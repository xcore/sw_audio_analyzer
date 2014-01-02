.DEFAULT_GOAL := all

# compiled for. It either refers to an XN file in the source directories
# or a valid argument for the --target option when compiling
TARGET = xr-usb-audio-2.0-mc

# The APP_NAME variable determines the name of the final .xe file. It should
# not include the .xe postfix. If left blank the name will default to
# the project name
APP_NAME = 

# The USED_MODULES variable lists other module used by the application.
USED_MODULES = module_audio_analyzer module_i2c_simple module_i2s_master module_spdif_rx  module_logging module_xassert

# The flags passed to xcc when building the application
# You can also set the following to override flags for a particular language:
# XCC_XC_FLAGS, XCC_C_FLAGS, XCC_ASM_FLAGS, XCC_CPP_FLAGS
# If the variable XCC_MAP_FLAGS is set it overrides the flags passed to
# xcc for the final link (mapping) stage.
COMMON_FLAGS = -O3 -g -report -save-temps
XCC_FLAGS_SimulatorLoopback = $(COMMON_FLAGS) -DSIMULATOR_LOOPBACK=1
XCC_FLAGS_GlitchInjector = $(COMMON_FLAGS)
XCC_FLAGS_TestDevice1 = $(COMMON_FLAGS)
XCC_FLAGS_TestDevice2 = $(COMMON_FLAGS)

INCLUDE_ONLY_IN_SimulatorLoopback = src/config_SimulatorLoopback
INCLUDE_ONLY_IN_GlitchInjector = src/config_GlitchInjector
INCLUDE_ONLY_IN_TestDevice1 = src/config_TestDevice1
INCLUDE_ONLY_IN_TestDevice2 = src/config_TestDevice2

# The VERBOSE variable, if set to 1, enables verbose output from the make system.
VERBOSE = 0

test:
	axe --loopback tile[1]:XS1_PORT_1J tile[1]:XS1_PORT_1L --loopback tile[1]:XS1_PORT_1M tile[1]:XS1_PORT_1G --loopback tile[1]:XS1_PORT_1F tile[1]:XS1_PORT_1A --loopback tile[1]:XS1_PORT_1H tile[1]:XS1_PORT_1B bin/SimulatorLoopback/app_audio_analyzer_mc_SimulatorLoopback.xe


#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
