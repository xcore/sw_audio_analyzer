#include "audio_analyzer.h"
#include "fft.h"
#include "string.h"
#include "debug_print.h"
#include "xscope.h"
#include "stdlib.h"
#include "hann.h"
#include "xs1.h"

#define DUMP_FIRST_ANALYSIS 0

#define SIGNAL_DETECT_THRESHOLD       90000000
#define SIGNAL_DETECT_COUNT_THRESHOLD 15

#define PEAK_IGNORE_WINDOW              15
#define NOISE_FLOOR                     25
#define GLITCH_TOLERANCE_RATIO_A       7
#define GLITCH_TOLERANCE_RATIO_B       25
#define LOW_FREQUENCY_IGNORE_THRESHOLD  5

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

static void do_fft_analysis(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                            int cur[AUDIO_ANALYZER_FFT_SIZE/2],
                            unsigned chan_id,
                            unsigned sample_rate, int &reported_freq,
                            int &reported_glitch, int &peak_freq)
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

  if (max_val < NOISE_FLOOR)
    return;
  max_val -= NOISE_FLOOR;

  if (!reported_freq) {
    unsigned freq;
    peak_freq = max_val;
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
  for (int i = LOW_FREQUENCY_IGNORE_THRESHOLD; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
    if (i >= max_index - PEAK_IGNORE_WINDOW && i < max_index + PEAK_IGNORE_WINDOW)
      continue;
    if (mag[i] < NOISE_FLOOR)
      continue;
    unsigned mag_i = mag[i] - NOISE_FLOOR;

    if (mag_i > tolerance) {
      // Found a glitch
      if (!reported_glitch) {
        debug_printf("ERROR: Channel %u: glitch detected (index %u, magnitude %d)\n", chan_id, i, mag_i);
        if (chan_id == 1 && 0) {
          for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
            debug_printf("%d,", prev[i]);
          }
          for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
            debug_printf("%d,", cur[i]);
          }
          debug_printf("\n");
        }
        reported_glitch = 1;
      }
    }
  }

}


[[combinable]]
void audio_analyzer(server interface audio_analysis_if i_client,
                    server interface audio_analysis_scheduler_if scheduler,
                    unsigned sample_rate, unsigned chan_id)
{
  int initial_buffer[AUDIO_ANALYZER_FFT_SIZE/2];
  int prev[AUDIO_ANALYZER_FFT_SIZE/2];
  int * movable pbuf = initial_buffer;
  debug_printf("Starting audio analyzer task\n");
  memset(prev, 0, sizeof(prev));
  int signal_started = 0, sig_detect_count = 0;
  int reported_freq = 0, reported_glitch = 0;
  int lost_signal = 0, reported_interrupt = 0;
  int peak_freq = 0;
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
      if (!signal_started) {
        if (max_amp > SIGNAL_DETECT_THRESHOLD) {
          sig_detect_count++;
          if (sig_detect_count > SIGNAL_DETECT_COUNT_THRESHOLD) {
            signal_started = 1;
            debug_printf("Channel %u: Signal detected (amplitute: %u)\n",
                chan_id, max_amp);
            sig_detect_count = 0;
          }
        }
        else {
          sig_detect_count = 0;
        }
      }
      else if (max_amp < SIGNAL_DETECT_THRESHOLD) {
        if (!lost_signal) {
          debug_printf("Channel %u: Lost signal\n", chan_id);
          lost_signal = 1;
        }
      }
      else if (lost_signal && max_amp > SIGNAL_DETECT_COUNT_THRESHOLD) {
        if (!reported_interrupt) {
          debug_printf("Channel %u: Resumed signal\n", chan_id);
          debug_printf("ERROR: Channel %u: Interrupted signal\n", chan_id);
          reported_interrupt = 1;
        }
      }
      else {
        do_fft_analysis(prev, buf, chan_id, sample_rate, reported_freq, reported_glitch, peak_freq);
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
