from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import numpy as np
import segmentation_models_pytorch as smp
import torch
from huggingface_hub import hf_hub_download
from safetensors.torch import load_file

from convert_common import save_fp16_and_optional_int8


MODEL_ID = "Yytsi/floorplan-to-3d-walls"
IMAGE_SIZE = 512


class WallSegmentationModel(torch.nn.Module):
    """Adds the model's ImageNet normalization to the exported graph."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model
        self.register_buffer(
            "mean", torch.tensor([0.485, 0.456, 0.406]).reshape(1, 3, 1, 1)
        )
        self.register_buffer(
            "std", torch.tensor([0.229, 0.224, 0.225]).reshape(1, 3, 1, 1)
        )

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return self.model((image - self.mean) / self.std)


def _load_model() -> torch.nn.Module:
    weights_path = hf_hub_download(repo_id=MODEL_ID, filename="best.safetensors")
    state = load_file(weights_path)
    model = smp.Unet(
        encoder_name="resnet34",
        encoder_weights=None,
        in_channels=3,
        classes=4,
    )

    candidates = [
        state,
        {key.removeprefix("model."): value for key, value in state.items()},
        {key.removeprefix("module."): value for key, value in state.items()},
    ]
    model_keys = set(model.state_dict())
    matching = next((candidate for candidate in candidates if set(candidate) == model_keys), None)
    if matching is None:
        missing = sorted(model_keys - set(state))[:10]
        unexpected = sorted(set(state) - model_keys)[:10]
        raise RuntimeError(
            f"Checkpoint keys do not match the published architecture. "
            f"missing={missing}, unexpected={unexpected}"
        )
    model.load_state_dict(matching, strict=True)
    return WallSegmentationModel(model.eval()).eval()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("outputs"))
    parser.add_argument("--int8", action="store_true")
    args = parser.parse_args()

    model = _load_model()
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    with torch.inference_mode():
        traced = torch.jit.trace(model, example, strict=True)
        traced_output = traced(example)
        eager_output = model(example)
        max_error = torch.max(torch.abs(traced_output - eager_output)).item()
    if max_error > 1e-4:
        raise RuntimeError(f"TorchScript trace changed model output: max_error={max_error}")

    coreml_model = ct.convert(
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
        outputs=[ct.TensorType(name="classLogits", dtype=np.float16)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    coreml_model.author = "Yytsi/floorplan-to-3d-walls; converted for CQB PoC"
    coreml_model.short_description = "512px floor-plan segmentation: floor, wall, door, window"
    coreml_model.user_defined_metadata["class_labels"] = "floor,wall,door,window"
    coreml_model.user_defined_metadata["source_model"] = MODEL_ID
    save_fp16_and_optional_int8(
        coreml_model,
        args.output,
        base_name="FloorPlanUNetResNet34",
        include_int8=args.int8,
    )


if __name__ == "__main__":
    main()
