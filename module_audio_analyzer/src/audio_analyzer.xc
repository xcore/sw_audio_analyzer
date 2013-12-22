#include "audio_analyzer.h"
#include "fft.h"
#include "string.h"
#include "debug_print.h"
#include "xscope.h"
#include "stdlib.h"
#include "hann.h"

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


static void do_fft_analysis(int sig[AUDIO_ANALYZER_FFT_SIZE], unsigned chan_id,
                            unsigned sample_rate, int &reported_freq,
                            int &reported_glitch, int &peak_freq)
{
  int im[AUDIO_ANALYZER_FFT_SIZE];
  int wsig[AUDIO_ANALYZER_FFT_SIZE];
  memset(im, 0, sizeof(im));

  if (DUMP_FIRST_ANALYSIS && chan_id == 0) {
    for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE; i++) {
      debug_printf("%d,", sig[i]);
    }
    debug_printf("\n");
  }

  // FFT
  windowHann(wsig, sig, 0, AUDIO_ANALYZER_FFT_SIZE, FFT_SINE(AUDIO_ANALYZER_FFT_SIZE));
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
        debug_printf("Channel %u: glitch detected (index %u, magnitude %d)\n", chan_id, i, mag_i);
        if (chan_id == 1 && 0) {
          for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE; i++) {
            debug_printf("%d,", sig[i]);
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
  int sig[AUDIO_ANALYZER_FFT_SIZE];
  int * movable pbuf = initial_buffer;
  debug_printf("Starting audio analyzer task\n");
  memset(sig, 0, sizeof(sig));
  int signal_started = 0, sig_detect_count = 0;
  int reported_freq = 0, reported_glitch = 0;
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
      // The analyzer gets given half a window worth of samples at a time.
      // We then shift the samples up from the previous window to get the a full sliding window
      memmove(sig, &sig[AUDIO_ANALYZER_FFT_SIZE/2], AUDIO_ANALYZER_FFT_SIZE/2 * sizeof(int));
      memcpy(&sig[AUDIO_ANALYZER_FFT_SIZE/2], buf, AUDIO_ANALYZER_FFT_SIZE/2 * sizeof(int));
      if (!signal_started) {
        unsigned max_amp = 0;
        for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE/2; i++) {
          unsigned amp = buf[i] > 0 ? buf[i] : -buf[i];
          if (amp > max_amp)
            max_amp = amp;
        }
        if (max_amp > SIGNAL_DETECT_THRESHOLD) {
          sig_detect_count++;
          if (sig_detect_count > SIGNAL_DETECT_COUNT_THRESHOLD) {
            signal_started = 1;
            debug_printf("Channel %u: Signal detected (amplitute: %u)\n",
                chan_id, max_amp);
          }
        }
        else {
          sig_detect_count = 0;
        }
      }
      else {
        do_fft_analysis(sig, chan_id, sample_rate, reported_freq, reported_glitch, peak_freq);
      }
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
