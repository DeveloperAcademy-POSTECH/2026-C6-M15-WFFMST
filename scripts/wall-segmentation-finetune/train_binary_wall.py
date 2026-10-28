from __future__ import annotations

import argparse
import io
import json
import random
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import matplotlib.pyplot as plt
import numpy as np
import segmentation_models_pytorch as smp
import torch
from datasets import Image as DatasetImage
from datasets import load_dataset
from huggingface_hub import hf_hub_download
from PIL import Image
from safetensors.torch import load_file, save_file
from torch.utils.data import DataLoader, IterableDataset

from binary_wall_data import (
    add_free_space_distractors,
    build_letterboxed_blocked_mask,
    enhance_training_image,
    letterbox_image,
    native_tile_pair,
)


DATASET_ID = "phungpx/cubicassa5k-coco"
BASE_MODEL_ID = "Yytsi/floorplan-to-3d-walls"
IMAGE_SIZE = 512
MAX_SOURCE_PIXELS = 40_000_000
MEAN = torch.tensor([0.485, 0.456, 0.406]).reshape(3, 1, 1)
STD = torch.tensor([0.229, 0.224, 0.225]).reshape(3, 1, 1)


def _matching_state(model: torch.nn.Module, state: dict[str, torch.Tensor]) -> dict[str, torch.Tensor]:
    candidates = (
        state,
        {key.removeprefix("model."): value for key, value in state.items()},
        {key.removeprefix("module."): value for key, value in state.items()},
    )
    keys = set(model.state_dict())
    matching = next((candidate for candidate in candidates if set(candidate) == keys), None)
    if matching is None:
        raise RuntimeError("Published checkpoint does not match U-Net ResNet-34 architecture")
    return matching


def load_base_model() -> torch.nn.Module:
    model = smp.Unet(encoder_name="resnet34", encoder_weights=None, in_channels=3, classes=4)
    path = hf_hub_download(repo_id=BASE_MODEL_ID, filename="best.safetensors")
    state = load_file(path)
    model.load_state_dict(_matching_state(model, state), strict=True)
    return model


def make_binary_model(base: torch.nn.Module) -> torch.nn.Module:
    binary = smp.Unet(encoder_name="resnet34", encoder_weights=None, in_channels=3, classes=1)
    base_state = base.state_dict()
    binary_state = binary.state_dict()

    for key in binary_state:
        if key in base_state and binary_state[key].shape == base_state[key].shape:
            binary_state[key] = base_state[key]

    weight_key = "segmentation_head.0.weight"
    bias_key = "segmentation_head.0.bias"
    # Initialize blocked-vs-free from the published order: floor, wall, door, window.
    binary_state[weight_key] = (
        0.5 * (base_state[weight_key][1:2] + base_state[weight_key][3:4])
        - 0.5 * (base_state[weight_key][0:1] + base_state[weight_key][2:3])
    )
    binary_state[bias_key] = (
        0.5 * (base_state[bias_key][1:2] + base_state[bias_key][3:4])
        - 0.5 * (base_state[bias_key][0:1] + base_state[bias_key][2:3])
    )
    binary.load_state_dict(binary_state, strict=True)
    return binary


def _to_tensor(image: Image.Image) -> torch.Tensor:
    array = np.asarray(image, dtype=np.float32) / 255.0
    return torch.from_numpy(array).permute(2, 0, 1)


