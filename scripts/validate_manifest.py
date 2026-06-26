#!/usr/bin/env python3
"""Validate deterministic generated artifact manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_dir", type=Path)
    args = parser.parse_args()

    manifest_path = args.build_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="ascii"))

    errors: list[str] = []
    for name, expected in manifest["files"].items():
        path = args.build_dir / name
        if not path.is_file():
            errors.append(f"{name}: missing")
            continue

        data = path.read_bytes()
        actual = {
            "bytes": len(data),
            "lines": data.count(b"\n"),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
        for key, actual_value in actual.items():
            if actual_value != expected[key]:
                errors.append(f"{name}: {key} got={actual_value} expected={expected[key]}")

    for path in args.build_dir.iterdir():
        allowed_sim_outputs = {"sim.vvp", "wave.vcd"}
        if path.name in manifest["files"] or path.name == "manifest.json":
            continue
        if path.is_file() and path.name in allowed_sim_outputs:
            continue
        errors.append(f"{path.name}: extra generated path before simulation")

    if errors:
        for error in errors:
            print(f"ERROR: manifest {error}")
        raise SystemExit(1)

    print(f"manifest OK: {args.build_dir}")


if __name__ == "__main__":
    main()
