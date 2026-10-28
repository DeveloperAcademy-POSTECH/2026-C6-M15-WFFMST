#!/usr/bin/env python3
"""Extract normalized wall segments with the OpenAI Responses API."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path


PROMPT = """
Analyze this 2D floor plan. Extract only physical walls and wall-like fixed barriers.
Return wall centerline segments in image coordinates normalized from 0 to 1000, where
(0, 0) is the top-left corner. `thickness` uses the same normalized scale. Split a wall
at every passable opening such as a door or open doorway so the opening remains free.
Ignore text, dimensions, furniture, fixtures, floor patterns, shadows, and paper edges.
Prefer several accurate straight segments over tracing decorative noise. Return no more
than 256 segments.
""".strip()


SCHEMA = {
    "type": "object",
    "properties": {
        "segments": {
            "type": "array",
            "maxItems": 256,
            "items": {
                "type": "object",
                "properties": {
                    "x1": {"type": "integer", "minimum": 0, "maximum": 1000},
                    "y1": {"type": "integer", "minimum": 0, "maximum": 1000},
                    "x2": {"type": "integer", "minimum": 0, "maximum": 1000},
                    "y2": {"type": "integer", "minimum": 0, "maximum": 1000},
                    "thickness": {"type": "integer", "minimum": 1, "maximum": 200},
                },
                "required": ["x1", "y1", "x2", "y2", "thickness"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["segments"],
    "additionalProperties": False,
}


def load_api_key() -> str:
    if api_key := os.environ.get("OPENAI_API_KEY"):
        return api_key

    result = subprocess.run(
        [
            "security", "find-generic-password", "-w",
            "-s", "wffmst-openai-api-key",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    raise SystemExit(
        "OPENAI_API_KEY is not set and wffmst-openai-api-key was not found in macOS Keychain"
    )


def image_data_url(path: Path) -> str:
    mime_type = mimetypes.guess_type(path.name)[0] or "image/png"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime_type};base64,{encoded}"


def extract_output_text(response: dict) -> str:
    for item in response.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "output_text":
                return content["text"]
    raise RuntimeError("The response did not contain output_text")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model", default="gpt-6-astra")
    args = parser.parse_args()

    api_key = load_api_key()

    payload = {
        "model": args.model,
        "input": [{
            "role": "user",
            "content": [
                {"type": "input_text", "text": PROMPT},
                {"type": "input_image", "image_url": image_data_url(args.image), "detail": "original"},
            ],
        }],
        "text": {
            "format": {
                "type": "json_schema",
                "name": "wall_extraction",
                "strict": True,
                "schema": SCHEMA,
            }
        },
    }
    request = urllib.request.Request(
        "https://api.openai.com/v1/responses",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )

    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=180) as result:
            response = json.load(result)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"OpenAI API returned HTTP {error.code}: {detail}") from error

    extraction = json.loads(extract_output_text(response))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(extraction, ensure_ascii=False, indent=2), encoding="utf-8")
    metadata = {
        "model": response.get("model", args.model),
        "response_id": response.get("id"),
        "elapsed_seconds": round(time.perf_counter() - started, 3),
        "usage": response.get("usage"),
    }
    args.output.with_suffix(".metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )


if __name__ == "__main__":
    main()

