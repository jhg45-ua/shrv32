# ==============================================================================
# Project: SHRV32 (Space-Hardened RISC-V 32)
# Script:  build.tcl — Synthesis, implementation, and bitstream in batch mode
# ==============================================================================

set script_dir [file dirname [file normalize [info script]]]
source "$script_dir/create_project.tcl"

# 1. Síntesis
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "ERROR: The Vivado synthesis has failed."
}

# 2. Implementation and Bitstream Generation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "ERROR: Bitstream implementation or generation has failed."
}

# 3. Export reports and copy the bitstream to a fixed path
open_run impl_1
report_utilization    -file "$proj_dir/utilization.rpt"
report_timing_summary -file "$proj_dir/timing.rpt"

set bit_src "$proj_dir/${proj_name}.runs/impl_1/soc.bit"
set bit_dst "$proj_dir/shrv32.bit"
file copy -force $bit_src $bit_dst

puts "INFO: Bitstream ready in $bit_dst"
puts "INFO: Reports saved in $proj_dir/utilization.rpt and timing.rpt"
