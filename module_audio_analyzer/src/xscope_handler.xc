
#include <xscope.h>
#include <string.h>
#include "xassert.h"
#include "debug_print.h"
#include "xscope_handler.h"
#include "host_xscope.h"

#define NUM_BLOCKS 32
#define BLOCK_SIZE_WORDS (AUDIO_ANALYZER_FFT_SIZE / NUM_BLOCKS)

#define ONE_MICROSECOND 100
#define BLOCK_DELAY (50 * ONE_MICROSECOND)

void xscope_handler(chanend c_host_data,
    client interface channel_config_if i_chan_config,
    client interface analysis_control_if i_control[n],
    server interface error_reporting_if i_error_reporting[n], unsigned n)
{
  xscope_connect_data_from_host(c_host_data);

  int sending = -1;
  int send_block = 0;
  int data_outstanding = 0;

  unsigned glitch_average[I2S_MASTER_NUM_CHANS_ADC];
  unsigned glitch_max[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_data[I2S_MASTER_NUM_CHANS_ADC][AUDIO_ANALYZER_FFT_SIZE];
  int glitch_data_valid[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_data_needs_send[I2S_MASTER_NUM_CHANS_ADC];
  memset(glitch_data_valid, 0, sizeof(glitch_data_valid));
  memset(glitch_data_needs_send, 0, sizeof(glitch_data_needs_send));
  int chan_id_map[I2S_MASTER_NUM_CHANS_ADC];

  for (int i = 0; i < I2S_MASTER_NUM_CHANS_ADC; i++)
    chan_id_map[i] = i;

  timer tmr;
  int t;
  const int ticks_per_second = 100000000;
  int second_count = 0;
  int minute_count = 0;
  tmr :> t;

  while (1) {
    unsigned int buffer[256/4]; // The maximum read size is 256 bytes
    unsigned char *char_ptr = (unsigned char *)buffer;
    int bytes_read = 0;

    if (sending == -1) {
      for (int i = 0; i < I2S_MASTER_NUM_CHANS_ADC; i++) {
        if (glitch_data_needs_send[i]) {
          // Start sending this glitch data
          sending = i;
          glitch_data_needs_send[i] = 0;

          // Send the total number of data words, whether it is glitch data and interface
          // in one word
          xscope_int(AUDIO_ANALYZER_GLITCH_DATA, (sizeof(glitch_data[i])/4) << 8 |
              ((glitch_data_valid[i] & 0x1) << 7) |
              chan_id_map[i]);
          break;
        }
      }
    }

    select {
      case tmr when timerafter(t + ticks_per_second) :> void:
        second_count += 1;
        if (second_count == 60) {
          second_count = 0;
          minute_count += 1;
          if (minute_count % 5 == 0) {
	    debug_printf("Time elapsed: %d mins\n", minute_count);
	  }
        }
        t += ticks_per_second;
      break;
      case xscope_data_from_host(c_host_data, (unsigned char *)buffer, bytes_read):
        if (bytes_read < 1) {
          debug_printf("ERROR: Received '%d' bytes\n", bytes_read);
          break;
        }
        int chan_index = -1;
        for (int i = 0; i < I2S_MASTER_NUM_CHANS_ADC; i++) {
          if (chan_id_map[i] == char_ptr[1])
            chan_index = i;
        }
        if (chan_index == -1 &&
            (char_ptr[0] == HOST_ENABLE_ONE ||
             char_ptr[0] == HOST_DISABLE_ONE ||
             char_ptr[0] == HOST_CONFIGURE_ONE ||
             char_ptr[0] == HOST_SET_VOLUME)) {
          debug_printf("ERROR: Invalid channel id '%d'\n", char_ptr[1]);
          break;
        }

        switch (char_ptr[0]) {
          case HOST_ACK_DATA :
            data_outstanding = 0;
            break;
          case HOST_ENABLE_ALL : 
            i_chan_config.enable_all_channels();
            break;
          case HOST_ENABLE_ONE : {
            assert(bytes_read > 1);
            i_chan_config.enable_channel(chan_index);
            break;
          }
          case HOST_DISABLE_ALL : 
            i_chan_config.disable_all_channels();
            break;
          case HOST_DISABLE_ONE : {
            assert(bytes_read > 1);
            i_chan_config.disable_channel(chan_index);
            break;
          }
          case HOST_CONFIGURE_ONE : {
            // There must be enough data for the word-aligned data
            assert(bytes_read == 20);
            chan_conf_t chan_config;
            chan_config.enabled = 0;
            chan_config.type = SINE;
            chan_config.freq = buffer[1];
            chan_config.glitch_count = buffer[2];
            chan_config.glitch_start = buffer[3];
            chan_config.glitch_period = buffer[4];
            i_chan_config.configure_channel(chan_index, chan_config);
            break;
          }
          case HOST_SIGNAL_DUMP_ONE : {
            assert(bytes_read > 1);
            int if_num = char_ptr[1];
            if (if_num < n)
              i_control[if_num].request_signal_dump();
            else
              debug_printf("Interface %d is invalid\n", if_num);
            break;
          }
          case HOST_SET_VOLUME : {
            assert(bytes_read > 2);
            i_chan_config.set_volume(chan_index, char_ptr[2]);
            break;
          }
          case HOST_SET_BASE : {
            int offset = char_ptr[1];
            for (int i = 0; i < I2S_MASTER_NUM_CHANS_ADC; i++) {
              chan_id_map[i] = i + offset;
              i_control[i].set_chan_id(chan_id_map[i]);
            }
            break;
          }
        }
        break;

      case i_error_reporting[int i].set_chan_id(unsigned x):
        chan_id_map[i] = x;
        break;

      case i_error_reporting[int i].glitch_detected(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                                                   int cur[AUDIO_ANALYZER_FFT_SIZE/2],
                                                   unsigned average, unsigned max) :
        memcpy(glitch_data[i], prev, sizeof(prev));
        memcpy(&glitch_data[i][AUDIO_ANALYZER_FFT_SIZE/2], cur, sizeof(cur));
        glitch_average[i] = average;
        glitch_max[i] = max;
        glitch_data_valid[i] = 1;
        break;

      case i_error_reporting[int i].signal_dump(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                                                int cur[AUDIO_ANALYZER_FFT_SIZE/2]) :
        memcpy(glitch_data[i], prev, sizeof(prev));
        memcpy(&glitch_data[i][AUDIO_ANALYZER_FFT_SIZE/2], cur, sizeof(cur));
        debug_printf("Channel %d: dump signal data\n", i);
        glitch_data_needs_send[i] = 1;
        break;

      case i_error_reporting[int i].report_glitch() :
        debug_printf("ERROR: Channel %u: glitch detected (average %u, max %u)\n",
            chan_id_map[i], glitch_average[i], glitch_max[i]);
        glitch_data_needs_send[i] = 1;
        break;

      case i_error_reporting[int i].cancel_glitch() : 
        glitch_data_valid[i] = 0;
        break;

      ((sending != -1) && !data_outstanding) => default :
          // Send the first block
        unsigned char *data = (unsigned char *)(&glitch_data[sending][send_block * BLOCK_SIZE_WORDS]);
        xscope_bytes(AUDIO_ANALYZER_GLITCH_DATA, BLOCK_SIZE_WORDS * sizeof(int), data);
        data_outstanding = 1;
        send_block += 1;

        if (send_block == NUM_BLOCKS) {
          glitch_data_valid[sending] = 0;
          sending = -1;
          send_block = 0;
        }
        break;
    }
  }
}

