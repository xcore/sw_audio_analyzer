#include <platform.h>
#include <xs1.h>
#include <math.h>
#include <xscope.h>
#include "i2s_master.h"
#include "audio_analyzer.h"
#include "app_global.h"
#include "audiohw.h"
#include "timer.h"
#include "debug_print.h"
#include "xassert.h"

#ifndef SIMULATOR_LOOPBACK
#define SIMULATOR_LOOPBACK 0
#endif

#define PORT_CLK_BIT            XS1_PORT_1I         /* Bit clock */
#define PORT_CLK_LR             XS1_PORT_1E         /* LR clock */

#define PORT_DAC_0              XS1_PORT_1M
#define PORT_DAC_1              XS1_PORT_1F
#define PORT_DAC_2              XS1_PORT_1H
#define PORT_DAC_3              XS1_PORT_1N

#define PORT_ADC_0              XS1_PORT_1G
#define PORT_ADC_1              XS1_PORT_1A
#define PORT_ADC_2              XS1_PORT_1B

#define PORT_CLK_MAS            XS1_PORT_1L

on tile[1] : r_i2s i2s_resources =
{
  XS1_CLKBLK_1,
  XS1_CLKBLK_2,
  PORT_CLK_MAS,
  PORT_CLK_BIT,
  PORT_CLK_LR,
  {PORT_ADC_0, PORT_ADC_1},
  {PORT_DAC_0, PORT_DAC_1},
};

clock dummy_clk = on tile[1]: XS1_CLKBLK_3;
out port p_dummy_clk = on tile[1]: XS1_PORT_1J;

#define MAX_SINE_PERIOD 500

static unsigned gcd(unsigned u, unsigned v) {
    while ( v != 0) {
        unsigned r = u % v;
        u = v;
        v = r;
    }
    return u;
}

/* This function generates the output signal for the DAC */
static void signal_gen(streaming chanend c_dac_samples, unsigned sample_freq)
{
  int sine_table[I2S_MASTER_NUM_CHANS_DAC][MAX_SINE_PERIOD];
  unsigned period[I2S_MASTER_NUM_CHANS_DAC];
  // output a test 1khz wav with occasional glitch
  debug_printf("Generating sine tables\n");
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
    int freq = (i+1) * 1000;
    unsigned d = gcd(freq, sample_freq);
    period[i] = freq/d * sample_freq/d;
    debug_printf("Generating sine table for chan %u, frequency %u, period %u\n", i, freq, period[i]);
    if (period[i] > MAX_SINE_PERIOD) {
      fail("Period of sine wave (w.r.t. sample rate) too large to calculate\n");
    }
    for (int j = 0; j < period[i];j++) {
      float ratio = (double) sample_freq / (double) freq;
      float x = sinf(((float) j) * 2 * M_PI / ratio);
      sine_table[i][j] = (int) (x * ldexp(2, 25));
    }
  }
  debug_printf("Generating signals.\n");
 // int sine_lut[48] = {0,140151431,277904833,410903206,536870911,653652607,759250124,851856662,929887696,992008094,1037154958,1064555813,1073741824,1064555813,1037154958,992008094,929887696,851856662,759250124,653652607,536870911,410903206,277904833,140151431,0,-140151431,-277904833,-410903206,-536870911,-653652607,-759250124,-851856662,-929887696,-992008094,-1037154958,-1064555813,-1073741824,-1064555813,-1037154958,-992008094,-929887696,-851856662,-759250124,-653652607,-536870912,-410903206,-277904833,-1401514310};
  int count[I2S_MASTER_NUM_CHANS_DAC];
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++)
    count[i] = 0;
  int gcount = 1;
  while (1) {
    gcount++;
    if (gcount > 55452) {
      //sample = 0;
      gcount = 0;
    }

    for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
      unsigned sample = sine_table[i][count[i]];
      sample >>= 8;
      count[i]++;
      if (count[i] >= period[i])
        count[i] = 0;
      if (i == 1 && gcount == 0)
          sample = 0;
      c_dac_samples <: sample;
    }
  }
}

static void audio(streaming chanend c_i2s_data) {
  // First make sure the i2s client is ready
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_ADC; i++)
    c_i2s_data <: 0;
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++)
    c_i2s_data :> int _;

  // Initialize hardware
  if (SIMULATOR_LOOPBACK) {
    // approximate 24.576 with 25Mhz output (this will be loopbacked by simulator
    // into the MCLK input)
    configure_clock_rate(dummy_clk, 100, 4);
    configure_port_clock_output(p_dummy_clk, dummy_clk);
    start_clock(dummy_clk);
  }
  else {
    debug_printf("Initializing Hardware\n");
    AudioHwInit();
  }

  // Go into the I2S loop
  debug_printf("Starting I2S\n");
  i2s_master(i2s_resources, c_i2s_data, MCLK_FREQ / (SAMP_FREQ * 64));
}

int main(){
  interface audio_analysis_if i_analysis[4];
  interface audio_analysis_scheduler_if i_sched0[2], i_sched1[2];
  streaming chan c_i2s_data, c_dac_samples;
  par {
	  on tile[0].core[0]: audio_analyzer(i_analysis[0], i_sched0[0], SAMP_FREQ, 0);
    on tile[0].core[0]: audio_analyzer(i_analysis[1], i_sched0[1], SAMP_FREQ, 1);
    on tile[0].core[0]: analysis_scheduler(i_sched0, 2);

    on tile[0].core[1]: audio_analyzer(i_analysis[2], i_sched1[0], SAMP_FREQ, 2);
    on tile[0].core[1]: audio_analyzer(i_analysis[3], i_sched1[1], SAMP_FREQ, 3);
    on tile[0].core[1]: analysis_scheduler(i_sched1, 2);

    on tile[0]: i2s_tap(c_i2s_data, c_dac_samples, i_analysis, 4);

    on tile[1]: audio(c_i2s_data);
	  on tile[1]: genclock();
	  on tile[1]: signal_gen(c_dac_samples, SAMP_FREQ);
  }
  return 0;
}

