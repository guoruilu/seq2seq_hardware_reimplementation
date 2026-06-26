#!/usr/bin/env python3
"""Generate deterministic e-G2C simulation targets and golden outputs."""

from __future__ import annotations

import argparse
import hashlib
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


def write_hex32(path: Path, values: list[int]) -> None:
    path.write_text("".join(f"{value & 0xFFFFFFFF:08x}\n" for value in values), encoding="ascii")


def _dw_trace_coord4(value: int) -> int:
    if value < -8:
        return 0
    if value > 7:
        return 0xF
    return (value + 8) & 0xF


def _dw_trace_unsigned4(value: int) -> int:
    if value < 0:
        return 0xF
    if value > 14:
        return 0xE
    return value & 0xF


def _dw_trace_descriptor(
    lane: int,
    oy: int,
    ox: int,
    ch: int,
    ky: int,
    kx: int,
    active: bool,
) -> int:
    return (
        (_dw_trace_unsigned4(lane) << 24)
        | (_dw_trace_coord4(oy) << 20)
        | (_dw_trace_coord4(ox) << 16)
        | (_dw_trace_unsigned4(ch) << 12)
        | (_dw_trace_unsigned4(ky) << 8)
        | (_dw_trace_unsigned4(kx) << 4)
        | (1 if active else 0)
    )


def _dw_trace_mix(current: int, descriptor: int) -> int:
    current &= 0xFFFFFFFF
    rotated = ((current << 5) & 0xFFFFFFFF) | (current >> 27)
    return (rotated ^ descriptor) & 0xFFFFFFFF


def _dw_term_active(
    in_h: int,
    in_w: int,
    channels: int,
    k_h: int,
    k_w: int,
    pad_h: int,
    pad_w: int,
    oy: int,
    ox: int,
    ch: int,
    ky: int,
    kx: int,
) -> bool:
    if not (0 <= oy < in_h and 0 <= ox < in_w and 0 <= ch < channels and 0 <= ky < k_h and 0 <= kx < k_w):
        return False
    iy = oy + ky - pad_h
    ix = ox + kx - pad_w
    return 0 <= iy < in_h and 0 <= ix < in_w


def _dw_trace_signature(
    cycle_index: int,
    lanes: list[tuple[int, int, int, int, int, int]],
    in_h: int,
    in_w: int,
    channels: int,
    k_h: int,
    k_w: int,
    pad_h: int,
    pad_w: int,
) -> int:
    value = (0x9E3779B9 ^ cycle_index) & 0xFFFFFFFF
    for lane, oy, ox, ch, ky, kx in lanes:
        active = _dw_term_active(in_h, in_w, channels, k_h, k_w, pad_h, pad_w, oy, ox, ch, ky, kx)
        value = _dw_trace_mix(value, _dw_trace_descriptor(lane, oy, ox, ch, ky, kx, active))
    return value


def write_manifest(build_dir: Path) -> None:
    files: dict[str, dict[str, int | str]] = {}
    for path in sorted(build_dir.iterdir()):
        if not path.is_file() or path.name == "manifest.json":
            continue
        data = path.read_bytes()
        files[path.name] = {
            "bytes": len(data),
            "lines": data.count(b"\n"),
            "sha256": hashlib.sha256(data).hexdigest(),
        }
    manifest = {
        "format": "eg2c-golden-manifest-v1",
        "files": files,
    }
    (build_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="ascii")


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


