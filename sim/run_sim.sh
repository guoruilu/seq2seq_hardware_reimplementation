#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${1:-}"
wave_arg="${2:-}"

usage() {
    cat <<USAGE
Usage: ./sim/run_sim.sh <target> [wave]

Targets:
  smoke    Compile the minimal e-G2C RTL shell and run the smoke test
  mac      Verify signed MAC lane and 32-lane MAC array arithmetic
  conv     Verify dense 3x3 normal convolution against Python golden output
  dw       Verify dense 3x3 depth-wise convolution against Python golden output
  pw       Verify dense 1x1 point-wise convolution against Python golden output
  pool     Verify average pooling against Python golden output
  pipeline_dense
           Verify instruction-driven dense toy programs, including error paths
  branch   Verify detector threshold branch between coarse and precise paths
  sparse   Verify vector-wise sparse activation selection and MAC work reduction
  conv_sparse
           Verify sparse-weight vector skipping inside normal-conv scheduling
  pw_sparse
           Verify sparse-weight vector skipping inside point-wise-conv scheduling
  dw_reuse Verify DW output equivalence and CIR/D-RIR schedule counters

Options:
  wave     Also write sim/build/<target>/wave.vcd when supported
USAGE
}

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    usage
    exit 2
fi

case "$target" in
    smoke)
        tb_file="$root_dir/tb/tb_smoke.v"
        ;;
    mac)
        tb_file="$root_dir/tb/tb_mac.v"
        ;;
    conv)
        tb_file="$root_dir/tb/tb_conv.v"
        ;;
    dw)
        tb_file="$root_dir/tb/tb_dw.v"
        ;;
    pw)
        tb_file="$root_dir/tb/tb_pw.v"
        ;;
    pool)
        tb_file="$root_dir/tb/tb_pool.v"
        ;;
    pipeline_dense)
        tb_file="$root_dir/tb/tb_pipeline_dense.v"
        ;;
    branch)
        tb_file="$root_dir/tb/tb_branch.v"
        ;;
    sparse)
        tb_file="$root_dir/tb/tb_sparse.v"
        ;;
    conv_sparse)
        tb_file="$root_dir/tb/tb_conv_sparse.v"
        ;;
    pw_sparse)
        tb_file="$root_dir/tb/tb_pw_sparse.v"
        ;;
    dw_reuse)
        tb_file="$root_dir/tb/tb_dw_reuse.v"
        ;;
    *)
        echo "Unknown target: $target" >&2
        usage >&2
        exit 2
        ;;
esac

if [[ -n "$wave_arg" && "$wave_arg" != "wave" && "$wave_arg" != "--wave" ]]; then
    echo "Unknown option: $wave_arg" >&2
    usage >&2
    exit 2
fi

build_dir="$root_dir/sim/build/$target"
rm -rf "$build_dir"
mkdir -p "$build_dir"
cd "$root_dir"

case "$target" in
    conv|dw|pw|pool|pipeline_dense|branch|sparse|conv_sparse|pw_sparse|dw_reuse)
        python3 "$root_dir/scripts/golden_eg2c.py" "$target" --build-dir "$build_dir"
        python3 "$root_dir/scripts/validate_manifest.py" "$build_dir"
        ;;
esac

rtl_files=(
    "$root_dir/rtl/eg2c_act_mem.v"
    "$root_dir/rtl/eg2c_weight_mem.v"
    "$root_dir/rtl/eg2c_index_mem.v"
    "$root_dir/rtl/eg2c_instr_mem.v"
    "$root_dir/rtl/eg2c_input_act_buffer.v"
    "$root_dir/rtl/eg2c_output_act_buffer.v"
    "$root_dir/rtl/eg2c_mac_lane.v"
    "$root_dir/rtl/eg2c_mac_array.v"
    "$root_dir/rtl/eg2c_dense_conv2d.v"
    "$root_dir/rtl/eg2c_dw_conv2d.v"
    "$root_dir/rtl/eg2c_pw_conv2d.v"
    "$root_dir/rtl/eg2c_avg_pool2d.v"
    "$root_dir/rtl/eg2c_dense_pipeline.v"
    "$root_dir/rtl/eg2c_detector_branch.v"
    "$root_dir/rtl/eg2c_sparse_selector.v"
    "$root_dir/rtl/eg2c_sparse_vector_mac.v"
    "$root_dir/rtl/eg2c_dw_reuse_conv2d.v"
    "$root_dir/rtl/eg2c_controller.v"
    "$root_dir/rtl/eg2c_top.v"
)

iverilog -Wall -g2012 -I"$root_dir/rtl" -o "$build_dir/sim.vvp" "${rtl_files[@]}" "$tb_file"

vvp_args=()
if [[ "$wave_arg" == "wave" || "$wave_arg" == "--wave" ]]; then
    vvp_args+=("+WAVE")
fi

vvp "$build_dir/sim.vvp" "${vvp_args[@]}"
