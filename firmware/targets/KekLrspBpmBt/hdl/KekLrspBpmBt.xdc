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

set_clock_groups -asynchronous \
    -group [get_clocks -of_objects [get_pins U_Core/REAL_CPU.U_CPU/U_Pll/PllGen.U_Pll/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins U_Core/REAL_CPU.U_CPU/U_Pll/PllGen.U_Pll/CLKOUT1]] \
    -group [get_clocks -of_objects [get_pins U_RFDC/U_Pll/PllGen.U_Pll/CLKOUT0]] \
    -group [get_clocks -of_objects [get_pins U_RFDC/U_Pll/PllGen.U_Pll/CLKOUT1]]

# QSFP Port (Bank 128)

# Transceiver reference clock (156.250 MHz fixed, to GT clock pins)
set_property -dict { PACKAGE_PIN AA33 IOSTANDARD LVDS } [get_ports { qsfpRefClkP }]
set_property -dict { PACKAGE_PIN AA34 IOSTANDARD LVDS } [get_ports { qsfpRefClkN }]
# Same as above but routed to ordinary FPGA clock input
set_property -dict { PACKAGE_PIN AL17 IOSTANDARD LVDS } [get_ports { qsfpSysClkP }]
set_property -dict { PACKAGE_PIN AM17 IOSTANDARD LVDS } [get_ports { qsfpSysClkN }]

# TX
# Maybe must use LOC instead of PACKAGE_PIN here?
set_property PACKAGE_PIN Y35 [get_ports { qsfpGtTxP[0] }]
set_property PACKAGE_PIN Y36 [get_ports { qsfpGtTxN[0] }]
set_property PACKAGE_PIN V35 [get_ports { qsfpGtTxP[2] }]
set_property PACKAGE_PIN V36 [get_ports { qsfpGtTxN[2] }]
set_property PACKAGE_PIN T35 [get_ports { qsfpGtTxP[1] }]
set_property PACKAGE_PIN T36 [get_ports { qsfpGtTxN[1] }]
set_property PACKAGE_PIN R33 [get_ports { qsfpGtTxP[3] }]
set_property PACKAGE_PIN R34 [get_ports { qsfpGtTxN[3] }]

# RX
# Maybe must use LOC instead of PACKAGE_PIN here?
set_property PACKAGE_PIN AA38 [get_ports { qsfpGtRxP[3] }]
set_property PACKAGE_PIN AA39 [get_ports { qsfpGtRxN[3] }]
set_property PACKAGE_PIN W38 [get_ports { qsfpGtRxP[1] }]
set_property PACKAGE_PIN W39 [get_ports { qsfpGtRxN[1] }]
set_property PACKAGE_PIN U38 [get_ports { qsfpGtRxP[2] }]
set_property PACKAGE_PIN U39 [get_ports { qsfpGtRxN[2] }]
set_property PACKAGE_PIN R38 [get_ports { qsfpGtRxP[0] }]
set_property PACKAGE_PIN R39 [get_ports { qsfpGtRxN[0] }]
