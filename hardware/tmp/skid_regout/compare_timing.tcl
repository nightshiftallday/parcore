# Compares routed checkpoints of the TypedDictionary builds: WNS, near-critical endpoint counts,
# logic-level histogram of the 1000 worst paths, and the 5 worst paths.
# Usage: vivado -mode batch -source compare_timing.tcl -tclargs <label>=<post_route.dcp> ...

foreach arg $argv {
    lassign [split $arg =] label dcp
    open_checkpoint $dcp

    set paths [get_timing_paths -setup -max_paths 1000 -nworst 1]
    set lt3 0
    set lt5 0
    array unset levels
    foreach p $paths {
        set s [get_property SLACK $p]
        if {$s < 0.3} { incr lt3 }
        if {$s < 0.5} { incr lt5 }
        set l [get_property LOGIC_LEVELS $p]
        if {![info exists levels($l)]} { set levels($l) 0 }
        incr levels($l)
    }
    set hist {}
    foreach l [lsort -integer [array names levels]] { lappend hist "$l:$levels($l)" }
    set dict [get_cells -hierarchical -filter {ORIG_REF_NAME == Dictionary || REF_NAME == Dictionary}]
    set id_pins [get_pins -of_objects $dict -filter {NAME =~ "*in_ids*"}]
    set id_wns [get_property SLACK [get_timing_paths -setup -max_paths 1 -through $id_pins]]
    puts "TIMING $label wns=[get_property SLACK [lindex $paths 0]] id_port=$id_wns \
endpoints_lt_0.3=$lt3 endpoints_lt_0.5=$lt5 levels(top1000)=[join $hist ,]"

    foreach p [lrange [get_timing_paths -setup -max_paths 5 -nworst 1] 0 4] {
        set from [get_property NAME [get_property STARTPOINT_PIN $p]]
        set to   [get_property NAME [get_property ENDPOINT_PIN $p]]
        regsub -all {gen_(inline|itc)\.inst_dut/inst_dictionary/} $from {} from
        regsub -all {gen_(inline|itc)\.inst_dut/inst_dictionary/} $to {} to
        puts [format "PATH %s slack=%.3f levels=%d delay=%.3f route=%.3f  %s -> %s" $label \
            [get_property SLACK $p] [get_property LOGIC_LEVELS $p] [get_property DATAPATH_DELAY $p] \
            [get_property DATAPATH_NET_DELAY $p] $from $to]
    }
    close_design
}
