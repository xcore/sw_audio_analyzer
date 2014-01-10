#include "audio_analyzer.h"
#include "i2s_master.h"
#include "xscope.h"
#include "debug_print.h"

#ifdef __audio_analyzer_conf_h_exists__
#include "audio_analyzer_conf.h"
#endif

// This function splits a big array into a set of segments
static void split_movable_array(int * movable a, int * movable b[n],
                                unsigned n, unsigned m)
{
  int * p = a;
  for (int i = 0; i < n; i++) {
    unsafe {
      unsigned * unsafe p_a = (unsigned * unsafe) &p;
      unsigned * unsafe p_b = (unsigned * unsafe) &b[i];
      *p_b = *p_a; // pointer;
      *(p_b + 1) = *p_a;  // base
      *(p_b + 2) = m * sizeof(int); // range
    }
    p += m;
  }
}

static void unsplit_movable_array(int * movable &a, int * movable b[n],
                                  unsigned n, unsigned m)
{
  unsafe {
    unsigned * unsafe p_a = (unsigned * unsafe) &a;
    unsigned * unsafe p_b = (unsigned * unsafe) &b[0];
    *p_a = *p_b; // pointer
    *(p_a + 1) = *p_b; // base;
    *(p_a + 2) = n * m * sizeof(int); // range
  }
  for (int i = 0; i < n; i++) {
    b[i] = null;
  }
}

void i2s_tap(streaming chanend c_i2s,
             streaming chanend c_dac_samples,
             client interface audio_analysis_if analyzer[n],
             unsigned n)
{
  /* Audio sample buffers */
  int buffer[AUDIO_ANALYZER_FFT_SIZE/2 * I2S_MASTER_NUM_CHANS_ADC];
  int * movable p_buf = buffer;
  int * movable buf[I2S_MASTER_NUM_CHANS_ADC];
  unsigned count = 0;
  debug_printf("Starting I2S sample tap\n");
  split_movable_array(move(p_buf), buf, I2S_MASTER_NUM_CHANS_ADC, AUDIO_ANALYZER_FFT_SIZE/2);
  while (1) {
    select {
      case c_i2s :> unsigned first_sample:
        xscope_int(AUDIO_ANALYZER_CHAN_0_ADC_DATA, first_sample);

        buf[0][count] = first_sample;
        for (int i = 1; i < I2S_MASTER_NUM_CHANS_ADC; i++) {
          unsigned sample;
          c_i2s :> sample;
          buf[i][count] = sample;
        }

        for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
          int sample;
          c_dac_samples :> sample;
          c_i2s <: sample;
        }

        count++;
        if (count == AUDIO_ANALYZER_FFT_SIZE/2) {
            for (int i = 0; i < n; i++)
              analyzer[i].swap_buffers(buf[i]);
          count = 0;
        }

      break;
    }
  }
  unsplit_movable_array(p_buf, buf, I2S_MASTER_NUM_CHANS_ADC, AUDIO_ANALYZER_FFT_SIZE);
}
