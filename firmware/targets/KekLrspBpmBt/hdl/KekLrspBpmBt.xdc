##############################################################################
## This file is part of 'kek-lrsp-bpm'.
## It is subject to the license terms in the LICENSE.txt file found in the
## top-level directory of this distribution and at:
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
## No part of 'kek-lrsp-bpm', including this file,
## may be copied, modified, propagated, or distributed except according to
## the terms contained in the LICENSE.txt file.
##############################################################################

create_clock -name plClkP -period  2.0 [get_ports {plClkP}]
create_clock -name qsfpRefClkP -period 6.4 [get_ports {qsfpRefClkP}]
create_clock -name qsfpSysClkP -period 6.4 [get_ports {qsfpSysClkP}]

# Constrain PS output clock?
# create_clock -name pl_clk0_250MHz -period 4.0 [get_pins AxiSocUltraPlusCpuCore/zynq_ultra_ps_e_0/pl_clk0]

set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins U_Core/REAL_CPU.U_CPU/U_Pll/PllGen.U_Pll/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins U_Core/REAL_CPU.U_CPU/U_Pll/PllGen.U_Pll/CLKOUT1]] \
    -group [get_clocks -of_objects [get_pins U_RFDC/U_Pll/PllGen.U_Pll/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins U_RFDC/U_Pll/PllGen.U_Pll/CLKOUT1]] \
    -group [get_clocks -include_generated_clocks qsfpSysClkP] \
    -group [get_clocks -include_generated_clocks -of_objects [get_pins U_EvrGty/U_EvrGtyCoreWrapper/rxOutClk]] \
    -group [get_clocks -include_generated_clocks -of_objects [get_pins U_EvrGty/U_EvrGtyCoreWrapper/txOutClk]]
    # -group [get_clocks -of_objects [get_pins U_XVC_PLL/MmcmGen.U_Mmcm/CLKOUT0]] \
    # -group [get_clocks qsfpRefClkP] \

# ILA timing constraint violations are probably fine? So ignore them I guess
# (appear to occur with faster clocks ...)
# Did not work...
# set_false_path -to [get_cells -hierarchical *u_ila_0*]
# Ya can get those from the GUI and copy/paste the name
set_false_path -from -reset_path [get_pins {U_EvrGty/U_EvrGtyCoreWrapper/U_EvrGtyCore/inst/gen_gtwizard_gtye4_top.EvrGtyCore_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[1].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST/RXOUTCLK}] -to [get_pins {u_ila_0/inst/PROBE_PIPE.shift_probes_reg[0][20]/D}]
set_false_path -from [get_clocks -of_objects [get_pins {U_EvrGty/U_EvrGtyCoreWrapper/U_EvrGtyCore/inst/gen_gtwizard_gtye4_top.EvrGtyCore_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[1].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST/RXOUTCLK}]] -to [get_clocks -of_objects [get_pins {U_EvrGty/U_EvrGtyCoreWrapper/U_EvrGtyCore/inst/gen_gtwizard_gtye4_top.EvrGtyCore_gtwizard_gtye4_inst/gen_gtwizard_gtye4.gen_channel_container[1].gen_enabled_channel.gtye4_channel_wrapper_inst/channel_inst/gtye4_channel_gen.gen_gtye4_channel_inst[0].GTYE4_CHANNEL_PRIM_INST/RXOUTCLK}]]

# QSFP Port (Bank 128)

# Transceiver reference clock (156.250 MHz fixed, to GT clock pins)
set_property -dict { PACKAGE_PIN AA33 IOSTANDARD LVDS } [get_ports { qsfpRefClkP }]
set_property -dict { PACKAGE_PIN AA34 IOSTANDARD LVDS } [get_ports { qsfpRefClkN }]
# Same as above but routed to ordinary FPGA clock input
set_property -dict { PACKAGE_PIN AL17 IOSTANDARD LVDS } [get_ports { qsfpSysClkP }]
set_property -dict { PACKAGE_PIN AM17 IOSTANDARD LVDS } [get_ports { qsfpSysClkN }]

# QSFP misc. transceiver signals (Bank 66)

# set_property -dict { PACKAGE_PIN AK22 IOSTANDARD LVCMOS33 } [get_ports { qsfpModSell }]
# set_property -dict { PACKAGE_PIN AL21 IOSTANDARD LVCMOS33 } [get_ports { qsfpResetL }]
# set_property -dict { PACKAGE_PIN AL22 IOSTANDARD LVCMOS33 } [get_ports { qsfpModPrsL }]
# set_property -dict { PACKAGE_PIN AM22 IOSTANDARD LVCMOS33 } [get_ports { qsfpIntL }]
# set_property -dict { PACKAGE_PIN AN22 IOSTANDARD LVCMOS33 } [get_ports { qsfpLpMode }]
set_property -dict { PACKAGE_PIN AK22 } [get_ports { qsfpModSelL }]
set_property -dict { PACKAGE_PIN AL21 } [get_ports { qsfpResetL }]
set_property -dict { PACKAGE_PIN AL22 } [get_ports { qsfpModPrsL }]
set_property -dict { PACKAGE_PIN AM22 } [get_ports { qsfpIntL }]
set_property -dict { PACKAGE_PIN AN22 } [get_ports { qsfpLpMode }]
