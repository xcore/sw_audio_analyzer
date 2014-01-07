#ifndef __signal_gen_h__
#define __signal_gen_h__
#include "i2s_master.h"

enum chan_conf_type {
  NO_SIGNAL,
  SINE
};

typedef struct chan_conf_t {
  int enabled;
  enum chan_conf_type type;
  unsigned freq;
  unsigned do_glitch;
  unsigned glitch_period;
} chan_conf_t;


#ifdef __XC__

interface channel_config_if {
  void enable_all_channels();
  void enable_channel(unsigned chan_id);
  void disable_all_channels();
  void disable_channel(unsigned chan_id);
  void configure_channel(unsigned chan_id, chan_conf_t chan_conf);
};

void signal_gen(streaming chanend c_dac_samples, unsigned sample_freq,
                chan_conf_t chan_conf[I2S_MASTER_NUM_CHANS_DAC],
                server interface channel_config_if i_chan_config);

#endif // __XC__

#endif // __signal_gen_h__
