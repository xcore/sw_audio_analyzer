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

#define DUMP_FIRST_ANALYSIS 0

// To ensure a stable signal, wait a number of windows with a valid signal
// before locking on to the signal and performing FFT analysis.
#define SIGNAL_DETECT_COUNT_THRESHOLD   15

// The peak signal is never a simple bin in the FFT. This configures
// how wide of a window around the peak to ignore for noise.
#define PEAK_IGNORE_WINDOW              15

// Ignore the first two FFT bins (DC component and ~50Hz signal)
#define LOW_FREQUENCY_IGNORE_THRESHOLD   2

// A signal is considered to be noise if it is a fraction of the peak value.
// Because the magnitude is a log function this is a simple subtraction operation
// and so if there are less than NOISE_THRESHOLD bits of difference between the
// peak and the bin then it is considered noise.
#define NOISE_THRESHOLD                 24

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
    if (i >= LOW_FREQUENCY_IGNORE_THRESHOLD && mag[i] > max_val) {
      max_val = mag[i];
      max_index = i;
    }
  }

  if (max_val < NOISE_THRESHOLD)
    return 0;

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

  // Check for a glitch - count number of bins which are considered to be above the
  // noise threshold. Allow a number of these for harmonics
  int bin_count = 0;
  int max_noise_magnitude = 0;
  int total_signal = 0;
  int min_peak_index = (max_index > PEAK_IGNORE_WINDOW) ? (max_index - PEAK_IGNORE_WINDOW) : 0;
  for (int i = LOW_FREQUENCY_IGNORE_THRESHOLD; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
    if (i >= min_peak_index && i < max_index + PEAK_IGNORE_WINDOW)
      continue;

    bin_count += 1;
    total_signal += mag[i];
    if (mag[i] > max_noise_magnitude)
      max_noise_magnitude = mag[i];
  }

  int glitch_detected = 0;
  int average = (total_signal / bin_count);
  unsigned tolerance = max_val - NOISE_THRESHOLD;
  if (average > tolerance) {
    glitch_detected = 1;
    if (glitch_count == 0) {
      i_error_reporting.glitch_detected(prev, cur, average, max_noise_magnitude);

      if (chan_id == 0 && 0) {
        for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
          debug_printf("%d,", mag[i]);
        }
        debug_printf("\n");
      }
    }
    glitch_count++;
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
                    server interface audio_analysis_scheduler_if i_scheduler,
                    unsigned sample_rate, unsigned chan_id,
                    client interface error_reporting_if i_error_reporting,
                    server interface analysis_control_if i_control)
{
  int initial_buffer[AUDIO_ANALYZER_FFT_SIZE/2];
  int * movable pbuf = initial_buffer;
  anayzer_state_t state = ANALYZER_IDLE;
  int sig_detect_count = 0;
  int glitch_count = 0;
  int reported_freq = 0;
  int prev[AUDIO_ANALYZER_FFT_SIZE/2];
  int signal_dump_requested = 0;
  memset(prev, 0, sizeof(prev));

  debug_printf("Starting audio analyzer task\n");
  i_error_reporting.set_chan_id(chan_id);

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
      i_scheduler.ready();
      break;

    case i_control.request_signal_dump():
      signal_dump_requested = 1;
      break;

    case i_control.set_chan_id(unsigned id):
      chan_id = id;
      break;

    case i_scheduler.do_analysis():
      int (& restrict buf)[AUDIO_ANALYZER_FFT_SIZE/2] = pbuf;

      if (signal_dump_requested) {
        i_error_reporting.signal_dump(prev, buf);
        signal_dump_requested = 0;
      }

      unsigned max_pos_amp = 0;
      unsigned max_neg_amp = 0;
      for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
        unsigned amp = buf[i] > 0 ? buf[i] : -buf[i];
        if (buf[i] > 0) {
          if (amp > max_pos_amp)
            max_pos_amp = amp;
        } else {
          if (amp > max_neg_amp)
            max_neg_amp = amp;
        }
      }
      switch (state) {
        case ANALYZER_IDLE:
          if (max_pos_amp > AUDIO_SIGNAL_DETECT_THRESHOLD && max_neg_amp > AUDIO_SIGNAL_DETECT_THRESHOLD) {
            sig_detect_count++;
            if (sig_detect_count > SIGNAL_DETECT_COUNT_THRESHOLD) {
              state = ANALYZER_ACTIVE;
              debug_printf("Channel %u: Signal detected (amplitute: %u,-%u)\n",
                  chan_id, max_pos_amp, max_neg_amp);
              sig_detect_count = 0;
            }
          } else {
            sig_detect_count = 0;
          }
          break;

        case ANALYZER_ACTIVE:
          if (max_pos_amp < AUDIO_SIGNAL_DETECT_THRESHOLD || max_neg_amp < AUDIO_SIGNAL_DETECT_THRESHOLD) {
            signal_lost(chan_id, state, glitch_count, reported_freq);
          } else {
            int glitch_detected = do_fft_analysis(prev, buf, chan_id, sample_rate,
                glitch_count, reported_freq, i_error_reporting);
            if (glitch_detected)
              state = ANALYZER_GLITCH_DETECTED;
          }
          break;

        case ANALYZER_GLITCH_DETECTED:
          if (max_pos_amp < AUDIO_SIGNAL_DETECT_THRESHOLD || max_neg_amp < AUDIO_SIGNAL_DETECT_THRESHOLD) {
            signal_lost(chan_id, state, glitch_count, reported_freq);
            i_error_reporting.cancel_glitch();
          } else {
            i_error_reporting.report_glitch();
            state = ANALYZER_GLITCH_REPORTED;
          }
          break;

        case ANALYZER_GLITCH_REPORTED:
          if (max_pos_amp < AUDIO_SIGNAL_DETECT_THRESHOLD || max_neg_amp < AUDIO_SIGNAL_DETECT_THRESHOLD) {
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
