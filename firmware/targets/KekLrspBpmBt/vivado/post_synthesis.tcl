##############################################################################
## This file is part of 'kek-lrsp-bpm'.
## It is subject to the license terms in the LICENSE.txt file found in the
## top-level directory of this distribution and at:
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
## No part of 'kek-lrsp-bpm', including this file,
## may be copied, modified, propagated, or distributed except according to
## the terms contained in the LICENSE.txt file.
##############################################################################

##############################
# Get variables and procedures
##############################
source -quiet $::env(RUCKUS_DIR)/vivado_env_var.tcl
source $::env(RUCKUS_PROC_TCL)

######################################################
# Bypass the debug chipscope generation via return cmd
# ELSE ... comment out the return to include chipscope
######################################################
# return

############################
## Open the synthesis design
############################
open_run synth_1

###############################
## Set the name of the ILA core
###############################
set ilaName u_ila_0

##################
## Create the core
##################
CreateDebugCore ${ilaName}

#######################
## Set the record depth
#######################
set_property C_DATA_DEPTH 8192 [get_debug_cores ${ilaName}]

#################################
## Set the clock for the ILA core
#################################
# TODO: I guess this really should be the axi clock but this gives timing
# errors... Try to somehow use that clock I guess? Maybe it must be the axi
# clock...
SetDebugCoreClk ${ilaName} {U_XVC/xvcClk156}
# SetDebugCoreClk ${ilaName} {U_App/axilClk}
# SetDebugCoreClk ${ilaName} {U_RFDC/refClk}
# SetDebugCoreClk ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxUsrClk}

#######################
## Set the debug Probes
#######################

ConfigProbe ${ilaName} {U_App/axilClk}
ConfigProbe ${ilaName} {U_App/axilRst}

# New EVR stuff
ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_TRGS/trgs*}
ConfigProbe ${ilaName} {U_App/U_ReadoutCtrl/trigsIn*}
ConfigProbe ${ilaName} {U_App/U_ReadoutCtrl/trigOut*}

ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/data*}
ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/dataK*}
ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/clk*}
ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/rst*}
ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/dataValid*}

ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/readoutTrigSync*}

ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/axis*}

ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/U_AxiStreamFrameBuffer/dataR*}
ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/U_AxiStreamFrameBuffer/axilR*}
# ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/U_AxiStreamFrameBuffer/txSlave*}
# ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/U_AxiStreamFrameBuffer/axisMaster*}
# ConfigProbe ${ilaName} {U_App/U_EvrDecoder/U_DBSD/U_AxiStreamFrameBuffer/axisSlave*}

##########################
## Write the port map file
##########################
WriteDebugProbes ${ilaName}
