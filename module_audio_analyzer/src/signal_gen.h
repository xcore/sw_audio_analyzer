#ifndef __signal_gen_h__
#define __signal_gen_h__
#include "i2s_master.h"

enum chan_conf_type {
  NO_SIGNAL,
  SINE
};

typedef struct chan_conf_t {
  enum chan_conf_type type;
  unsigned freq;
  unsigned do_glitch;
  unsigned glitch_period;
} chan_conf_t;

void signal_gen(streaming chanend c_dac_samples, unsigned sample_freq,
                chan_conf_t chan_conf[I2S_MASTER_NUM_CHANS_DAC]);


#endif // __signal_gen_h__
