# Out-of-context implementation of td_synth_top for resource and timing evaluation.
# Invoked by run_synth.sh:
#   vivado -mode batch -source synth.tcl -tclargs <root> <here> <out> <part> <period> <variant> <id_bits>

lassign $argv ROOT HERE OUT PART PERIOD VARIANT ID_BITS

set HDL "$ROOT/libstf/hardware/src/hdl"
set TB  "$HERE/../typed_dictionary_tb"
file mkdir $OUT/reports

set_part $PART

read_vhdl -vhdl2008 [list $HDL/fifo/fifo.vhd $HDL/fifo/multi_insert_fifo.vhd]

# Several libstf files use lynxTypes/libstf names imported at file scope by an earlier file, which
# only resolves when all files share one compilation unit (as with a single xvlog call). Vivado
# synthesis compiles each file separately, so the sources are concatenated into one file.
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
        $TB/typed_dictionary_inline.sv \
        $TB/typed_dictionary_itc.sv \
        $HERE/td_synth_top.sv \
    ] \
]
set unit [open $OUT/sources_unit.sv w]
foreach src $srcs {
    set f [open $src r]
    puts $unit "// ---- $src"
    puts $unit [read $f]
    close $f
    # Files such as util/demultiplexer.sv use lynxTypes before any file imports it.
    if {[file tail $src] eq "lynx_pkg.sv"} { puts $unit "import lynxTypes::*;" }
}
close $unit
read_verilog -sv $OUT/sources_unit.sv

set xdc [open $OUT/clock.xdc w]
puts $xdc "create_clock -name clk -period $PERIOD \[get_ports clk\]"
close $xdc
read_xdc $OUT/clock.xdc

synth_design -top td_synth_top -part $PART -mode out_of_context \
    -include_dirs [list $HDL] \
    -generic VARIANT=$VARIANT -generic ID_BITS=$ID_BITS

report_utilization -hierarchical -file $OUT/reports/synth_utilization_hier.rpt
report_timing_summary -file $OUT/reports/synth_timing_summary.rpt
write_checkpoint -force $OUT/post_synth.dcp

opt_design
place_design
phys_opt_design

report_utilization -file $OUT/reports/place_utilization.rpt
report_utilization -hierarchical -file $OUT/reports/place_utilization_hier.rpt
report_timing_summary -max_paths 10 -file $OUT/reports/place_timing_summary.rpt
write_checkpoint -force $OUT/post_place.dcp

route_design

report_utilization -file $OUT/reports/route_utilization.rpt
report_utilization -hierarchical -file $OUT/reports/route_utilization_hier.rpt
report_timing_summary -max_paths 10 -file $OUT/reports/route_timing_summary.rpt
report_timing -max_paths 100 -nworst 10 -path_type full -input_pins \
    -file $OUT/reports/route_timing_paths.rpt

# Paths through the Dictionary's id port, i.e. through the id conversion in front of it (and the
# ready fed back to in_ids).
set dict [get_cells -hierarchical -filter {ORIG_REF_NAME == Dictionary || REF_NAME == Dictionary}]
set id_pins [get_pins -of_objects $dict -filter {NAME =~ "*in_ids*"}]
report_timing -through $id_pins -max_paths 20 -nworst 1 -path_type full -input_pins \
    -file $OUT/reports/route_timing_id_port.rpt
write_checkpoint -force $OUT/post_route.dcp

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set id_wns [get_property SLACK [get_timing_paths -through $id_pins -max_paths 1 -nworst 1 -setup]]
puts "RESULT variant=${VARIANT} period=${PERIOD}ns wns=${wns}ns id_port_wns=${id_wns}ns"
