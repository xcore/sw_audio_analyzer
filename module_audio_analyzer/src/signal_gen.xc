#include "signal_gen.h"
#include "i2s_master.h"
#include <math.h>
#include "debug_print.h"
#include "xassert.h"

#define MAX_SINE_PERIOD 500

static unsigned gcd(unsigned u, unsigned v) {
    while ( v != 0) {
        unsigned r = u % v;
        u = v;
        v = r;
    }
    return u;
}

/*
 * This function generates the output signal for the DAC */
void signal_gen(streaming chanend c_dac_samples, unsigned sample_freq,
                chan_conf_t chan_conf[I2S_MASTER_NUM_CHANS_DAC])
{
  int sine_table[I2S_MASTER_NUM_CHANS_DAC][MAX_SINE_PERIOD];
  unsigned period[I2S_MASTER_NUM_CHANS_DAC];

  // output a test 1khz wav with occasional glitch
  debug_printf("Generating sine tables\n");
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
    if (chan_conf[i].type == NO_SIGNAL)
      continue;
    int freq = chan_conf[i].freq;
    unsigned d = gcd(freq, sample_freq);
    period[i] = freq/d * sample_freq/d;
    debug_printf("Generating sine table for chan %u, frequency %u, period %u\n",
                 i, freq, period[i]);
    if (period[i] > MAX_SINE_PERIOD) {
      fail("Period of sine wave (w.r.t. sample rate) too large to calculate\n");
    }
    for (int j = 0; j < period[i];j++) {
      float ratio = (double) sample_freq / (double) freq;
      float x = sinf(((float) j) * 2 * M_PI / ratio);
      sine_table[i][j] = (int) (x * ldexp(2, 25));
    }
    if (chan_conf[i].do_glitch)
      debug_printf("Channel %u will glitch with period %u samples\n", i,
                   chan_conf[i].glitch_period);
  }
  debug_printf("Generating signals.\n");
  int count[I2S_MASTER_NUM_CHANS_DAC];
  int gcount[I2S_MASTER_NUM_CHANS_DAC];
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++)
    count[i] = gcount[i] = 0;
  while (1) {

    for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
      unsigned sample = sine_table[i][count[i]];
      sample >>= 8;
      count[i]++;
      if (count[i] >= period[i])
        count[i] = 0;
      gcount[i]++;
      if (chan_conf[i].do_glitch && gcount[i] > chan_conf[i].glitch_period) {
        gcount[i] = 0;
        sample = 0;
      }
      c_dac_samples <: sample;
    }
  }
}
