#ifndef __xscope_handler_h__
#define __xscope_handler_h__

#include "signal_gen.h"
#include "audio_analyzer.h"

void xscope_handler(chanend c_host_data,
    client interface channel_config_if i_chan_config,
    client interface analysis_control_if i_control[n],
    server interface error_reporting_if i_error_reporting[n], unsigned n);

#endif // __xscope_handler_h__