def gen_dw(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    channels = 4
    k_h = 3
    k_w = 3
    pad_h = 1
    pad_w = 1

    input_count = in_h * in_w * channels
    weight_count = k_h * k_w * channels

    input_act = [((idx * 3 + 2) % 19) - 9 for idx in range(input_count)]
    weights = [((idx * 5 + 4) % 11) - 5 for idx in range(weight_count)]
    expected: list[int] = []

    for oy in range(in_h):
        for ox in range(in_w):
            for ch in range(channels):
                acc = 0
                for ky in range(k_h):
                    for kx in range(k_w):
                        iy = oy + ky - pad_h
                        ix = ox + kx - pad_w
                        if 0 <= iy < in_h and 0 <= ix < in_w:
                            act_idx = (iy * in_w + ix) * channels + ch
                            weight_idx = (ky * k_w + kx) * channels + ch
                            acc += input_act[act_idx] * weights[weight_idx]
                expected.append(sat_int8(acc))

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)

    target = {
        "target": "dw",
        "operation": "depthwise_conv2d",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": channels},
            "kernel": {"h": k_h, "w": k_w},
            "output": {"h": in_h, "w": in_w, "c": channels},
        },
        "layout": {
            "activation": "NHWC",
            "weight": "kh,kw,channel",
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
        "expected_cycles": in_h * in_w * channels * k_h * k_w,
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def gen_pw(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    in_c = 4
    out_c = 5

    input_count = in_h * in_w * in_c
    weight_count = in_c * out_c

    input_act = [((idx * 7 + 1) % 23) - 11 for idx in range(input_count)]
    weights = [((idx * 3 + 6) % 13) - 6 for idx in range(weight_count)]
    expected: list[int] = []

    for oy in range(in_h):
        for ox in range(in_w):
            for oc in range(out_c):
                acc = 0
                for ic in range(in_c):
                    act_idx = (oy * in_w + ox) * in_c + ic
                    weight_idx = ic * out_c + oc
                    acc += input_act[act_idx] * weights[weight_idx]
                expected.append(sat_int8(acc))

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)

    target = {
        "target": "pw",
        "operation": "pointwise_conv2d",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": in_c},
            "kernel": {"h": 1, "w": 1},
            "output": {"h": in_h, "w": in_w, "c": out_c},
        },
        "layout": {
            "activation": "NHWC",
            "weight": "cin,cout",
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
            "padding": {"mode": "none"},
            "activation_function": "linear",
        },
        "expected_cycles": in_h * in_w * out_c * in_c,
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def div_trunc_toward_zero(value: int, divisor: int) -> int:
    sign = -1 if value < 0 else 1
    return sign * (abs(value) // divisor)


def gen_pool(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    channels = 3
    pool_h = 2
    pool_w = 2
    stride_h = 2
    stride_w = 2
    out_h = 2
    out_w = 2

    input_count = in_h * in_w * channels
    input_act = [((idx * 11 + 5) % 31) - 15 for idx in range(input_count)]
    expected: list[int] = []

    for oy in range(out_h):
        for ox in range(out_w):
            for ch in range(channels):
                acc = 0
                for py in range(pool_h):
                    for px in range(pool_w):
                        iy = oy * stride_h + py
                        ix = ox * stride_w + px
                        act_idx = (iy * in_w + ix) * channels + ch
                        acc += input_act[act_idx]
                expected.append(sat_int8(div_trunc_toward_zero(acc, pool_h * pool_w)))

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", [])
    write_hex(build_dir / "expected.hex", expected)

    target = {
        "target": "pool",
        "operation": "avg_pool2d",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": channels},
            "pool": {"h": pool_h, "w": pool_w},
            "output": {"h": out_h, "w": out_w, "c": channels},
        },
        "layout": {
            "activation": "NHWC",
            "flattening": "last dimension contiguous",
        },
        "arithmetic": {
            "activation": "signed int8 two's-complement",
            "accumulator": "signed int32",
            "division": "integer divide truncating toward zero",
            "output": "signed int8 saturated from averaged accumulator",
        },
        "pooling": {
            "type": "average",
            "stride": {"h": stride_h, "w": stride_w},
            "padding": {"mode": "none"},
        },
        "expected_cycles": out_h * out_w * channels * pool_h * pool_w,
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def dense_conv_same(
    input_act: list[int],
    weights: list[int],
    in_h: int,
    in_w: int,
    in_c: int,
    out_c: int,
    k_h: int,
    k_w: int,
    pad_h: int,
    pad_w: int,
) -> list[int]:
    output: list[int] = []
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
                output.append(sat_int8(acc))
    return output


def gen_conv_sparse(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    in_c = 2
    out_c = 3
    k_h = 3
    k_w = 3
    pad_h = 1
    pad_w = 1
    sparse_vec_len = k_w * in_c
    sparse_vec_count = k_h

    input_count = in_h * in_w * in_c
    weight_count = k_h * k_w * in_c * out_c

    input_act = [((idx * 5 + 3) % 17) - 8 for idx in range(input_count)]
    weights = [((idx * 7 + 1) % 9) - 4 for idx in range(weight_count)]

    def weight_index(ky: int, kx: int, ic: int, oc: int) -> int:
        return (((ky * k_w + kx) * in_c + ic) * out_c) + oc

    for oc in range(out_c):
        for ky in range(k_h):
            if (oc + ky) % 3 == 1:
                for kx in range(k_w):
                    for ic in range(in_c):
                        weights[weight_index(ky, kx, ic, oc)] = 0

    vector_valid: list[int] = []
    for oc in range(out_c):
        for ky in range(k_h):
            any_nonzero = False
            for kx in range(k_w):
                for ic in range(in_c):
                    any_nonzero |= weights[weight_index(ky, kx, ic, oc)] != 0
            vector_valid.append(int(any_nonzero))

    expected = dense_conv_same(input_act, weights, in_h, in_w, in_c, out_c, k_h, k_w, pad_h, pad_w)

    dense_cycles = in_h * in_w * out_c * k_h * k_w * in_c
    active_cycles = 0
    skipped_vectors = 0
    for _oy in range(in_h):
        for _ox in range(in_w):
            for oc in range(out_c):
                for vec in range(sparse_vec_count):
                    if vector_valid[oc * sparse_vec_count + vec]:
                        active_cycles += sparse_vec_len
                    else:
                        skipped_vectors += 1
    total_sparse_cycles = active_cycles + skipped_vectors

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)
    (build_dir / "vector_valid.bin").write_text("".join(f"{bit:b}\n" for bit in vector_valid), encoding="ascii")
    write_hex32(build_dir / "expected_stats.hex", [dense_cycles, active_cycles, skipped_vectors, total_sparse_cycles])

    target = {
        "target": "conv_sparse",
        "operation": "normal_conv2d_with_vector_wise_sparse_weight_schedule",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": in_c},
            "kernel": {"h": k_h, "w": k_w},
            "output": {"h": in_h, "w": in_w, "c": out_c},
        },
        "layout": {
            "activation": "NHWC",
            "weight": "kh,kw,cin,cout",
            "vector_valid": "oc-major kernel rows; each vector covers one ky row across kx and cin",
        },
        "sparse_schedule": {
            "sparse_vector_length": sparse_vec_len,
            "sparse_vectors_per_output_channel": sparse_vec_count,
            "valid_rule": "valid iff at least one weight in the vector is nonzero",
            "skip_rule": "invalid all-zero weight vector consumes one skip cycle per output pixel and output channel",
            "dense_equivalent_cycles": dense_cycles,
            "active_sparse_cycles": active_cycles,
            "skipped_vectors": skipped_vectors,
            "total_sparse_cycles": total_sparse_cycles,
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
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def pointwise_conv2d(input_act: list[int], weights: list[int], in_h: int, in_w: int, in_c: int, out_c: int) -> list[int]:
    output: list[int] = []
    for oy in range(in_h):
        for ox in range(in_w):
            for oc in range(out_c):
                acc = 0
                for ic in range(in_c):
                    act_idx = (oy * in_w + ox) * in_c + ic
                    weight_idx = ic * out_c + oc
                    acc += input_act[act_idx] * weights[weight_idx]
                output.append(sat_int8(acc))
    return output


def gen_pw_sparse(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    in_c = 5
    out_c = 5
    sparse_vec_len = 3
    sparse_vec_count = (in_c + sparse_vec_len - 1) // sparse_vec_len

    input_count = in_h * in_w * in_c
    weight_count = in_c * out_c

    input_act = [((idx * 7 + 1) % 23) - 11 for idx in range(input_count)]
    weights = [((idx * 3 + 6) % 13) - 6 for idx in range(weight_count)]

    def weight_index(ic: int, oc: int) -> int:
        return ic * out_c + oc

    for oc in range(out_c):
        for vec in range(sparse_vec_count):
            if (oc + vec) % 2 == 1:
                for elem in range(sparse_vec_len):
                    ic = vec * sparse_vec_len + elem
                    if ic < in_c:
                        weights[weight_index(ic, oc)] = 0

    vector_valid: list[int] = []
    vector_actual_len: list[int] = []
    for oc in range(out_c):
        for vec in range(sparse_vec_count):
            any_nonzero = False
            actual_len = 0
            for elem in range(sparse_vec_len):
                ic = vec * sparse_vec_len + elem
                if ic < in_c:
                    actual_len += 1
                    any_nonzero |= weights[weight_index(ic, oc)] != 0
            vector_actual_len.append(actual_len)
            vector_valid.append(int(any_nonzero))

    expected = pointwise_conv2d(input_act, weights, in_h, in_w, in_c, out_c)

    dense_cycles = in_h * in_w * out_c * in_c
    active_cycles = 0
    skipped_vectors = 0
    for _oy in range(in_h):
        for _ox in range(in_w):
            for oc in range(out_c):
                for vec in range(sparse_vec_count):
                    flat = oc * sparse_vec_count + vec
                    if vector_valid[flat]:
                        active_cycles += vector_actual_len[flat]
                    else:
                        skipped_vectors += 1
    total_sparse_cycles = active_cycles + skipped_vectors

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)
    (build_dir / "vector_valid.bin").write_text("".join(f"{bit:b}\n" for bit in vector_valid), encoding="ascii")
    write_hex32(build_dir / "expected_stats.hex", [dense_cycles, active_cycles, skipped_vectors, total_sparse_cycles])

    target = {
        "target": "pw_sparse",
        "operation": "pointwise_conv2d_with_vector_wise_sparse_weight_schedule",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": in_c},
            "kernel": {"h": 1, "w": 1},
            "output": {"h": in_h, "w": in_w, "c": out_c},
        },
        "layout": {
            "activation": "NHWC",
            "weight": "cin,cout",
            "vector_valid": "oc-major input-channel groups; each vector covers up to three weights",
        },
        "sparse_schedule": {
            "sparse_vector_length": sparse_vec_len,
            "sparse_vectors_per_output_channel": sparse_vec_count,
            "valid_rule": "valid iff at least one weight in the vector is nonzero",
            "skip_rule": "invalid all-zero weight vector consumes one skip cycle per output pixel and output channel",
            "dense_equivalent_cycles": dense_cycles,
            "active_sparse_cycles": active_cycles,
            "skipped_vectors": skipped_vectors,
            "total_sparse_cycles": total_sparse_cycles,
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
            "padding": {"mode": "none"},
            "activation_function": "linear",
        },
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def avg_pool2d(
    input_act: list[int],
    in_h: int,
    in_w: int,
    channels: int,
    pool_h: int,
    pool_w: int,
    stride_h: int,
    stride_w: int,
    out_h: int,
    out_w: int,
) -> list[int]:
    output: list[int] = []
    for oy in range(out_h):
        for ox in range(out_w):
            for ch in range(channels):
                acc = 0
                for py in range(pool_h):
                    for px in range(pool_w):
                        iy = oy * stride_h + py
                        ix = ox * stride_w + px
                        act_idx = (iy * in_w + ix) * channels + ch
                        acc += input_act[act_idx]
                output.append(sat_int8(div_trunc_toward_zero(acc, pool_h * pool_w)))
    return output


def gen_pipeline_dense(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    in_c = 2
    conv_out_c = 3
    pool_out_h = 2
    pool_out_w = 2
    k_h = 3
    k_w = 3
    pad_h = 1
    pad_w = 1

    input_count = in_h * in_w * in_c
    weight_count = k_h * k_w * in_c * conv_out_c

    input_act = [((idx * 13 + 2) % 29) - 14 for idx in range(input_count)]
    weights = [((idx * 5 + 8) % 15) - 7 for idx in range(weight_count)]
    conv_output = dense_conv_same(input_act, weights, in_h, in_w, in_c, conv_out_c, k_h, k_w, pad_h, pad_w)
    expected_normal = avg_pool2d(conv_output, in_h, in_w, conv_out_c, 2, 2, 2, 2, pool_out_h, pool_out_w)
    output_count = pool_out_h * pool_out_w * conv_out_c
    zero_output = [0 for _ in range(output_count)]
    programs = [
        {
            "name": "conv_pool_done",
            "program": [0x01000000, 0x04000000, 0xFF000000, 0x00000000],
            "expected_output": expected_normal,
            "expected_error": 0,
            "expected_ops": 2,
            "expected_cycles": 912,
        },
        {
            "name": "done_only",
            "program": [0xFF000000, 0x00000000, 0x00000000, 0x00000000],
            "expected_output": zero_output,
            "expected_error": 0,
            "expected_ops": 0,
            "expected_cycles": 0,
        },
        {
            "name": "nop_conv_pool_done",
            "program": [0x00000000, 0x01000000, 0x04000000, 0xFF000000],
            "expected_output": expected_normal,
            "expected_error": 0,
            "expected_ops": 2,
            "expected_cycles": 912,
        },
        {
            "name": "illegal_opcode",
            "program": [0x7E000000, 0xFF000000, 0x00000000, 0x00000000],
            "expected_output": zero_output,
            "expected_error": 1,
            "expected_ops": 0,
            "expected_cycles": 0,
        },
    ]
    instr = [word for case in programs for word in case["program"]]
    expected = [value for case in programs for value in case["expected_output"]]
    expected_status = [
        value
        for case in programs
        for value in (case["expected_error"], case["expected_ops"], case["expected_cycles"])
    ]

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)
    (build_dir / "expected_status.hex").write_text(
        "".join(f"{value:08x}\n" for value in expected_status),
        encoding="ascii",
    )
    (build_dir / "instr.hex").write_text("".join(f"{word:08x}\n" for word in instr), encoding="ascii")

    target = {
        "target": "pipeline_dense",
        "operation": "instruction_driven_dense_pipeline",
        "case_count": len(programs),
        "instr_count_per_case": 4,
        "programs": [
            {
                "case": idx,
                "name": case["name"],
                "program": [f"0x{word:08x}" for word in case["program"]],
                "expected_error": case["expected_error"],
                "expected_ops": case["expected_ops"],
                "expected_cycles": case["expected_cycles"],
            }
            for idx, case in enumerate(programs)
        ],
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": in_c},
            "conv_output": {"h": in_h, "w": in_w, "c": conv_out_c},
            "pipeline_output": {"h": pool_out_h, "w": pool_out_w, "c": conv_out_c},
        },
        "layout": {
            "activation": "NHWC",
            "conv_weight": "kh,kw,cin,cout",
            "flattening": "last dimension contiguous",
        },
        "arithmetic": {
            "activation": "signed int8 two's-complement",
            "weight": "signed int8 two's-complement",
            "accumulator": "signed int32",
            "output": "signed int8 saturated after each layer",
        },
        "layers": [
            {
                "opcode": "CONV",
                "kernel": {"h": k_h, "w": k_w},
                "stride": {"h": 1, "w": 1},
                "padding": {"mode": "explicit_zero", "top": pad_h, "bottom": pad_h, "left": pad_w, "right": pad_w},
                "activation_function": "linear",
            },
            {
                "opcode": "POOL",
                "pool": {"h": 2, "w": 2},
                "stride": {"h": 2, "w": 2},
                "padding": {"mode": "none"},
                "division": "integer divide truncating toward zero",
            },
        ],
        "expected_status_hex_fields": ["expected_error", "expected_ops", "expected_cycles"],
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def gen_branch(build_dir: Path) -> None:
    out_count = 8
    cases = [
        {"score": 10, "threshold": 20},
        {"score": 33, "threshold": 20},
        {"score": -4, "threshold": -4},
        {"score": -1, "threshold": 1},
        {"score": 1, "threshold": -1},
    ]
    coarse: list[int] = []
    precise: list[int] = []
    expected: list[int] = []
    expected_path: list[int] = []

    for case_idx, case in enumerate(cases):
        case_coarse = [((case_idx * 17 + elem * 3 + 1) % 31) - 15 for elem in range(out_count)]
        case_precise = [((case_idx * 19 + elem * 5 + 4) % 37) - 18 for elem in range(out_count)]
        abnormal = int(case["score"] >= case["threshold"])
        coarse.extend(case_coarse)
        precise.extend(case_precise)
        expected.extend(case_precise if abnormal else case_coarse)
        expected_path.append(abnormal)

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "scores.hex", [case["score"] for case in cases])
    write_hex(build_dir / "thresholds.hex", [case["threshold"] for case in cases])
    write_hex(build_dir / "coarse.hex", coarse)
    write_hex(build_dir / "precise.hex", precise)
    write_hex(build_dir / "expected.hex", expected)
    (build_dir / "expected_path.bin").write_text("".join(f"{bit:b}\n" for bit in expected_path), encoding="ascii")

    target = {
        "target": "branch",
        "operation": "detector_threshold_branch",
        "rule": "score >= threshold selects precise/abnormal path; otherwise coarse/normal path",
        "case_count": len(cases),
        "output_count": out_count,
        "arithmetic": {
            "score": "signed int8 two's-complement",
            "threshold": "signed int8 two's-complement",
            "comparison": "signed greater-than-or-equal",
        },
        "cases": [
            {
                "case": idx,
                "score": case["score"],
                "threshold": case["threshold"],
                "expected_path": "precise" if expected_path[idx] else "coarse",
            }
            for idx, case in enumerate(cases)
        ],
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def _adapt_interval_for_score(score: int, boundaries: list[int]) -> int | None:
    for idx in range(len(boundaries) - 1):
        lower = boundaries[idx]
        upper = boundaries[idx + 1]
        if idx == len(boundaries) - 2:
            if lower <= score <= upper:
                return idx
        elif lower <= score < upper:
            return idx
    return None


def _adapt_midpoint(lower: int, upper: int) -> int:
    total = lower + upper
    if total >= 0:
        return total // 2
    return -((-total) // 2)


def gen_adapt(build_dir: Path) -> None:
    interval_count = 8
    counter_width = 16
    boundaries = [-64, -48, -32, -16, 0, 16, 32, 48, 64]
    cases = [
        {
            "name": "boundary_tie_low_index",
            "initial_threshold": 7,
            "scores": [
                -65,
                -64, -63, -49,
                -48, -47, -33,
                -32,
                -16, -15, -1,
                0,
                16, 17, 31,
                32, 33, 47,
                48, 49, 50, 64,
                65,
            ],
        },
        {
            "name": "restart_unique_empty_interval",
            "initial_threshold": -12,
            "scores": [-64, -48, -32, -16, 0, 16, 48, 65, 64],
        },
    ]

    flat_scores: list[int] = []
    case_lengths: list[int] = []
    initial_thresholds: list[int] = []
    expected_histogram: list[int] = []
    expected_stats: list[int] = []
    case_summaries = []

    for case_idx, case in enumerate(cases):
        histogram = [0 for _ in range(interval_count)]
        ignored = 0
        scores = case["scores"]
        for score in scores:
            interval = _adapt_interval_for_score(score, boundaries)
            if interval is None:
                ignored += 1
            else:
                histogram[interval] += 1

        min_count = min(histogram)
        selected_interval = next(idx for idx, count in enumerate(histogram) if count == min_count)
        threshold = _adapt_midpoint(boundaries[selected_interval], boundaries[selected_interval + 1])
        accepted = sum(histogram)

        flat_scores.extend(scores)
        case_lengths.append(len(scores))
        initial_thresholds.append(case["initial_threshold"])
        expected_histogram.extend(histogram)
        expected_stats.extend([threshold, selected_interval, accepted, ignored, len(scores)])
        case_summaries.append(
            {
                "case": case_idx,
                "name": case["name"],
                "initial_threshold": case["initial_threshold"],
                "score_count": len(scores),
                "accepted_samples": accepted,
                "ignored_samples": ignored,
                "histogram": histogram,
                "selected_interval": selected_interval,
                "updated_threshold": threshold,
            }
        )

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "scores.hex", flat_scores)
    write_hex(build_dir / "boundaries.hex", boundaries)
    write_hex(build_dir / "initial_thresholds.hex", initial_thresholds)
    write_hex32(build_dir / "case_lengths.hex", case_lengths)
    write_hex32(build_dir / "expected_histogram.hex", expected_histogram)
    write_hex32(build_dir / "expected_stats.hex", expected_stats)

    target = {
        "target": "adapt",
        "operation": "threshold_adaptation",
        "case_count": len(cases),
        "interval_count": interval_count,
        "counter_width": counter_width,
        "score_format": "signed int8 two's-complement",
        "threshold_format": "signed int8 two's-complement",
        "interval_rule": "lower bound inclusive, upper bound exclusive, except the last interval includes its upper bound",
        "out_of_range_rule": "scores outside the sensitive range are ignored by histogram counters",
        "argmin_tie_rule": "select the lowest interval index among equal minimum counters",
        "midpoint_rule": "integer midpoint truncating toward zero",
        "start_rule": "start is accepted only on a rising edge while the engine is idle",
        "update_score_valid_rule": "if update and score_valid are asserted together, the score is counted before argmin and snapshot",
        "counter_overflow_rule": "histogram counters saturate at their maximum value instead of wrapping",
        "sensitive_range": {"min": boundaries[0], "max": boundaries[-1]},
        "boundaries": boundaries,
        "stats_hex_fields_per_case": [
            "updated_threshold",
            "selected_interval",
            "accepted_samples",
            "ignored_samples",
            "total_samples",
        ],
        "cases": case_summaries,
    }
    encoded = json.dumps(target, indent=2) + "\n"
    (build_dir / "target.json").write_text(encoded, encoding="ascii")
    (build_dir / "adapt_target.json").write_text(encoded, encoding="ascii")


def gen_sparse(build_dir: Path) -> None:
    act_count = 16
    vec_count = 5
    vec_len = 3

    input_act = [((idx * 9 + 4) % 25) - 12 for idx in range(act_count)]
    indices = [
        0, 3, 7,
        0, 0, 0,
        2, 5, 11,
        1, 4, 8,
        0, 0, 0,
    ]
    weights = [
        3, -2, 4,
        0, 0, 0,
        -5, 2, 1,
        6, -3, 2,
        0, 0, 0,
    ]
    vector_valid = [1, 0, 1, 1, 0]

    dense_acc = 0
    active_cycles = 0
    skipped_vectors = 0
    for vec in range(vec_count):
        if not vector_valid[vec]:
            skipped_vectors += 1
            continue
        for elem in range(vec_len):
            flat = vec * vec_len + elem
            dense_acc += input_act[indices[flat]] * weights[flat]
            active_cycles += 1

    dense_cycles = vec_count * vec_len
    total_cycles = active_cycles + skipped_vectors
    output = sat_int8(dense_acc)

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    (build_dir / "indices.hex").write_text("".join(f"{idx:04x}\n" for idx in indices), encoding="ascii")
    write_hex(build_dir / "weights.hex", weights)
    (build_dir / "vector_valid.bin").write_text("".join(f"{bit:b}\n" for bit in vector_valid), encoding="ascii")
    write_hex(build_dir / "expected.hex", [output])
    stats = [dense_acc & 0xFFFFFFFF, active_cycles, skipped_vectors, dense_cycles, total_cycles]
    (build_dir / "expected_stats.hex").write_text("".join(f"{value:08x}\n" for value in stats), encoding="ascii")

    target = {
        "target": "sparse",
        "operation": "vector_wise_sparse_mac",
        "shape": {
            "activation_count": act_count,
            "vector_count": vec_count,
            "vector_length": vec_len,
        },
        "layout": {
            "activation": "flat int8 activation vector",
            "indices": "vector-major sparse indices, one uint16 per sparse element",
            "weights": "vector-major signed int8 sparse weights",
            "vector_valid": "one bit per sparse vector; invalid vectors model skipped all-zero vectors",
        },
        "arithmetic": {
            "activation": "signed int8 two's-complement",
            "weight": "signed int8 two's-complement",
            "accumulator": "signed int32",
            "output": "signed int8 saturated from accumulator",
        },
        "reference": {
            "dense_accumulator": dense_acc,
            "expected_output": output,
            "active_sparse_cycles": active_cycles,
            "dense_equivalent_cycles": dense_cycles,
            "skipped_vectors": skipped_vectors,
            "total_sparse_cycles": total_cycles,
        },
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def gen_dw_reuse(build_dir: Path) -> None:
    in_h = 4
    in_w = 4
    channels = 4
    k_h = 3
    k_w = 3
    pad_h = 1
    pad_w = 1

    input_count = in_h * in_w * channels
    weight_count = k_h * k_w * channels

    input_act = [((idx * 5 + 7) % 27) - 13 for idx in range(input_count)]
    weights = [((idx * 7 + 3) % 13) - 6 for idx in range(weight_count)]

    expected: list[int] = []
    for oy in range(in_h):
        for ox in range(in_w):
            for ch in range(channels):
                acc = 0
                for ky in range(k_h):
                    for kx in range(k_w):
                        iy = oy + ky - pad_h
                        ix = ox + kx - pad_w
                        if 0 <= iy < in_h and 0 <= ix < in_w:
                            act_idx = (iy * in_w + ix) * channels + ch
                            weight_idx = (ky * k_w + kx) * channels + ch
                            acc += input_act[act_idx] * weights[weight_idx]
                expected.append(sat_int8(acc))

    simple_cycles = in_h * in_w * channels * k_h * k_w
    cir_cycles = in_h * in_w * channels * k_w
    drir_pair_count = (in_w + 1) // 2
    drir_cycles = in_h * channels * k_h * k_w * drir_pair_count

    active_products = 0
    for oy in range(in_h):
        for ox in range(in_w):
            for ch in range(channels):
                for ky in range(k_h):
                    for kx in range(k_w):
                        iy = oy + ky - pad_h
                        ix = ox + kx - pad_w
                        if 0 <= iy < in_h and 0 <= ix < in_w:
                            active_products += 1

    simple_active_slots = active_products
    cir_active_slots = active_products
    drir_active_slots = active_products
    simple_idle_slots = simple_cycles - simple_active_slots
    cir_idle_slots = cir_cycles * k_h - cir_active_slots
    drir_idle_slots = drir_cycles * 2 - drir_active_slots

    simple_trace: list[int] = []
    for cycle in range(simple_cycles):
        tmp = cycle
        kx = tmp % k_w
        tmp //= k_w
        ky = tmp % k_h
        tmp //= k_h
        ch = tmp % channels
        tmp //= channels
        ox = tmp % in_w
        tmp //= in_w
        oy = tmp
        simple_trace.append(
            _dw_trace_signature(cycle, [(0, oy, ox, ch, ky, kx)], in_h, in_w, channels, k_h, k_w, pad_h, pad_w)
        )

    cir_trace: list[int] = []
    for cycle in range(cir_cycles):
        tmp = cycle
        kx = tmp % k_w
        tmp //= k_w
        ch = tmp % channels
        tmp //= channels
        ix = tmp % in_w
        tmp //= in_w
        iy = tmp
        lanes = []
        for lane in range(k_h):
            ky = lane
            oy = iy - ky + pad_h
            ox = ix - kx + pad_w
            lanes.append((lane, oy, ox, ch, ky, kx))
        cir_trace.append(_dw_trace_signature(cycle, lanes, in_h, in_w, channels, k_h, k_w, pad_h, pad_w))

    drir_trace: list[int] = []
    for cycle in range(drir_cycles):
        tmp = cycle
        pair_idx = tmp % drir_pair_count
        tmp //= drir_pair_count
        kx = tmp % k_w
        tmp //= k_w
        ky = tmp % k_h
        tmp //= k_h
        ch = tmp % channels
        tmp //= channels
        oy = tmp
        lanes = []
        for lane in range(2):
            ox = pair_idx * 2 + lane
            lanes.append((lane, oy, ox, ch, ky, kx))
        drir_trace.append(_dw_trace_signature(cycle, lanes, in_h, in_w, channels, k_h, k_w, pad_h, pad_w))

    build_dir.mkdir(parents=True, exist_ok=True)
    write_hex(build_dir / "input_act.hex", input_act)
    write_hex(build_dir / "weights.hex", weights)
    write_hex(build_dir / "expected.hex", expected)
    write_hex32(
        build_dir / "expected_stats.hex",
        [
            simple_cycles,
            cir_cycles,
            drir_cycles,
            simple_active_slots,
            cir_active_slots,
            drir_active_slots,
            simple_idle_slots,
            cir_idle_slots,
            drir_idle_slots,
        ],
    )
    write_hex32(build_dir / "simple_trace.hex", simple_trace)
    write_hex32(build_dir / "cir_trace.hex", cir_trace)
    write_hex32(build_dir / "drir_trace.hex", drir_trace)

    target = {
        "target": "dw_reuse",
        "operation": "depthwise_conv2d_reuse_lane_assignment_schedule",
        "shape": {
            "input": {"h": in_h, "w": in_w, "c": channels},
            "kernel": {"h": k_h, "w": k_w},
            "output": {"h": in_h, "w": in_w, "c": channels},
        },
        "layout": {
            "activation": "NHWC",
            "weight": "kh,kw,channel",
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
        "schedule_model": {
            "mode": "parallel RTL instances for simple, CIR, and D-RIR",
            "simple_cycles": simple_cycles,
            "cir_cycles": cir_cycles,
            "drir_cycles": drir_cycles,
            "simple_active_slots": simple_active_slots,
            "cir_active_slots": cir_active_slots,
            "drir_active_slots": drir_active_slots,
            "simple_idle_slots": simple_idle_slots,
            "cir_idle_slots": cir_idle_slots,
            "drir_idle_slots": drir_idle_slots,
            "trace_files": {
                "simple": "simple_trace.hex",
                "cir": "cir_trace.hex",
                "drir": "drir_trace.hex",
            },
            "cir_lane_mapping": "one input activation position and one kernel column feed K_H output-row lanes",
            "drir_lane_mapping": "one output row/kernel term feeds two adjacent output-column lanes",
            "note": "Architecture-level lane-assignment schedule; not an ASIC cycle-accurate claim.",
        },
    }
    (build_dir / "target.json").write_text(json.dumps(target, indent=2) + "\n", encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "target",
        choices=[
            "conv",
            "dw",
            "pw",
            "pool",
            "pipeline_dense",
            "branch",
            "adapt",
            "sparse",
            "conv_sparse",
            "pw_sparse",
            "dw_reuse",
        ],
    )
    parser.add_argument("--build-dir", required=True, type=Path)
    args = parser.parse_args()

    if args.target == "conv":
        gen_conv(args.build_dir)
    elif args.target == "dw":
        gen_dw(args.build_dir)
    elif args.target == "pw":
        gen_pw(args.build_dir)
    elif args.target == "pool":
        gen_pool(args.build_dir)
    elif args.target == "pipeline_dense":
        gen_pipeline_dense(args.build_dir)
    elif args.target == "branch":
        gen_branch(args.build_dir)
    elif args.target == "adapt":
        gen_adapt(args.build_dir)
    elif args.target == "sparse":
        gen_sparse(args.build_dir)
    elif args.target == "conv_sparse":
        gen_conv_sparse(args.build_dir)
    elif args.target == "pw_sparse":
        gen_pw_sparse(args.build_dir)
    elif args.target == "dw_reuse":
        gen_dw_reuse(args.build_dir)

    write_manifest(args.build_dir)


if __name__ == "__main__":
    main()
