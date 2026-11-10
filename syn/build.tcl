# Non-project Vivado build: synthesis + implementation + reports (no bitstream).
# Run from the syn/ folder:  vivado -mode batch -source build.tcl
set part xc7a200tfbg484-1
set top  rt_top

file mkdir reports
read_vhdl -vhdl2008 [glob ../rtl/*.vhd]
read_xdc rt_top.xdc

# 100 MHz clock -> 50 clocks per 0.5 us half bit
synth_design -top $top -part $part -generic CLKS_PER_HALF=50
opt_design
place_design
phys_opt_design
route_design

report_utilization -file reports/utilization.rpt
report_utilization -hierarchical -file reports/utilization_hier.rpt
report_timing_summary -file reports/timing_summary.rpt
