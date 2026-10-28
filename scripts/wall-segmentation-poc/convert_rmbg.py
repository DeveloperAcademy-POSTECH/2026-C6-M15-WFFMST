from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

import coremltools as ct
import numpy as np
import torch
from transformers import AutoModelForImageSegmentation

from convert_common import save_fp16_and_optional_int8


MODEL_ID = "phungpx/RMBG-1.4-wall-segmentation-cubicassa"
IMAGE_SIZE = 1024


class WallProbabilityModel(torch.nn.Module):
    """Exports only RMBG's highest-resolution wall probability output."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        output: Any = self.model(image - 0.5)
        # The published custom model returns ([six probability maps], [features]).
        return output[0][0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("outputs"))
    parser.add_argument("--int8", action="store_true")
    args = parser.parse_args()

    source_model = AutoModelForImageSegmentation.from_pretrained(
        MODEL_ID,
        trust_remote_code=True,
    ).eval()
    model = WallProbabilityModel(source_model).eval()
    example = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    with torch.inference_mode():
        traced = torch.jit.trace(model, example, strict=False)
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
        outputs=[ct.TensorType(name="wallProbability", dtype=np.float16)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    coreml_model.author = f"{MODEL_ID}; converted for CQB PoC"
    coreml_model.short_description = "1024px binary wall probability segmentation"
    coreml_model.user_defined_metadata["recommended_threshold"] = "0.4"
    coreml_model.user_defined_metadata["source_model"] = MODEL_ID
    save_fp16_and_optional_int8(
        coreml_model,
        args.output,
        base_name="RMBGWallSegmentation",
        include_int8=args.int8,
    )


if __name__ == "__main__":
    main()