class CubiCasaBinaryStream(IterableDataset):
    def __init__(
        self,
        split: str,
        max_samples: int,
        seed: int,
        synthetic_probability: float,
        training: bool,
        native_tile_probability: float = 0.0,
        tile_wall_focus_probability: float = 0.75,
    ) -> None:
        self.split = split
        self.max_samples = max_samples
        self.seed = seed
        self.synthetic_probability = synthetic_probability
        self.training = training
        self.native_tile_probability = native_tile_probability
        self.tile_wall_focus_probability = tile_wall_focus_probability

    def __iter__(self):
        dataset = load_dataset(DATASET_ID, split=self.split, streaming=True)
        # Inspect source dimensions before PIL decodes rare 90MP outliers.
        dataset = dataset.cast_column("image", DatasetImage(decode=False))
        if self.training:
            dataset = dataset.shuffle(seed=self.seed, buffer_size=min(512, self.max_samples))
        dataset = dataset.take(self.max_samples)

        for index, sample in enumerate(dataset):
            if sample["width"] * sample["height"] > MAX_SOURCE_PIXELS:
                print(f"skip oversized source: {sample['file_name']} ({sample['width']}x{sample['height']})")
                continue
            image_record = sample["image"]
            if image_record.get("bytes") is not None:
                image = Image.open(io.BytesIO(image_record["bytes"])).convert("RGB")
            elif image_record.get("path") is not None:
                image = Image.open(image_record["path"]).convert("RGB")
            else:
                raise ValueError(f"image bytes/path missing: {sample['file_name']}")
            rng = random.Random(self.seed + index)
            if self.native_tile_probability > 0 and rng.random() < self.native_tile_probability:
                image, mask, _ = native_tile_pair(
                    image,
                    sample["annotations"],
                    IMAGE_SIZE,
                    rng,
                    wall_focus_probability=self.tile_wall_focus_probability,
                )
            else:
                mask = build_letterboxed_blocked_mask(
                    sample["width"], sample["height"], sample["annotations"], IMAGE_SIZE
                )
                image = letterbox_image(image, IMAGE_SIZE)
            distractor_mask = Image.new("L", image.size, 0)
            if rng.random() < self.synthetic_probability:
                synthetic = add_free_space_distractors(image, mask, rng)
                image = synthetic.image
                distractor_mask = synthetic.distractor_mask
            if self.training:
                image = enhance_training_image(image, rng)

            image_tensor = (_to_tensor(image) - MEAN) / STD
            mask_tensor = torch.from_numpy(np.asarray(mask, dtype=np.float32) / 255.0)[None, ...]
            distractor_tensor = torch.from_numpy(
                np.asarray(distractor_mask, dtype=np.float32) / 255.0
            )[None, ...]
            yield {
                "image": image_tensor,
                "mask": mask_tensor,
                "distractor": distractor_tensor,
                "file_name": sample["file_name"],
            }


def _soft_erode(mask: torch.Tensor) -> torch.Tensor:
    vertical = -torch.nn.functional.max_pool2d(-mask, (3, 1), stride=1, padding=(1, 0))
    horizontal = -torch.nn.functional.max_pool2d(-mask, (1, 3), stride=1, padding=(0, 1))
    return torch.minimum(vertical, horizontal)


def _soft_open(mask: torch.Tensor) -> torch.Tensor:
    eroded = _soft_erode(mask)
    return torch.nn.functional.max_pool2d(eroded, 3, stride=1, padding=1)


def soft_skeleton(mask: torch.Tensor, iterations: int = 10) -> torch.Tensor:
    skeleton = torch.relu(mask - _soft_open(mask))
    for _ in range(iterations):
        mask = _soft_erode(mask)
        delta = torch.relu(mask - _soft_open(mask))
        skeleton = skeleton + torch.relu(delta - skeleton * delta)
    return skeleton


