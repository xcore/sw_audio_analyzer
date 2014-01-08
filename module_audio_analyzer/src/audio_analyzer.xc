#include "audio_analyzer.h"
#include "fft.h"
#include "string.h"
#include "debug_print.h"
#include "xscope.h"
#include "stdlib.h"
#include "hann.h"
#include "xs1.h"

#ifdef __audio_analyzer_conf_h_exists__
#include "audio_analyzer_conf.h"
#endif

#ifndef AUDIO_SIGNAL_DETECT_THRESHOLD
#define AUDIO_SIGNAL_DETECT_THRESHOLD 90000000
#endif

#ifndef AUDIO_NOISE_FLOOR
#define AUDIO_NOISE_FLOOR 25
#endif

#define DUMP_FIRST_ANALYSIS 0

#define SIGNAL_DETECT_COUNT_THRESHOLD   15
#define PEAK_IGNORE_WINDOW              15
#define GLITCH_TOLERANCE_RATIO_A         8
#define GLITCH_TOLERANCE_RATIO_B        25
#define LOW_FREQUENCY_IGNORE_THRESHOLD   5

// This function does a very fast but quite innacurate log2 calculation
static unsigned fastlog2(unsigned long long v)
{
  unsigned z = __builtin_clz(v >> 32);
  if (z == 32)
    z += __builtin_clz((unsigned) v);
  return 64-z;
}

static inline int hmul(int a, int b) {
    int h;
    unsigned l;
    {h,l} = macs(a, b, 0, 0);
    return h << 1 | l >> 31;
}

static void hanning_window(int output[], int data0[], int data1[],
                           int N, const int sine[]) {
    for(int i = 0; i < (N>>2); i++) {
        int s = sine[i]>>1;
        output[1*(N>>2)-i] = hmul(data0[1*(N>>2)-i], 0x3fffffff-s);
        output[1*(N>>2)+i] = hmul(data0[1*(N>>2)+i], 0x3fffffff+s);
        output[3*(N>>2)-i] = hmul(data1[1*(N>>2)-i], 0x3fffffff+s);
        output[3*(N>>2)+i] = hmul(data1[1*(N>>2)+i], 0x3fffffff-s);
    }
    output[0] = 0;
    output[N>>1] = hmul(data1[0], 0x7ffffffe);
}

static int do_fft_analysis(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                            int cur[AUDIO_ANALYZER_FFT_SIZE/2],
                            unsigned chan_id, unsigned sample_rate,
                            int &glitch_count, int &reported_freq,
                            client interface error_reporting_if i_error_reporting)
{
  int im[AUDIO_ANALYZER_FFT_SIZE];
  int wsig[AUDIO_ANALYZER_FFT_SIZE];
  memset(im, 0, sizeof(im));

  if (DUMP_FIRST_ANALYSIS && chan_id == 0) {
    for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
      debug_printf("%d,", prev[i]);
    }
    for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
      debug_printf("%d,", cur[i]);
    }
    debug_printf("\n");
  }

  // FFT
  hanning_window(wsig, prev, cur, AUDIO_ANALYZER_FFT_SIZE, FFT_SINE(AUDIO_ANALYZER_FFT_SIZE));
  fftTwiddle(wsig, im, AUDIO_ANALYZER_FFT_SIZE);
  fftForward(wsig, im, AUDIO_ANALYZER_FFT_SIZE, FFT_SINE(AUDIO_ANALYZER_FFT_SIZE));

  // We will use the buffer for the imaginary part to store the magnitude
  int *mag = im;

  // Calculate magnitude spectrum
  unsigned max_val = 0;
  unsigned max_index = 0;
  long long mag_spec;
  for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE; i++) {
    long long re_i = wsig[i];
    long long im_i = im[i];
    mag_spec = re_i * re_i + im_i * im_i;
    mag[i] = fastlog2(mag_spec);
    if (mag[i] > max_val) {
      max_val = mag[i];
      max_index = i;
    }
  }

  if (max_val < AUDIO_NOISE_FLOOR)
    return 0;
  max_val -= AUDIO_NOISE_FLOOR;

  if (!reported_freq) {
    unsigned freq;
    freq = ((unsigned long long) max_index * sample_rate) / AUDIO_ANALYZER_FFT_SIZE;
    debug_printf("Channel %u: Frequency %u (mag: %d)\n", chan_id, ((freq+125)/250)*250, max_val);
    reported_freq = 1;
  }

  if (DUMP_FIRST_ANALYSIS && chan_id == 0) {
    for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE; i++) {
      debug_printf("%d,", mag[i]);
    }
    debug_printf("\n");
    exit(0);
  }

  unsigned tolerance = max_val * GLITCH_TOLERANCE_RATIO_A / GLITCH_TOLERANCE_RATIO_B;

  // Check for a glitch
  int glitch_detected = 0;
  for (int i = LOW_FREQUENCY_IGNORE_THRESHOLD; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
    if (i >= max_index - PEAK_IGNORE_WINDOW && i < max_index + PEAK_IGNORE_WINDOW)
      continue;
    if (mag[i] < AUDIO_NOISE_FLOOR)
      continue;
    unsigned mag_i = mag[i] - AUDIO_NOISE_FLOOR;

    if (mag_i > tolerance) {
      glitch_detected = 1;
      glitch_count++;
      i_error_reporting.glitch_detected(prev, cur, i, mag_i);

      if (chan_id == 1 && 0) {
        for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
          debug_printf("%d,", prev[i]);
        }
        for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
          debug_printf("%d,", cur[i]);
        }
        debug_printf("\n");
      }
      break;
    }
  }
  return glitch_detected;
}

