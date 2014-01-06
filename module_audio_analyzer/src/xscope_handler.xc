
#include <xscope.h>
#include <string.h>
#include "xassert.h"
#include "debug_print.h"
#include "xscope_handler.h"
#include "host_xscope.h"

void xscope_handler(chanend c_host_data,
    client interface channel_config_if i_chan_config,
    server interface error_reporting_if i_error_reporting[n], unsigned n)
{
  xscope_connect_data_from_host(c_host_data);

  int glitch_data[I2S_MASTER_NUM_CHANS_ADC][AUDIO_ANALYZER_FFT_SIZE];
  int glitch_index[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_magnitude[I2S_MASTER_NUM_CHANS_ADC];
  int glitch_data_valid[I2S_MASTER_NUM_CHANS_ADC];
  memset(glitch_data_valid, 0, sizeof(glitch_data_valid));

  while (1) {
    unsigned int buffer[256/4]; // The maximum read size is 256 bytes
    unsigned char *char_ptr = (unsigned char *)buffer;
    int bytes_read = 0;

    select {
      case xscope_data_from_host(c_host_data, (unsigned char *)buffer, bytes_read):
        if (bytes_read < 1) {
          debug_printf("ERROR: Received '%d' bytes\n", bytes_read);
          break;
        }
        switch (char_ptr[0]) {
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
        assert(glitch_data_valid[i]);

        debug_printf("ERROR: Channel %u: glitch detected (index %u, magnitude %d)\n",
            i, glitch_index[i], glitch_magnitude[i]);

        xscope_int(AUDIO_ANALYZER_GLITCH_DATA, sizeof(glitch_data[i]) << 8 | i);
        xscope_bytes(AUDIO_ANALYZER_GLITCH_DATA, sizeof(glitch_data[i]),
            (unsigned char *)glitch_data[i]);
        glitch_data_valid[i] = 0;
        break;

      case i_error_reporting[int i].cancel_glitch() : 
        assert(glitch_data_valid[i]);
        glitch_data_valid[i] = 0;
        break;
    }
  }
}

