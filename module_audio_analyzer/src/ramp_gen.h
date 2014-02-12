#ifndef __ramp_gen_h__
#define __ramp_gen_h__

#include "app_config.h"
#include "app_global.h"

enum dig_conf_type {
  NO_SIG,
  RAMP
};

typedef struct spdif_conf_t {
  int enabled;
  enum dig_conf_type type;
  signed step;
  int glitch_count;
  unsigned glitch_start;
  unsigned glitch_period;
} spdif_conf_t;


#ifdef __XC__

interface spdif_config_if {
  void enable_all_channels();
  void enable_channel(unsigned chan_id);
  void disable_all_channels();
  void disable_channel(unsigned chan_id);
  void configure_channel(unsigned chan_id, spdif_conf_t conf);
};

void ramp_gen(chanend c_spdif_tx, unsigned sample_freq,
                spdif_conf_t spdif_conf[DIGITAL_MASTER_NUM_CHANS],
                server interface spdif_config_if i_spdif_config);

#endif // __XC__

#endif // __ramp_gen_h__
