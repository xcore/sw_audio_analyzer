#include <platform.h>
#include <xs1.h>
#include <xscope.h>
#include "i2s_master.h"
#include "audio_analyzer.h"
#include "app_global.h"
#include "audiohw.h"
#include "timer.h"
#include "debug_print.h"
#include "xassert.h"
#include "signal_gen.h"
#if SPDIF_IN_TESTER == 1
#include "ramp_gen.h"
#endif
#include "SpdifReceive.h"
#include "SpdifTransmit.h"
#include "xscope_handler.h"

#ifndef SIMULATOR_LOOPBACK
#define SIMULATOR_LOOPBACK 0
#endif

//Controls ramp checking (from DUT SPDIF out)
#ifndef SPDIF_OUT_TESTER
#define SPDIF_OUT_TESTER 0
#endif

//Controls ramp generation (into DUT SPDIF in)
#ifndef SPDIF_IN_TESTER
#define SPDIF_IN_TESTER 0
#endif

#ifndef STEREO_BOARD_TESTER
#define STEREO_BOARD_TESTER 0
#endif

#define PORT_CLK_BIT            XS1_PORT_1I         /* Bit clock */
#define PORT_CLK_LR             XS1_PORT_1E         /* LR clock */

#define PORT_DAC_0              XS1_PORT_1M
#define PORT_DAC_1              XS1_PORT_1F
#define PORT_DAC_2              XS1_PORT_1H

#define PORT_ADC_0              XS1_PORT_1G
#define PORT_ADC_1              XS1_PORT_1A
#define PORT_ADC_2              XS1_PORT_1B

#define PORT_CLK_MAS            XS1_PORT_1L

#define PORT_SPDIF_IN           XS1_PORT_1K;    //coaxial (optical = 1J, coax = 1K)
#ifndef PORT_SPDIF_OUT
#define PORT_SPDIF_OUT          XS1_PORT_1K;    //coaxial (optical = 1J, coax = 1K)
#endif

on tile[1] : r_i2s i2s_resources =
{
  XS1_CLKBLK_1,
  XS1_CLKBLK_2,
  PORT_CLK_MAS,
  PORT_CLK_BIT,
  PORT_CLK_LR,
#if I2S_MASTER_NUM_CHANS_ADC == 2
#if !STEREO_BOARD_TESTER
  {PORT_ADC_0},
#else
  {PORT_ADC_2},
#endif
#else
  {PORT_ADC_0, PORT_ADC_1},
#endif
#if I2S_MASTER_NUM_CHANS_DAC == 2
#if !STEREO_BOARD_TESTER
  {PORT_DAC_0},
#else
  {PORT_DAC_2},
#endif
#else
  {PORT_DAC_0, PORT_DAC_1},
#endif
};

on tile[1]: clock dummy_clk = XS1_CLKBLK_3;
on tile[1]: out port p_dummy_clk = XS1_PORT_1J;

on tile[0]: in buffered port:4 p_spdif_in = PORT_SPDIF_IN;
on tile[0]: clock clk_spdif_in = XS1_CLKBLK_1;

on tile[1]: out buffered port:32 p_spdif_out =  PORT_SPDIF_OUT;
on tile[1]: clock clk_spdif_out = XS1_CLKBLK_5;

static void audio(streaming chanend c_i2s_data, chanend ?c_spdif_tx) {
  // First make sure the i2s client is ready
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_ADC; i++)
    c_i2s_data <: 0;
  for (int i = 0; i < I2S_MASTER_NUM_CHANS_DAC; i++)
    c_i2s_data :> int _;

  // Initialize hardware
  if (SIMULATOR_LOOPBACK) {
    // approximate 24.576 with 25Mhz output (this will be loopbacked
    // by simulator into the MCLK input)
    configure_clock_rate(dummy_clk, 100, 4);
    configure_port_clock_output(p_dummy_clk, dummy_clk);
    start_clock(dummy_clk);
  }
  else {
    debug_printf("Initializing Hardware\n");
    AudioHwInit();
#if SPDIF_IN_TESTER == 1
    SpdifTransmitPortConfig(p_spdif_out, clk_spdif_out, i2s_resources.mck);
#else
    p_spdif_out <: 0; //Drive a zero to stop it flapping (causes noise on SPDIF input when looped back)
#endif
  }

  // Go into the I2S loop
  debug_printf("Starting I2S\n");
  par{
  i2s_master(i2s_resources, c_i2s_data, MCLK_FREQ / (SAMP_FREQ * 64));
#if SPDIF_IN_TESTER == 1
      debug_printf("Starting SPDIF tx\n");
      SpdifTransmit(p_spdif_out, c_spdif_tx);
#endif
  }
}