def soft_cldice_loss(probability: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
    predicted_skeleton = soft_skeleton(probability)
    target_skeleton = soft_skeleton(target)
    smooth = 1.0
    topology_precision = (
        (predicted_skeleton * target).sum(dim=(1, 2, 3)) + smooth
    ) / (predicted_skeleton.sum(dim=(1, 2, 3)) + smooth)
    topology_sensitivity = (
        (target_skeleton * probability).sum(dim=(1, 2, 3)) + smooth
    ) / (target_skeleton.sum(dim=(1, 2, 3)) + smooth)
    cldice = (2 * topology_precision * topology_sensitivity) / (
        topology_precision + topology_sensitivity + 1e-6
    )
    return 1 - cldice.mean()


def binary_loss(
    logits: torch.Tensor,
    target: torch.Tensor,
    cldice_weight: float = 0.0,
) -> torch.Tensor:
    bce = torch.nn.functional.binary_cross_entropy_with_logits(logits, target)
    probability = torch.sigmoid(logits)
    intersection = (probability * target).sum(dim=(1, 2, 3))
    denominator = probability.sum(dim=(1, 2, 3)) + target.sum(dim=(1, 2, 3))
    dice_loss = 1 - ((2 * intersection + 1) / (denominator + 1)).mean()
    return bce + dice_loss + cldice_weight * soft_cldice_loss(probability, target)


@dataclass
class Metrics:
    iou: float
    precision: float
    recall: float
    distractor_false_positive_rate: float


@torch.inference_mode()
def evaluate(
    model: torch.nn.Module,
    loader: DataLoader,
    device: torch.device,
    baseline: bool,
) -> Metrics:
    model.eval()
    true_positive = false_positive = false_negative = 0
    distractor_positive = distractor_total = 0
    for batch in loader:
        image = batch["image"].to(device)
        target = batch["mask"].to(device) > 0.5
        distractor = batch["distractor"].to(device) > 0.5
        logits = model(image)
        if baseline:
            classes = torch.softmax(logits, dim=1)
            prediction = (classes[:, 1:2] + classes[:, 3:4]) >= 0.5
        else:
            prediction = torch.sigmoid(logits) >= 0.5
        true_positive += torch.logical_and(prediction, target).sum().item()
        false_positive += torch.logical_and(prediction, ~target).sum().item()
        false_negative += torch.logical_and(~prediction, target).sum().item()
        distractor_positive += torch.logical_and(prediction, distractor).sum().item()
        distractor_total += distractor.sum().item()

    return Metrics(
        iou=true_positive / max(1, true_positive + false_positive + false_negative),
        precision=true_positive / max(1, true_positive + false_positive),
        recall=true_positive / max(1, true_positive + false_negative),
        distractor_false_positive_rate=distractor_positive / max(1, distractor_total),
    )


def train_epoch(
    model: torch.nn.Module,
    loader: DataLoader,
    optimizer: torch.optim.Optimizer,
    device: torch.device,
    cldice_weight: float,
) -> float:
    model.train()
    total_loss = 0.0
    batches = 0
    for batch in loader:
        image = batch["image"].to(device)
        target = batch["mask"].to(device)
        optimizer.zero_grad(set_to_none=True)
        loss = binary_loss(model(image), target, cldice_weight=cldice_weight)
        loss.backward()
        optimizer.step()
        total_loss += loss.item()
        batches += 1
    return total_loss / max(1, batches)


@torch.inference_mode()
def save_comparison(
    base_model: torch.nn.Module,
    binary_model: torch.nn.Module,
    loader: DataLoader,
    device: torch.device,
    output: Path,
) -> None:
    batch = next(iter(loader))
    count = min(4, len(batch["file_name"]))
    image = batch["image"].to(device)
    base_probability = torch.softmax(base_model(image), dim=1)
    base_probability = base_probability[:, 1] + base_probability[:, 3]
    tuned_probability = torch.sigmoid(binary_model(image))[:, 0]

    figure, axes = plt.subplots(count, 4, figsize=(16, 4 * count), squeeze=False)
    for index in range(count):
        restored = image[index].cpu() * STD + MEAN
        restored = restored.permute(1, 2, 0).clamp(0, 1).numpy()
        panels: list[tuple[Any, str, str | None]] = [
            (restored, f"Input\n{batch['file_name'][index]}", None),
            (batch["mask"][index, 0].numpy(), "Target blocked", "gray"),
            (base_probability[index].cpu().numpy(), "Baseline", "magma"),
            (tuned_probability[index].cpu().numpy(), "Fine-tuned", "magma"),
        ]
        for axis, (panel, title, color_map) in zip(axes[index], panels, strict=True):
            axis.imshow(panel, cmap=color_map, vmin=0, vmax=1)
            axis.set_title(title)
            axis.axis("off")
    figure.tight_layout()
    figure.savefig(output, dpi=160)
    plt.close(figure)


class CoreMLBinaryWrapper(torch.nn.Module):
    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer("mean", MEAN[None, ...])
        self.register_buffer("std", STD[None, ...])

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return torch.sigmoid(self.model((image - self.mean) / self.std))


def export_coreml(model: torch.nn.Module, output: Path) -> Path:
    import coremltools as ct

    wrapper = CoreMLBinaryWrapper(model.cpu().eval()).eval()
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    traced = torch.jit.trace(wrapper, example, strict=True)
    package = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name="image",
                shape=example.shape,
                color_layout=ct.colorlayout.RGB,
                scale=1 / 255.0,
            )
        ],
        outputs=[ct.TensorType(name="blockedProbability", dtype=np.float16)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    package_path = output / "BinaryWallSegmentation-FP16.mlpackage"
    package.author = "CubiCasa5K binary blocked-mask experiment for CQB"
    package.short_description = "wall + window blocked probability; floor + door free"
    package.user_defined_metadata["source_dataset"] = DATASET_ID
    package.user_defined_metadata["source_model"] = BASE_MODEL_ID
    package.save(package_path)
    shutil.make_archive(str(package_path), "zip", root_dir=package_path)
    return package_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--learning-rate", type=float, default=1e-4)
    parser.add_argument("--max-train-samples", type=int, default=3_000)
    parser.add_argument("--max-valid-samples", type=int, default=300)
    parser.add_argument("--synthetic-probability", type=float, default=0.75)
    parser.add_argument("--native-tile-probability", type=float, default=0.0)
    parser.add_argument("--tile-wall-focus-probability", type=float, default=0.75)
    parser.add_argument("--cldice-weight", type=float, default=0.0)
    parser.add_argument("--seed", type=int, default=20261028)
    parser.add_argument("--output", type=Path, default=Path("outputs/binary-finetune"))
    parser.add_argument("--export-coreml", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.native_tile_probability <= 1:
        parser.error("--native-tile-probability must be between 0 and 1")
    if not 0 <= args.tile_wall_focus_probability <= 1:
        parser.error("--tile-wall-focus-probability must be between 0 and 1")
    if args.cldice_weight < 0:
        parser.error("--cldice-weight must be nonnegative")
    args.output.mkdir(parents=True, exist_ok=True)
    torch.manual_seed(args.seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"device={device}; dataset is streamed from {DATASET_ID}")

    train_dataset = CubiCasaBinaryStream(
        "train",
        args.max_train_samples,
        args.seed,
        args.synthetic_probability,
        training=True,
        native_tile_probability=args.native_tile_probability,
        tile_wall_focus_probability=args.tile_wall_focus_probability,
    )
    valid_dataset = CubiCasaBinaryStream(
        "valid",
        args.max_valid_samples,
        args.seed + 100_000,
        synthetic_probability=1.0,
        training=False,
    )
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, num_workers=0)
    valid_loader = DataLoader(valid_dataset, batch_size=args.batch_size, num_workers=0)
    valid_tile_loader: DataLoader | None = None
    if args.native_tile_probability > 0:
        valid_tile_dataset = CubiCasaBinaryStream(
            "valid",
            args.max_valid_samples,
            args.seed + 200_000,
            synthetic_probability=1.0,
            training=False,
            native_tile_probability=1.0,
            tile_wall_focus_probability=args.tile_wall_focus_probability,
        )
        valid_tile_loader = DataLoader(
            valid_tile_dataset, batch_size=args.batch_size, num_workers=0
        )

    base_model = load_base_model().to(device).eval()
    binary_model = make_binary_model(base_model).to(device)
    baseline_metrics = evaluate(base_model, valid_loader, device, baseline=True)
    print("baseline", asdict(baseline_metrics))
    baseline_tile_metrics = None
    if valid_tile_loader is not None:
        baseline_tile_metrics = evaluate(base_model, valid_tile_loader, device, baseline=True)
        print("baseline_native_tile", asdict(baseline_tile_metrics))

    optimizer = torch.optim.AdamW(binary_model.parameters(), lr=args.learning_rate)
    best_iou = -1.0
    history: list[dict[str, Any]] = []
    checkpoint = args.output / "BinaryWallSegmentation.safetensors"
    for epoch in range(1, args.epochs + 1):
        loss = train_epoch(
            binary_model,
            train_loader,
            optimizer,
            device,
            cldice_weight=args.cldice_weight,
        )
        metrics = evaluate(binary_model, valid_loader, device, baseline=False)
        record = {
            "epoch": epoch,
            "loss": loss,
            **asdict(metrics),
        }
        tile_metrics = None
        if valid_tile_loader is not None:
            tile_metrics = evaluate(binary_model, valid_tile_loader, device, baseline=False)
            record["native_tile"] = asdict(tile_metrics)
        history.append(record)
        print(record)
        selection_iou = metrics.iou
        if tile_metrics is not None:
            selection_iou = 0.5 * (metrics.iou + tile_metrics.iou)
        if selection_iou > best_iou:
            best_iou = selection_iou
            save_file({key: value.detach().cpu() for key, value in binary_model.state_dict().items()}, checkpoint)

    binary_model.load_state_dict(load_file(checkpoint), strict=True)
    final_metrics = evaluate(binary_model, valid_loader, device, baseline=False)
    final_tile_metrics = None
    if valid_tile_loader is not None:
        final_tile_metrics = evaluate(binary_model, valid_tile_loader, device, baseline=False)
    report = {
        "experiment": "wall+window blocked; door/floor/other free; synthetic free-space distractors",
        "dataset": DATASET_ID,
        "base_model": BASE_MODEL_ID,
        "arguments": {key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
        "baseline": asdict(baseline_metrics),
        "fine_tuned": asdict(final_metrics),
        "history": history,
    }
    if baseline_tile_metrics is not None and final_tile_metrics is not None:
        report["baseline_native_tile"] = asdict(baseline_tile_metrics)
        report["fine_tuned_native_tile"] = asdict(final_tile_metrics)
    (args.output / "metrics.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    save_comparison(base_model, binary_model, valid_loader, device, args.output / "comparison.png")
    if args.export_coreml:
        export_coreml(binary_model, args.output)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

