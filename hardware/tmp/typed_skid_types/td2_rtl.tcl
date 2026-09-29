# RTL elaboration (synth_design -rtl, no synthesis) of TypedDictionary2 from a libstf tree.
# Usage: vivado -mode batch -source td2_rtl.tcl -tclargs <parcore root> <out dir>
# The sources are concatenated into one compilation unit, as in ../typed_dictionary_synth/synth.tcl.

lassign $argv ROOT OUT
set HERE [file dirname [file normalize [info script]]]
set HDL "$ROOT/libstf/hardware/src/hdl"
file mkdir $OUT

set srcs [concat \
    [list $ROOT/.slang/generated/lynx_pkg.sv $HDL/common.sv $HDL/data_interfaces.sv] \
    [lsort [glob $HDL/util/*.sv]] \
    [lsort [glob $HDL/crossbar/*.sv]] \
    [list \
        $HDL/stream/data_width_converter.sv \
        $HDL/dict/deduplicate_stage.sv \
        $HDL/dict/deduplicate.sv \
        $HDL/dict/duplicate.sv \
        $HDL/dict/dictionary_bank.sv \
        $HDL/dict/dictionary.sv \
        $HDL/dict/index_type_converter.sv \
        $HDL/dict/typed_dictionary.sv \
        $HERE/td2_syn_top.sv \
    ] \
]
set unit [open $OUT/sources_unit.sv w]
foreach src $srcs {
    set f [open $src r]
    puts $unit "// ---- $src"
    puts $unit [read $f]
    close $f
    if {[file tail $src] eq "lynx_pkg.sv"} { puts $unit "import lynxTypes::*;" }
}
close $unit

create_project -in_memory -part xcu55c-fsvh2892-2L-e
read_vhdl -vhdl2008 [list $HDL/fifo/fifo.vhd $HDL/fifo/multi_insert_fifo.vhd]
read_verilog -sv $OUT/sources_unit.sv
if {[catch {synth_design -rtl -top td2_syn_top -include_dirs [list $HDL]} err]} {
    puts "TD2_RTL FAIL"
} else {
    puts "TD2_RTL OK"
}
