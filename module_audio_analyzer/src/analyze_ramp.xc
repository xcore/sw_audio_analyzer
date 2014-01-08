#include "audio_analyzer.h"
#include "debug_print.h"
#include "SpdifReceive.h"
#include <xs1.h>

interface analyze_ramp_if {
   void analyze_sample(int sample);
};

enum ramp_analyzer_state {
  INITIALIZING,
  WAITING_FOR_SIGNAL,
  DETECTING,
  CHECKING,
};

#define INITIAL_IGNORE_COUNT 10000

[[distributable]]
static void analyze_ramp_aux(server interface analyze_ramp_if i, unsigned chan_id)
{
  debug_printf("Channel %u: Started ramp checker\n", chan_id);
  enum ramp_analyzer_state state = INITIALIZING;
  int prev = 0;
  int step = 0;
  int init_count = 0;
  while (1) {
    select {
    case i.analyze_sample(int sample):
      switch (state) {
      case INITIALIZING:
        init_count++;
        if (init_count > INITIAL_IGNORE_COUNT) {
          init_count = 0;
          state = WAITING_FOR_SIGNAL;
        }
        break;
      case WAITING_FOR_SIGNAL:
        if (sample != 0) {
          debug_printf("Channel %u: Signal detected (initial value %d)\n",
                       chan_id, sample);
          state = DETECTING;
        }
        break;
      case DETECTING:
        step = ((sample << 8) - (prev << 8)) >> 8;
        debug_printf("Channel %u: step = %d\n", chan_id, step);
        state = CHECKING;
        break;
      case CHECKING:
        int diff = ((sample << 8) - (prev << 8)) >> 8;
        if (diff != step) {
          debug_printf("Channel %u: discontinuity"
                       " (samples %d, %d do not differ by %d)\n",
                       chan_id, prev, sample, step);
          state = INITIALIZING;
        }
        break;
      }
      prev = sample;
      break;

    }
  }
}

static void split_signal(streaming chanend c_dig_in,
                         client interface analyze_ramp_if i[2])
{
  while (1) {
    int sample;
    c_dig_in :> sample;
    int lr = ((sample & 0xF) == FRAME_Y) ? 1 : 0;
    sample >>= 4;
    sample = sext(sample, 24);
    i[lr].analyze_sample(sample);
  }
}
void analyze_ramp(streaming chanend c_dig_in, unsigned base_chan_id) {
  interface analyze_ramp_if i[2];
  par {
    split_signal(c_dig_in, i);
    analyze_ramp_aux(i[0], base_chan_id);
    analyze_ramp_aux(i[1], base_chan_id + 1);
  }
}
