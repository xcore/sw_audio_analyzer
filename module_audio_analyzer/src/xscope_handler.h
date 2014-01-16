#ifndef __xscope_handler_h__
#define __xscope_handler_h__

#include "signal_gen.h"
#include "audio_analyzer.h"
#include "app_config.h"

#ifndef RELAY_CONTROL
  #define RELAY_CONTROL 0
#endif

#if RELAY_CONTROL
  #include "ethernet_tap.h"
#endif

void xscope_handler(chanend c_host_data,
    client interface channel_config_if i_chan_config,
#if RELAY_CONTROL
    client interface ethernet_tap_relay_control_if i_relay_control,
#endif
    client interface analysis_control_if i_control[n],
    server interface error_reporting_if i_error_reporting[n], unsigned n);

#endif // __xscope_handler_h__
