
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
    server interface error_reporting_if i_error_reporting[n], unsigned n)
{
  xscope_connect_data_from_host(c_host_data);

  int sending = -1;
  int send_block = 0;
  int data_outstanding = 0;

  int glitch_data[I2S_MASTER_NUM_CHANS_ADC][AUDIO_ANALYZER_FFT_SIZE];
  int glitch_index[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_magnitude[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_data_valid[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_data_needs_send[I2S_MASTER_NUM_CHANS_ADC];
  memset(glitch_data_valid, 0, sizeof(glitch_data_valid));
  memset(glitch_data_needs_send, 0, sizeof(glitch_data_needs_send));

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

          // Send the total number of data words
          xscope_int(AUDIO_ANALYZER_GLITCH_DATA, (sizeof(glitch_data[i])/4) << 8 | i);
          break;
        }
      }
    }

    select {
      case xscope_data_from_host(c_host_data, (unsigned char *)buffer, bytes_read):
        if (bytes_read < 1) {
          debug_printf("ERROR: Received '%d' bytes\n", bytes_read);
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
            i_chan_config.enable_channel(char_ptr[1]);
            break;
          }
          case HOST_DISABLE_ALL : 
            i_chan_config.disable_all_channels();
            break;
          case HOST_DISABLE_ONE : {
            assert(bytes_read > 1);
            i_chan_config.disable_channel(char_ptr[1]);
            break;
          }
          case HOST_CONFIGURE_ONE : {
            // There must be enough data for the word-aligned data
            assert(bytes_read == 16);
            chan_conf_t chan_config;
            chan_config.enabled = 0;
            chan_config.type = SINE;
            chan_config.freq = buffer[1];
            chan_config.do_glitch = buffer[2];
            chan_config.glitch_period = buffer[3];
            i_chan_config.configure_channel(char_ptr[1], chan_config);
            break;
          }
        }
        break;

      case i_error_reporting[int i].glitch_detected(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                                                  int cur[AUDIO_ANALYZER_FFT_SIZE/2],
                                                  int index, int magnitude) : 
        memcpy(glitch_data[i], prev, sizeof(prev));
        memcpy(&glitch_data[i][AUDIO_ANALYZER_FFT_SIZE/2], cur, sizeof(cur));
        glitch_index[i] = index;
        glitch_magnitude[i] = magnitude;
        glitch_data_valid[i] = 1;
        break;

      case i_error_reporting[int i].report_glitch() :
        debug_printf("ERROR: Channel %u: glitch detected (index %u, magnitude %d)\n",
            i, glitch_index[i], glitch_magnitude[i]);
        glitch_data_needs_send[i] = 1;
        break;

      case i_error_reporting[int i].cancel_glitch() : 
        assert(glitch_data_valid[i] && msg("!data_valid cancel"));
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

