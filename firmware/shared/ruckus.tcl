# Load RUCKUS environment and library
source $::env(RUCKUS_PROC_TCL)

# Load submodule code
loadRuckusTcl $::env(TOP_DIR)/submodules/surf
loadRuckusTcl $::env(TOP_DIR)/submodules/axi-soc-ultra-plus-core/hardware/RealDigitalRfSoC4x2

# Load RTL code
loadSource -dir "$::DIR_PATH/rtl"
# loadSource -sim_only -dir "$::DIR_PATH/tb" -fileType "VHDL 2008"

# Load Evr (Event Receiver) related code
loadRuckusTcl "$::DIR_PATH/Evr"

# Load VIVADO unisim components (not sure if this is correct...)
loadSource -sim_only -lib unisim -path "$::env(XILINX_VIVADO)/data/vhdl/src/unisims/unisim_VCOMP.vhd"
loadSource -sim_only -lib unisim -dir "$::env(XILINX_VIVADO)/data/vhdl/src/unisims/primitive"

# Load IP cores
loadIpCore -dir "$::DIR_PATH/ip"

# Updating the impl_1 strategy
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
