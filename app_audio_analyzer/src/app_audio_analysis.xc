#include <platform.h>
#include <xs1.h>
#include <math.h>
#include <xscope.h>
#include "i2s_master.h"
#include "audio_analyzer.h"
#include "app_global.h"

#ifndef SIMULATOR_LOOPBACK
#define SIMULATOR_LOOPBACK 0
#endif

on tile[0] : r_i2s i2s_resources =
{
  XS1_CLKBLK_1,
  XS1_CLKBLK_2,
  XS1_PORT_1A,
  XS1_PORT_1B,             // Master Clock
  XS1_PORT_1C,            // Bit Clock
  {XS1_PORT_1D},
  {XS1_PORT_1E},
};

clock dummy_clk = on tile[0]: XS1_CLKBLK_3;
out port p_dummy_clk = on tile[0]: XS1_PORT_1F;

/* This function generates the output signal for the DAC */
static void signal_gen(streaming chanend c_dac_samples)
{
  // output a test 6khz wav
  int sine_lut[6] = {0, 2048, 2048, 0, -2048, -2048};
  int count = 0;
  while (1) {
    for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++) {
      c_dac_samples <: sine_lut[count];
    }
    count++;
    if (count > 5)
      count = 0;
  }
}

int main(){
  interface audio_analysis_if i;
  streaming chan c_i2s_data, c_dac_samples;
  par {
	  on tile[0]: audio_analyzer(i);
	  on tile[0]: i2s_tap(c_i2s_data, c_dac_samples, i);
	  on tile[0]:
	    {
	      if (SIMULATOR_LOOPBACK) {
	        // approximate 24.576 with 25Mhz output (this will be loopbacked by simulator
	        // into the MCLK input)
	        configure_clock_rate(dummy_clk, 100, 4);
	        configure_port_clock_output(p_dummy_clk, dummy_clk);
	        start_clock(dummy_clk);
	      }
	      i2s_master(i2s_resources, c_i2s_data, MCLK_FREQ/(SAMP_FREQ * 64));
	    }
	  on tile[0]: signal_gen(c_dac_samples);
  }
  return 0;
}

