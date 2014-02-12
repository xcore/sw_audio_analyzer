#include "ramp_gen.h"
//#include <math.h>
#include "debug_print.h"
#include "xassert.h"
#include "xs1.h"
#include <xscope.h>

#ifdef __audio_analyzer_conf_h_exists__
#include "audio_analyzer_conf.h"
#endif


static void enable(unsigned chan_id, spdif_conf_t &spdif_conf)
{
  spdif_conf.enabled = 1;
  debug_printf("Channel %u: enabled\n", chan_id);
}

static void disable(unsigned chan_id, spdif_conf_t &spdif_conf)
{
  spdif_conf.enabled = 0;
  debug_printf("Channel %u: disabled\n", chan_id);
}


/*
 * This function generates the output signal for the spdif transmitter */

void ramp_gen(chanend c_spdif_tx, unsigned sample_freq,
                spdif_conf_t spdif_conf[DIGITAL_MASTER_NUM_CHANS],
                server interface spdif_config_if i_conf)
{
  int gcount[DIGITAL_MASTER_NUM_CHANS];
  unsigned sample[DIGITAL_MASTER_NUM_CHANS];

  for (int i = 0; i < DIGITAL_MASTER_NUM_CHANS; i++) {
    gcount[i] = 0;   //Reset glitch count
    sample[i] = 0;   //Start with zero sample
    debug_printf("Generating ramp for chan %d, step size %d\n", i, spdif_conf[i].step);
  }

  outuint(c_spdif_tx, sample_freq);
  outuint(c_spdif_tx, MCLK_FREQ);

  //Command processor
  while (1) {
    select {
      case i_conf.enable_all_channels() :
        for (int i = 0; i < DIGITAL_MASTER_NUM_CHANS; i++)
          enable(i, spdif_conf[i]);
        break;

      case i_conf.enable_channel(unsigned i) :
        enable(i, spdif_conf[i]);
        break;

      case i_conf.disable_all_channels() :
        for (int i = 0; i < DIGITAL_MASTER_NUM_CHANS; i++)
          disable(i, spdif_conf[i]);
        break;

      case i_conf.disable_channel(unsigned i) :
        disable(i, spdif_conf[i]);
        break;

      case i_conf.configure_channel(unsigned i, spdif_conf_t conf) :
        spdif_conf[i].type = conf.type;
        spdif_conf[i].step = conf.step;
        spdif_conf[i].glitch_count = conf.glitch_count;
        spdif_conf[i].glitch_start = conf.glitch_start;
        spdif_conf[i].glitch_period = conf.glitch_period;
        gcount[i] = 0;
        sample[i] = 0;
        break;

      default:
        break;
    }

    //Generate signal
    for (int i = 0; i < DIGITAL_MASTER_NUM_CHANS; i++) {
      if (spdif_conf[i].enabled) {
        sample[i] += spdif_conf[i].step << 8;    //Do the ramp, left align 24b word

        if (spdif_conf[i].glitch_count) {
          if (spdif_conf[i].glitch_start)
            spdif_conf[i].glitch_start--;
          else
            gcount[i]++;

          if (gcount[i] >= spdif_conf[i].glitch_period) {
            gcount[i] = 0;
            sample[i] = 0; //Insert the zero sample (the glitch)
            if (spdif_conf[i].glitch_count > 0)
              spdif_conf[i].glitch_count--;
          }
        }
      }
      outuint(c_spdif_tx, sample[i]);
    }
    //xscope_int(AUDIO_ANALYZER_SPDIF_TX, sample[0]); //just send the left
  }
}
