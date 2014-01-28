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
BUILD_FLAGS = -O3 -g -report -save-temps

XCC_FLAGS_stereo_board_tester = $(BUILD_FLAGS) -DSTEREO_BOARD_TESTER=1
INCLUDE_ONLY_IN_stereo_board_tester =

XCC_FLAGS_multi_chan_board_tester = $(BUILD_FLAGS) -DSPDIF_TESTER=1
INCLUDE_ONLY_IN_multi_chan_board_tester =

# The VERBOSE variable, if set to 1, enables verbose output from the make system.
VERBOSE = 0

test:
	axe --loopback tile[1]:XS1_PORT_1J tile[1]:XS1_PORT_1L --loopback tile[1]:XS1_PORT_1M tile[1]:XS1_PORT_1G --loopback tile[1]:XS1_PORT_1F tile[1]:XS1_PORT_1A --loopback tile[1]:XS1_PORT_1H tile[1]:XS1_PORT_1B bin/SimulatorLoopback/app_audio_analyzer_mc_SimulatorLoopback.xe


#=============================================================================
# The following part of the Makefile includes the common build infrastructure
# for compiling XMOS applications. You should not need to edit below here.

XMOS_MAKE_PATH ?= ../..
include $(XMOS_MAKE_PATH)/xcommon/module_xcommon/build/Makefile.common
