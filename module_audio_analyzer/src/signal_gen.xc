#include "signal_gen.h"
#include "i2s_master.h"
#include <math.h>
#include "debug_print.h"
#include "xassert.h"

#define MAX_SINE_PERIOD 500

// The default volume of the signals generated (min 1..31 max)
#define DEFAULT_VOLUME 27

static unsigned gcd(unsigned u, unsigned v)
{
  while (v != 0) {
    unsigned r = u % v;
    u = v;
    v = r;
  }
  return u;
}

static void enable(unsigned chan_id, chan_conf_t &chan_conf)
{
  chan_conf.enabled = 1;
  debug_printf("Channel %u: enabled\n", chan_id);
}

static void disable(unsigned chan_id, chan_conf_t &chan_conf)
{
  chan_conf.enabled = 0;
  debug_printf("Channel %u: disabled\n", chan_id);
}

static void generate_sine_table(unsigned chan_id, chan_conf_t chan_conf,
    int sine_table[MAX_SINE_PERIOD], unsigned &period, unsigned sample_freq,
    int volume)
{
  if (chan_conf.type != SINE)
    return;

  int freq = chan_conf.freq;
  unsigned d = gcd(freq, sample_freq);
  period = freq/d * sample_freq/d;
  debug_printf("Generating sine table for chan %u, frequency %u, period %u, volume %d\n",
               chan_id, freq, period, volume);
  if (period > MAX_SINE_PERIOD) {
    fail("Period of sine wave (w.r.t. sample rate) too large to calculate\n");
  }
  for (int j = 0; j < period;j++) {
    float ratio = (double) sample_freq / (double) freq;
    float x = sinf(((float) j) * 2 * M_PI / ratio);
    sine_table[j] = (int) (x * ldexp(2, volume));
  }
  if (chan_conf.glitch_count) {
    debug_printf("Channel %u will glitch %d times, starting %u, period %u samples\n", chan_id,
                 chan_conf.glitch_count, chan_conf.glitch_start, chan_conf.glitch_period);
  }
}

/*
 * This function generates the output signal for the DAC */
void signal_gen(streaming chanend c_dac_samples, unsigned sample_freq,
                chan_conf_t chan_conf[I2S_MASTER_NUM_CHANS_DAC],
                server interface channel_config_if i_conf)
{
  int sine_table[I2S_MASTER_NUM_CHANS_DAC][MAX_SINE_PERIOD];
  unsigned period[I2S_MASTER_NUM_CHANS_DAC];
  int count[I2S_MASTER_NUM_CHANS_DAC];
  int gcount[I2S_MASTER_NUM_CHANS_DAC];
  int volume[I2S_MASTER_NUM_CHANS_DAC];

  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
    volume[i] = DEFAULT_VOLUME;
    generate_sine_table(i, chan_conf[i], sine_table[i], period[i], sample_freq, volume[i]);
    count[i] = gcount[i] = 0;
  }

  debug_printf("Generating signals.\n");

  while (1) {
    select {
      case i_conf.enable_all_channels() :
        for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++)
          enable(i, chan_conf[i]);
        break;

      case i_conf.enable_channel(unsigned i) :
        enable(i, chan_conf[i]);
        break;

      case i_conf.disable_all_channels() :
        for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++)
          disable(i, chan_conf[i]);
        break;

      case i_conf.disable_channel(unsigned i) :
        disable(i, chan_conf[i]);
        break;

      case i_conf.configure_channel(unsigned i, chan_conf_t conf) :
        chan_conf[i].type = conf.type;
        chan_conf[i].freq = conf.freq;
        chan_conf[i].glitch_count = conf.glitch_count;
        chan_conf[i].glitch_start = conf.glitch_start;
        chan_conf[i].glitch_period = conf.glitch_period;
        count[i] = gcount[i] = 0;
        generate_sine_table(i, chan_conf[i], sine_table[i], period[i], sample_freq, volume[i]);
        break;

      case i_conf.set_volume(unsigned i, unsigned v) :
        if (v > 0 && v < 32) {
          volume[i] = v;
          generate_sine_table(i, chan_conf[i], sine_table[i], period[i], sample_freq, volume[i]);
        }
        break;

      default:
        break;
    }

    for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
      unsigned sample = 0;
      if (chan_conf[i].enabled) {
        sample = sine_table[i][count[i]];
        count[i]++;
        if (count[i] >= period[i])
          count[i] = 0;

        if (chan_conf[i].glitch_count) {
          if (chan_conf[i].glitch_start)
            chan_conf[i].glitch_start--;
          else
            gcount[i]++;

          if (gcount[i] >= chan_conf[i].glitch_period) {
            gcount[i] = 0;
            sample = 0;
            if (chan_conf[i].glitch_count > 0)
              chan_conf[i].glitch_count--;
          }
        }
      }
      c_dac_samples <: sample;
    }
  }
}
