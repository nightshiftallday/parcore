#!/usr/bin/env bash
# Tries every TypedNDataSkidBuffer variant in variants/ with xvlog, xelab, an xsim run of tb.sv and
# a Vivado RTL elaboration (synth_design -rtl, no synthesis) of syn_top.sv, and prints one result
# line per variant. Logs land in results/. Needs Vivado's settings64.sh sourced.
# WRAP=1 simulates the skid buffers behind a wrapper's interface ports (as in TypedDictionary2) and
# skips the Vivado step; RESULTS=<dir> changes the log directory.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PARCORE_ROOT:-$(cd "$HERE/../../.." && pwd)}"
HDL="$ROOT/libstf/hardware/src/hdl"
OUT="${RESULTS:-$HERE/results}"
rm -rf "$OUT" && mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

if ! ldconfig -p | grep -q 'libtinfo\.so\.5 '; then
    mkdir -p compat
    ln -s /lib/x86_64-linux-gnu/libtinfo.so.6 compat/libtinfo.so.5
    export LD_LIBRARY_PATH="$WORK/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

python3 "$HERE/gen_variants.py"
python3 "$HERE/../skid_regout/skid_unit.py" extract "$HDL/util/skid_buffer.sv" "$WORK/skid_buffer.sv"
COMMON=("$ROOT/.slang/generated/lynx_pkg.sv" "$HDL/common.sv" "$HDL/data_interfaces.sv" "$WORK/skid_buffer.sv")

# ${WRAP:+-d WRAP} runs the testbench with both skid buffers behind wrap's interface ports.
declare -A SIM
for v in "$HERE"/variants/*.sv; do
    name=$(basename "$v" .sv)
    mkdir -p "$name" && cd "$name"
    if ! xvlog -sv -i "$HDL" ${WRAP:+-d WRAP} "${COMMON[@]}" "$v" "$HERE/tb.sv" > "$OUT/${name}_xvlog.log" 2>&1; then
        SIM[$name]="xvlog: $(grep -m1 ERROR "$OUT/${name}_xvlog.log" | sed 's/ \[\/.*//')"
    elif ! xelab tb -s tb > "$OUT/${name}_xelab.log" 2>&1; then
        SIM[$name]="xelab: $(grep -m1 ERROR "$OUT/${name}_xelab.log" | sed 's/ \[\/.*//')"
    else
        timeout 600 xsim tb -R > "$OUT/${name}_xsim.log" 2>&1
        SIM[$name]="xsim: $(grep -m1 -E '^(PASS|FAIL)|Fatal' "$OUT/${name}_xsim.log" || echo 'no result')"
    fi
    cd "$WORK"
done

if [[ -n ${WRAP:-} ]]; then
    for v in "$HERE"/variants/*.sv; do
        name=$(basename "$v" .sv)
        printf '%-22s | %s\n' "$name" "${SIM[$name]}"
    done
    exit 0
fi

cat > rtl.tcl <<TCL
foreach v [lsort [glob $HERE/variants/*.sv]] {
    set name [file rootname [file tail \$v]]
    create_project -in_memory -part xcu55c-fsvh2892-2L-e
    read_verilog -sv [list ${COMMON[*]} \$v $HERE/syn_top.sv]
    if {[catch {synth_design -rtl -top syn_top -include_dirs [list $HDL]} err]} {
        puts "RTL \$name FAIL"
    } else {
        puts "RTL \$name OK"
    }
    close_project
}
TCL
vivado -mode batch -nojournal -log "$OUT/vivado_rtl.log" -source rtl.tcl > /dev/null 2>&1
declare -A RTL
while read -r _ name status; do RTL[$name]=$status; done < <(grep '^RTL ' "$OUT/vivado_rtl.log")

for v in "$HERE"/variants/*.sv; do
    name=$(basename "$v" .sv)
    printf '%-22s | %-70s | vivado rtl: %s\n' "$name" "${SIM[$name]}" "${RTL[$name]:-no result}"
done