typedef enum {
  ANALYZER_IDLE,
  ANALYZER_ACTIVE,
  ANALYZER_GLITCH_DETECTED,
  ANALYZER_GLITCH_REPORTED,
} anayzer_state_t;

static void inline signal_lost(unsigned chan_id, anayzer_state_t &state,
    int &glitch_count, int &reported_freq)
{
  debug_printf("Channel %u: Lost signal having detected %d glitches\n", chan_id, glitch_count);

  state = ANALYZER_IDLE;
  reported_freq = 0;
  glitch_count = 0;
}

[[combinable]]
void audio_analyzer(server interface audio_analysis_if i_client,
                    server interface audio_analysis_scheduler_if scheduler,
                    unsigned sample_rate, unsigned chan_id,
                    client interface error_reporting_if i_error_reporting)
{
  int initial_buffer[AUDIO_ANALYZER_FFT_SIZE/2];
  int * movable pbuf = initial_buffer;
  anayzer_state_t state = ANALYZER_IDLE;
  int sig_detect_count = 0;
  int glitch_count = 0;
  int reported_freq = 0;
  int prev[AUDIO_ANALYZER_FFT_SIZE/2];
  memset(prev, 0, sizeof(prev));

  debug_printf("Starting audio analyzer task\n");

  while (1) {
    // Wait until the other side gives us a buffer to analyze
    select {
    case i_client.swap_buffers(int * movable &other):
      int * movable tmp;
      tmp = move(pbuf);
      pbuf = move(other);
      other = move(tmp);
      // This task will not analyze this buffer straight away but will
      // just notify the scheduler that it is ready to go
      scheduler.ready();
      break;
    case scheduler.do_analysis():
      int (& restrict buf)[AUDIO_ANALYZER_FFT_SIZE/2] = pbuf;

      unsigned max_amp = 0;
      for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
        unsigned amp = buf[i] > 0 ? buf[i] : -buf[i];
        if (amp > max_amp)
          max_amp = amp;
      }
      switch (state) {
        case ANALYZER_IDLE:
          if (max_amp > AUDIO_SIGNAL_DETECT_THRESHOLD) {
            sig_detect_count++;
            if (sig_detect_count > SIGNAL_DETECT_COUNT_THRESHOLD) {
              state = ANALYZER_ACTIVE;
              debug_printf("Channel %u: Signal detected (amplitute: %u)\n",
                  chan_id, max_amp);
              sig_detect_count = 0;
            }
          } else {
            sig_detect_count = 0;
          }
          break;

        case ANALYZER_ACTIVE:
          if (max_amp < AUDIO_SIGNAL_DETECT_THRESHOLD) {
            signal_lost(chan_id, state, glitch_count, reported_freq);
          } else {
            int glitch_detected = do_fft_analysis(prev, buf, chan_id, sample_rate,
                glitch_count, reported_freq, i_error_reporting);
            if (glitch_detected)
              state = ANALYZER_GLITCH_DETECTED;
          }
          break;

        case ANALYZER_GLITCH_DETECTED:
          if (max_amp < AUDIO_SIGNAL_DETECT_THRESHOLD) {
            signal_lost(chan_id, state, glitch_count, reported_freq);
            i_error_reporting.cancel_glitch();
          } else {
            i_error_reporting.report_glitch();
            state = ANALYZER_GLITCH_REPORTED;
          }
          break;

        case ANALYZER_GLITCH_REPORTED:
          if (max_amp < AUDIO_SIGNAL_DETECT_THRESHOLD) {
            signal_lost(chan_id, state, glitch_count, reported_freq);
          } else {
            // Continue analysis to track glitch count
            do_fft_analysis(prev, buf, chan_id, sample_rate,
                glitch_count, reported_freq, i_error_reporting);
          }
          break;
      }
      // The analyzer gets given half a window worth of samples at a time.
      memcpy(prev, buf, AUDIO_ANALYZER_FFT_SIZE/2 * sizeof(int));
      break;
    }
  }
}

[[combinable]]
void analysis_scheduler(client interface audio_analysis_scheduler_if analyzer[n], unsigned n)
{
  unsigned ready_count = 0;
  while (1) {
    select {
      case analyzer[int i].ready():
        ready_count++;
        if (ready_count == n) {
          for (int j = 0; j < n; j++)
            analyzer[j].do_analysis();
          ready_count = 0;
        }
        break;
    }
  }
}
