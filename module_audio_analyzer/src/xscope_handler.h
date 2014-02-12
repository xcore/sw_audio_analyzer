#ifndef __xscope_handler_h__
#define __xscope_handler_h__

#include "signal_gen.h"
#include "ramp_gen.h"
#include "audio_analyzer.h"
#include "app_config.h"

#ifndef RELAY_CONTROL
  #define RELAY_CONTROL 0
#endif

#if RELAY_CONTROL
  #include "ethernet_tap.h"
#endif

[[combinable]]
void xscope_handler(chanend c_host_data,
    client interface error_flow_control_if i_flow_control,
    client interface channel_config_if i_chan_config,
    client interface spdif_config_if ?i_spdif_config,
    client interface analysis_control_if i_control[n], unsigned n);

void error_reporter(server interface error_flow_control_if i_flow_control,
    server interface error_reporting_if i_error_reporting[n], unsigned n);

#endif // __xscope_handler_h__
