#!/usr/bin/env bash
# Runs type_eq_tb.sv in xsim and elaborates it with Vivado (synth_design -rtl, no synthesis), once
# as is and once with +define+FIRE, where one ASSERT_ELAB on unequal types must stop elaboration.
# Needs Vivado's settings64.sh sourced.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PARCORE_ROOT:-$(cd "$HERE/../../.." && pwd)}"
HDL="$ROOT/libstf/hardware/src/hdl"
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

SRCS=("$ROOT/.slang/generated/lynx_pkg.sv" "$HDL/common.sv" "$HDL/data_interfaces.sv" "$HERE/type_eq_tb.sv")

for mode in normal fire; do
    define=()
    [[ $mode == fire ]] && define=(-d FIRE)
    echo "== xsim $mode"
    if ! xvlog -sv -i "$HDL" "${define[@]}" "${SRCS[@]}" > "$OUT/xvlog_$mode.log" 2>&1; then
        grep -m3 ERROR "$OUT/xvlog_$mode.log"; continue
    fi
    if ! xelab type_eq_tb -s "tb_$mode" > "$OUT/xelab_$mode.log" 2>&1; then
        echo "xelab failed:"; grep -m3 -E 'ERROR|Error' "$OUT/xelab_$mode.log"; continue
    fi
    xsim "tb_$mode" -R > "$OUT/xsim_$mode.log" 2>&1
    grep -E '^CASE|^DONE|Error|Assertion' "$OUT/xsim_$mode.log"
done

cat > rtl.tcl <<TCL
foreach mode {normal fire} {
    create_project -in_memory -part xcu55c-fsvh2892-2L-e
    read_verilog -sv [list ${SRCS[*]}]
    set defs {}
    if {\$mode eq "fire"} { set defs [list -verilog_define FIRE] }
    if {[catch {synth_design -rtl -top type_eq_tb -include_dirs [list $HDL] {*}\$defs} err]} {
        puts "RTL \$mode FAIL"
    } else {
        puts "RTL \$mode OK"
    }
    close_project
}
TCL
vivado -mode batch -nojournal -log "$OUT/vivado_rtl.log" -source rtl.tcl > /dev/null 2>&1
echo "== vivado"
grep -E '^RTL |ELAB|Assertion failed' "$OUT/vivado_rtl.log" | sed 's/ \[\/.*//' | sort | uniq -c
