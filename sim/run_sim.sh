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

Options:
  wave     Also write sim/build/<target>/wave.vcd when supported
USAGE
}

if [[ -z "$target" ]]; then
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
mkdir -p "$build_dir"

rtl_files=(
    "$root_dir/rtl/eg2c_act_mem.v"
    "$root_dir/rtl/eg2c_weight_mem.v"
    "$root_dir/rtl/eg2c_index_mem.v"
    "$root_dir/rtl/eg2c_instr_mem.v"
    "$root_dir/rtl/eg2c_input_act_buffer.v"
    "$root_dir/rtl/eg2c_output_act_buffer.v"
    "$root_dir/rtl/eg2c_mac_lane.v"
    "$root_dir/rtl/eg2c_mac_array.v"
    "$root_dir/rtl/eg2c_controller.v"
    "$root_dir/rtl/eg2c_top.v"
)

iverilog -Wall -g2012 -I"$root_dir/rtl" -o "$build_dir/sim.vvp" "${rtl_files[@]}" "$tb_file"

vvp_args=()
if [[ "$wave_arg" == "wave" || "$wave_arg" == "--wave" ]]; then
    vvp_args+=("+WAVE")
fi

vvp "$build_dir/sim.vvp" "${vvp_args[@]}"
