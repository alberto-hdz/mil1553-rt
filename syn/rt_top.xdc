# 100 MHz system clock
create_clock -period 10.000 -name clk [get_ports clk]

# rx_p / rx_n are asynchronous to clk and go straight into two-flop synchronizers
set_false_path -from [get_ports {rx_p rx_n}]

# reset and bus outputs are not timed against an external device in this build
set_false_path -from [get_ports rst]
set_false_path -to [get_ports {tx_p tx_n}]
