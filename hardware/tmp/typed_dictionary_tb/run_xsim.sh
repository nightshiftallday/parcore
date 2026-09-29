#!/usr/bin/env bash
# Standalone xsim runs of typed_dictionary_tb for both id conversion variants (inline doubling in
# TypedDictionary, and IndexTypeConverter), each once with random stalls (correctness) and once
# without (+NOSTALL, cycle counts). Results land in results/.
# Needs Vivado's settings64.sh sourced and .slang/generated/lynx_pkg.sv (scripts/gen_slang_pkg.py).
# Sources are taken from PARCORE_ROOT (default: the checkout containing this script), so the script
# also works from a worktree whose libstf submodule is not populated.
set -euo pipefail

TB="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PARCORE_ROOT:-$(cd "$TB/../../.." && pwd)}"
HDL="$ROOT/libstf/hardware/src/hdl"
OUT="$TB/results"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# Vivado 2024.2's xsim links against libtinfo.so.5, which Ubuntu 24.04 no longer ships; without it
# xsim fails with "Failed to load feature 'simulator'". libtinfo.so.6 is a drop-in replacement.
if ! ldconfig -p | grep -q 'libtinfo\.so\.5 '; then
    mkdir -p compat
    ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 compat/libtinfo.so.5
    export LD_LIBRARY_PATH="$WORK/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

SRCS=(
    "$ROOT/.slang/generated/lynx_pkg.sv"
    "$HDL/common.sv"
    "$HDL/data_interfaces.sv"
    "$HDL/util/"*.sv
    "$HDL/crossbar/"*.sv
    "$HDL/stream/data_width_converter.sv"
    "$HDL/dict/deduplicate_stage.sv"
    "$HDL/dict/deduplicate.sv"
    "$HDL/dict/duplicate.sv"
    "$HDL/dict/dictionary_bank.sv"
    "$HDL/dict/dictionary.sv"
    "$HDL/dict/index_type_converter.sv"
    "$TB/typed_dictionary_inline.sv"
    "$TB/typed_dictionary_itc.sv"
)

xvhdl -2008 "$HDL/fifo/fifo.vhd" "$HDL/fifo/multi_insert_fifo.vhd" > "$OUT/xvhdl.log"

for variant in inline itc; do
    define=()
    [[ $variant == itc ]] && define=(-d DUT_ITC)
    xvlog -sv -i "$HDL" "${define[@]}" "${SRCS[@]}" "$TB/typed_dictionary_tb.sv" > "$OUT/xvlog_$variant.log"
    xelab -debug typical typed_dictionary_tb -s "tb_$variant" > "$OUT/xelab_$variant.log"

    for mode in stall nostall; do
        args=()
        [[ $mode == nostall ]] && args=(-testplusarg NOSTALL)
        log="$OUT/xsim_${variant}_${mode}.log"
        xsim "tb_$variant" -R "${args[@]}" -testplusarg "CSV=$OUT/metrics_${variant}_${mode}.csv" \
            > "$log"
        grep -E '^(SUMMARY|PASS|FAIL)' "$log"
        grep -q '^PASS' "$log"
    done
done
