#!/usr/bin/env bash
# Runs skid_buffer_tb against the original SkidBuffer (taken from SRC, default the libstf
# util/skid_buffer.sv) and against skid_buffer_regout.sv. Needs Vivado's settings64.sh sourced.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PARCORE_ROOT:-$(cd "$HERE/../../.." && pwd)}"
HDL="$ROOT/libstf/hardware/src/hdl"
SRC="${SRC:-$HDL/util/skid_buffer.sv}"
OUT="$HERE/results"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

if ! ldconfig -p | grep -q 'libtinfo\.so\.5 '; then
    mkdir -p compat
    ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 compat/libtinfo.so.5
    export LD_LIBRARY_PATH="$WORK/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

python3 "$HERE/skid_unit.py" extract "$SRC" original.sv
for variant in original regout; do
    skid=$([[ $variant == original ]] && echo "$WORK/original.sv" || echo "$HERE/skid_buffer_regout.sv")
    xvlog -sv -i "$HDL" "$ROOT/.slang/generated/lynx_pkg.sv" "$HDL/common.sv" "$HDL/data_interfaces.sv" \
        "$skid" "$HERE/skid_buffer_tb.sv" > "$OUT/skid_xvlog_$variant.log" \
        || { echo "$variant: xvlog failed, see $OUT/skid_xvlog_$variant.log"; exit 1; }
    xelab skid_buffer_tb -s "tb_$variant" > "$OUT/skid_xelab_$variant.log" \
        || { echo "$variant: xelab failed, see $OUT/skid_xelab_$variant.log"; exit 1; }
    xsim "tb_$variant" -R > "$OUT/skid_xsim_$variant.log"
    echo "== $variant"
    grep -E '^(STREAM|CAPACITY|COMB|BUBBLES|TRACE|PASS|FAIL)|^Error' "$OUT/skid_xsim_$variant.log" | head -12
done
