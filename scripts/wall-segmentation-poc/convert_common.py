from __future__ import annotations

import json
import shutil
from pathlib import Path

import coremltools as ct
import coremltools.optimize as cto


def save_fp16_and_optional_int8(
    model: ct.models.MLModel,
    output_directory: Path,
    base_name: str,
    include_int8: bool,
) -> None:
    output_directory.mkdir(parents=True, exist_ok=True)
    fp16_path = output_directory / f"{base_name}-FP16.mlpackage"
    model.save(fp16_path)
    _write_manifest(fp16_path, precision="FP16")
    _archive(fp16_path)

    if not include_int8:
        return

    config = cto.coreml.OptimizationConfig(
        global_config=cto.coreml.OpLinearQuantizerConfig(
            mode="linear_symmetric",
            dtype="int8",
        )
    )
    int8_model = cto.coreml.linear_quantize_weights(model, config=config)
    int8_path = output_directory / f"{base_name}-W8A16.mlpackage"
    int8_model.save(int8_path)
    _write_manifest(int8_path, precision="INT8 weights / FP16 activations")
    _archive(int8_path)


def _write_manifest(package_path: Path, precision: str) -> None:
    manifest = {
        "name": package_path.stem,
        "precision": precision,
        "package_bytes": sum(
            item.stat().st_size for item in package_path.rglob("*") if item.is_file()
        ),
    }
    output = package_path.parent / f"{package_path.stem}.json"
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def _archive(package_path: Path) -> None:
    archive_base = package_path.parent / package_path.name
    shutil.make_archive(str(archive_base), "zip", package_path.parent, package_path.name)
