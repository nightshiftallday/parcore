#!/usr/bin/env bash
# Out-of-context synthesis, placement, one phys_opt_design pass and routing of TypedDictionary with
# its inline id conversion (VARIANT 0) or with IndexTypeConverter (VARIANT 1), with utilization and
# timing reports in reports/.
# Usage: run_synth.sh [VARIANT] [ID_BITS] [PERIOD_NS]     (defaults: 0 18 4.0, i.e. 250 MHz)
# Needs .slang/generated/lynx_pkg.sv (scripts/gen_slang_pkg.py). Sources are taken from PARCORE_ROOT
# (default: the checkout containing this script).
set -euo pipefail

VARIANT="${1:-0}"
ID_BITS="${2:-18}"
PERIOD="${3:-4.0}"
PART="xcu55c-fsvh2892-2L-e"

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PARCORE_ROOT:-$(cd "$HERE/../../.." && pwd)}"
NAME=$([[ $VARIANT == 0 ]] && echo inline || echo itc)
OUT="$HERE/build_${NAME}_w${ID_BITS}_p${PERIOD}"
mkdir -p "$OUT"

if ! command -v vivado > /dev/null; then
    source "${VIVADO_SETTINGS:-/mnt/labstore/Xilinx/Vivado/2024.2/settings64.sh}"
fi

# Vivado 2024.2 links against libtinfo.so.5, which Ubuntu 24.04 no longer ships.
if ! ldconfig -p | grep -q 'libtinfo\.so\.5 '; then
    mkdir -p "$OUT/compat"
    ln -sf /lib/x86_64-linux-gnu/libtinfo.so.6 "$OUT/compat/libtinfo.so.5"
    export LD_LIBRARY_PATH="$OUT/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

cd "$OUT"
vivado -mode batch -nojournal -log vivado.log \
    -source "$HERE/synth.tcl" \
    -tclargs "$ROOT" "$HERE" "$OUT" "$PART" "$PERIOD" "$VARIANT" "$ID_BITS"

echo
grep '^RESULT' vivado.log
echo "Reports: $OUT/reports"
