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

# These clocks should all be the same...
# Sometimes not possible to fulfill timing constraints when connecting these
# clocks to the ILA, so leave them out for now...
# ConfigProbe ${ilaName} {U_XVC/xvcClk156}
# ConfigProbe ${ilaName} {U_EvrGty/stableClk}
# ConfigProbe ${ilaName} {U_EvrGty/gtRefClk}
# ConfigProbe ${ilaName} {U_qsfpSysClk/O}

ConfigProbe ${ilaName} {U_EvrGty/rxData[*]}
ConfigProbe ${ilaName} {U_EvrGty/rxDataK[*]}
ConfigProbe ${ilaName} {U_EvrGty/rxUsrClk}
# ConfigProbe ${ilaName} {U_EvrGty/U_RXUSRCLK_PLL/clkOut[*]}
# ConfigProbe ${ilaName} {U_EvrGty/U_RXUSRCLK_PLL/locked}
# ConfigProbe ${ilaName} {U_EvrGty/U_TXUSRCLK_PLL/locked}
ConfigProbe ${ilaName} {U_EvrGty/rxResetDone}
ConfigProbe ${ilaName} {U_EvrGty/rxDispErr[*]}
ConfigProbe ${ilaName} {U_EvrGty/rxDecErr[*]}

# ConfigProbe ${ilaName} {U_EvrGty/stableRst}
ConfigProbe ${ilaName} {U_EvrGty/resetGt}
# Hard reset signal (stablerst or resetgt):
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/stableRst}
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxUsrClkActive}
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/txUsrClkActive}


# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rx8b10bEn}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxCommaDetEn}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxMCommaAlignEn}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxPCommaAlignEn}

ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxByteIsAligned}
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxByteRealign}
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxCommaDet}
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxPmaResetDone}

# TODO: Check this one!
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxCdrStable}

# ConfigProbe ${ilaName} {qsfpModPrs}
# ConfigProbe ${ilaName} {qsfpLpModeInt}
# ConfigProbe ${ilaName} {qsfpReset}

# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/tx8b10bEn}
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/txPmaResetDone}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/txPrgDivResetDone}


# QPLL1 locked signal
ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/qpll1Lock}

ConfigProbe ${ilaName} {U_EvrGty/txData[*]}
ConfigProbe ${ilaName} {U_EvrGty/txDataK[*]}
ConfigProbe ${ilaName} {U_EvrGty/txUsrClk}
ConfigProbe ${ilaName} {U_EvrGty/txResetDone}

ConfigProbe ${ilaName} {U_EvrGty/gtRxUserResetSync}
ConfigProbe ${ilaName} {U_EvrGty/gtTxUserResetSync}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/rxOutClk}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrGtyCoreWrapper/txOutClk}

# # Before synchronizer
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrDecoder/U_TRGS/r[trgCountsResets]*}
# # After synchronizer
# #ConfigProbe ${ilaName} {U_EvrGty/U_EvrDecoder/trgCountsResets/*}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrDecoder/U_TRGS/U_SyncV_Inst/dataIn*}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrDecoder/U_TRGS/U_SyncV_Inst/dataOut*}
# ConfigProbe ${ilaName} {U_EvrGty/U_EvrDecoder/U_TRGS/trgs*}

# ConfigProbe ${ilaName} {evrRxUsrClkBuffODDR}



##########################
## Write the port map file
##########################
WriteDebugProbes ${ilaName}
