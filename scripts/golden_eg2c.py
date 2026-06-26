#!/usr/bin/env python3
"""Generate deterministic e-G2C simulation targets and golden outputs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def int8(value: int) -> int:
    value &= 0xFF
    return value - 0x100 if value & 0x80 else value


def sat_int8(value: int) -> int:
    return max(-128, min(127, value))


def hex_int8(value: int) -> str:
    return f"{value & 0xFF:02x}"


def write_hex(path: Path, values: list[int]) -> None:
    path.write_text("".join(f"{hex_int8(value)}\n" for value in values), encoding="ascii")


def gen_conv(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    in_c = 2
    out_c = 3
    k_h = 3
    k_w = 3
    pad_h = 1
    pad_w = 1

    input_count = in_h * in_w * in_c
    weight_count = k_h * k_w * in_c * out_c

    input_act = [((idx * 5 + 3) % 17) - 8 for idx in range(input_count)]
    weights = [((idx * 7 + 1) % 9) - 4 for idx in range(weight_count)]
    expected: list[int] = []

    for oy in range(in_h):
        for ox in range(in_w):
            for oc in range(out_c):
                acc = 0
                for ky in range(k_h):
                    for kx in range(k_w):
                        iy = oy + ky - pad_h
                        ix = ox + kx - pad_w
                        for ic in range(in_c):
                            if 0 <= iy < in_h and 0 <= ix < in_w:
                                act_idx = (iy * in_w + ix) * in_c + ic
                                weight_idx = (((ky * k_w + kx) * in_c + ic) * out_c) + oc
                                acc += input_act[act_idx] * weights[weight_idx]
                expected.append(sat_int8(acc))

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)

    target = {
        "target": "conv",
        "operation": "dense_conv2d",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": in_c},
            "kernel": {"h": k_h, "w": k_w},
            "output": {"h": in_h, "w": in_w, "c": out_c},
        },
        "layout": {
            "activation": "NHWC",
            "weight": "kh,kw,cin,cout",
            "flattening": "last dimension contiguous",
        },
        "arithmetic": {
            "activation": "signed int8 two's-complement",
            "weight": "signed int8 two's-complement",
            "accumulator": "signed int32",
            "output": "signed int8 saturated from accumulator",
            "scale_zero_point": None,
        },
        "convolution": {
            "stride": {"h": 1, "w": 1},
            "padding": {"mode": "explicit_zero", "top": pad_h, "bottom": pad_h, "left": pad_w, "right": pad_w},
            "activation_function": "linear",
        },
        "expected_cycles": in_h * in_w * out_c * k_h * k_w * in_c,
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=["conv"])
    parser.add_argument("--build-dir", required=True, type=Path)
    args = parser.parse_args()

    if args.target == "conv":
        gen_conv(args.build_dir)


if __name__ == "__main__":
    main()
