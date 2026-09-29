#!/usr/bin/env bash
# Compile-only check of the unit-test vfpga tops: elaborates the Coyote user logic stand-in
# (user_logic.sv) with the original typed_dict_test.sv and with typed_dict2_test.sv against all of
# libstf. It does not simulate. Needs Vivado's settings64.sh sourced.
# PARCORE_ROOT selects the checkout (or a copy) whose libstf/hardware/src is used; ORIG_TOP (default:
# that checkout's unit-tests/vfpga_tops/typed_dict_test.sv) and CYT_ROOT (default: its libstf/coyote)
# can point elsewhere when that is only a copy of the sources.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PARCORE_ROOT:-$(cd "$HERE/../../../.." && pwd)}"
LIBSTF="$ROOT/libstf"
HDL="$LIBSTF/hardware/src/hdl"
CYT="${CYT_ROOT:-$ROOT/libstf/coyote}/hw/hdl/pkg"
OUT="$HERE/results"
rm -rf "$OUT" && mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

if ! ldconfig -p | grep -q 'libtinfo\.so\.5 '; then
    mkdir -p compat
    ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 compat/libtinfo.so.5
    export LD_LIBRARY_PATH="$WORK/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

mapfile -t LIBSTF_SRCS < <(find "$HDL" -name '*.sv' ! -name common.sv ! -name data_interfaces.sv | sort)
SRCS=("$ROOT/.slang/generated/lynx_pkg.sv" "$CYT/axi_intf.sv" "$CYT/lynx_intf.sv"
      "$HDL/common.sv" "$HDL/data_interfaces.sv" "${LIBSTF_SRCS[@]}")

mapfile -t VHDL_SRCS < <(find "$HDL" -name '*.vhd' | sort)
xvhdl -2008 "${VHDL_SRCS[@]}" > "$OUT/xvhdl.log" 2>&1 || { echo "xvhdl failed"; exit 1; }
ORIG_TOP="${ORIG_TOP:-$LIBSTF/hardware/unit-tests/vfpga_tops/typed_dict_test.sv}"

status=0
for top in original:"$ORIG_TOP" \
           clone:"$HERE/../vfpga_tops/typed_dict2_test.sv"; do
    name=${top%%:*}
    file=${top#*:}
    mkdir -p "inc_$name"
    cp "$file" "inc_$name/vfpga_top.svh"
    if ! xvlog -sv -i "$WORK/inc_$name" -i "$HDL" -i "$CYT" "${SRCS[@]}" "$HERE/user_logic.sv" \
            > "$OUT/xvlog_$name.log" 2>&1; then
        echo "$name: xvlog failed"; grep ERROR "$OUT/xvlog_$name.log" | head -5; status=1; continue
    fi
    if ! xelab elab_top -s "elab_$name" > "$OUT/xelab_$name.log" 2>&1; then
        echo "$name: xelab failed"; grep ERROR "$OUT/xelab_$name.log" | head -5; status=1; continue
    fi
    echo "$name: elaborates"
done
exit $status
