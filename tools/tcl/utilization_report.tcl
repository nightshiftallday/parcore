open_project build_synth/test_config_0/user_c0_0/test.xpr
open_run synth_1
# This will only report the utilization of the user design!
# All other parts that are added by Coyote will be ignored
# If you want the full report remove the "-cells" argument
report_utilization -hierarchical -cells inst_user_c0_0 -file tools/utilization_report.txt
quit
