open_checkpoint build_synth/checkpoints/shell_routed.dcp
report_timing -delay_type min_max -max_paths 1000 -sort_by group -input_pins -routable_nets -file tools/timing_report_worst_paths.txt
quit