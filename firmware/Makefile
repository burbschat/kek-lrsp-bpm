# Makefile for running testbeds
# Use as (substitute variables as required):
# make GHDL_TOP_LIB=work TARGET=KekLrspBpmBt PROJECT=EvrDecoderTb GHDL_STOP_TIME=100ns gtkwave

# Define default target
target: analysis

ifndef MODULES
export MODULES = $(abspath $(PWD)/submodules/)
endif

ifndef TARGET
export TARGET = KekLrspBpmBt
endif
export TARGET_PATH = $(abspath $(PWD)/targets/$(TARGET))

# Must define some part for the axi-soc-ultra-plus-core files to load 
# (tcl code checks for the part).
ifndef TARGET_PART
export PRJ_PART = xczu48dr-ffvg1517-2-e
endif

export RUCKUS_DIR = $(MODULES)/ruckus
export TOP_DIR    = $(abspath $(PWD))
# export PROJ_DIR   = $(abspath $(PWD))
export PROJ_DIR   = $(TARGET_PATH)
export OUT_DIR    = $(TOP_DIR)/build/sim/$(TARGET)

# Override the submodule check because ruckus external of this repo
export OVERRIDE_SUBMODULE_LOCKS = 1
# Bypass vivado version checks (won't help as the procedure is missing...)
export BYPASS_VERSION_CHECK = 1

# Those must be set to 1 for soc-core code loading to succeed
export GEN_BIT_IMAGE = 1
export GEN_XSA_IMAGE = 1
# Dummy bd version 
export VIVADO_VERSION = 2024.1

ifndef GHDL_CMD
export GHDL_CMD = ghdl
endif

export GHDL_BASE_FLAGS = \
	--workdir=$(OUT_DIR) \
	--std=08 \
	--ieee=synopsys \
	-frelaxed-rules \
	-fexplicit

export GHDL_OPTIONAL_WARNINGS = elaboration hide specs shared
export GHDL_SUPPORTED_WARNING_NAMES := $(shell $(GHDL_CMD) --help-warnings 2>/dev/null | awk '/^[[:space:]]*-W/ {name=$$1; sub(/^-W/, "", name); sub(/\*$$/, "", name); if (name != "all") print name}')
export GHDL_WARNING_FLAGS := $(strip $(foreach warn,$(GHDL_OPTIONAL_WARNINGS),$(if $(filter $(warn),$(GHDL_SUPPORTED_WARNING_NAMES)),-Wno-$(warn))))
export GHDLFLAGS = $(GHDL_BASE_FLAGS) $(GHDL_WARNING_FLAGS)

# Load the common makefile library
include $(MODULES)/ruckus/system_ghdl.mk