chan_conf_t chan_conf[I2S_MASTER_NUM_CHANS_DAC] = CHAN_CONFIG;
#if SPDIF_IN_TESTER == 1
spdif_conf_t spdif_conf[DIGITAL_MASTER_NUM_CHANS] = SPDIF_CONFIG;
#endif

#ifndef BASE_CHAN_ID
#define BASE_CHAN_ID 0
#endif

#ifndef BASE_DIG_CHAN_ID
#define BASE_DIG_CHAN_ID (BASE_CHAN_ID + 4)
#endif

#if STEREO_BOARD_TESTER
#define NUM_ANALYSIS_INTERFACES 2
#else
#define NUM_ANALYSIS_INTERFACES 4
#endif

int main(){
  interface audio_analysis_if i_analysis[NUM_ANALYSIS_INTERFACES];
  interface audio_analysis_scheduler_if i_sched0[2];
#if NUM_ANALYSIS_INTERFACES == 4
  interface audio_analysis_scheduler_if i_sched1[2];
#endif
  interface error_reporting_if i_error_reporting[NUM_ANALYSIS_INTERFACES];
  interface analysis_control_if i_control[NUM_ANALYSIS_INTERFACES];
  interface channel_config_if i_chan_config;
  interface error_flow_control_if i_flow_control;

  streaming chan c_i2s_data, c_dac_samples;
#if SPDIF_IN_TESTER == 1
  chan c_spdif_tx;
  interface spdif_config_if i_spdif_config;
#endif
#if SPDIF_OUT_TESTER == 1
  streaming chan c_dig_in;
#endif
  chan c_host_data;
  par {
    on tile[1]: error_reporter(i_flow_control, i_error_reporting,
                               NUM_ANALYSIS_INTERFACES);
    on tile[1]: xscope_handler(c_host_data, i_flow_control, i_chan_config,
#if SPDIF_IN_TESTER == 1
            i_spdif_config,
#else
            null,
#endif

                               i_control, NUM_ANALYSIS_INTERFACES);

    on tile[0].core[0]: audio_analyzer(i_analysis[0], i_sched0[0], SAMP_FREQ,
                                       0, i_error_reporting[0],
                                       i_control[0]);
    on tile[0].core[0]: audio_analyzer(i_analysis[1], i_sched0[1], SAMP_FREQ,
                                       1, i_error_reporting[1],
                                       i_control[1]);
    on tile[0].core[0]: analysis_scheduler(i_sched0, 2);

#if NUM_ANALYSIS_INTERFACES == 4
    on tile[0].core[1]: audio_analyzer(i_analysis[2], i_sched1[0], SAMP_FREQ,
                                       2, i_error_reporting[2],
                                       i_control[2]);
    on tile[0].core[1]: audio_analyzer(i_analysis[3], i_sched1[1], SAMP_FREQ,
                                       3, i_error_reporting[3],
                                       i_control[3]);
    on tile[0].core[1]: analysis_scheduler(i_sched1, 2);
#endif

    on tile[0]: {
      if (SIMULATOR_LOOPBACK)
        xscope_config_io(XSCOPE_IO_NONE);
      i2s_tap(c_i2s_data, c_dac_samples, i_analysis, I2S_MASTER_NUM_CHANS_DAC);
    }

#if SPDIF_IN_TESTER == 1
    on tile[0]: ramp_gen(c_spdif_tx, SAMP_FREQ, spdif_conf, i_spdif_config);
#endif
#if SPDIF_OUT_TESTER == 1
    on tile[0]: analyze_ramp(c_dig_in, BASE_DIG_CHAN_ID);
    on tile[0]: SpdifReceive(p_spdif_in, c_dig_in, 4, clk_spdif_in);
#endif
    on tile[1]: audio(c_i2s_data,
#if SPDIF_IN_TESTER == 1
            c_spdif_tx);
#else
            null);
#endif
    on tile[1]: genclock();
    on tile[1]: {
      if (SIMULATOR_LOOPBACK)
        xscope_config_io(XSCOPE_IO_NONE);
      signal_gen(c_dac_samples, SAMP_FREQ, chan_conf, i_chan_config);
    }
  }
  return 0;
}

