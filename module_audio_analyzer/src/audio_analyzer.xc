#include "analyzer.h"
#include "audio_analyzer.h"
#include "fft.h"
#include "string.h"
#include "debug_print.h"
#include "xscope.h"
#include "stdlib.h"
#include "hann.h"

#define DUMP_FIRST_ANALYSIS 0

static void magnitude_spectrum(int sig[AUDIO_ANALYZER_FFT_SIZE], unsigned magSpectrum[AUDIO_ANALYZER_FFT_SIZE])
{
  int im[AUDIO_ANALYZER_FFT_SIZE];
  int wsig[AUDIO_ANALYZER_FFT_SIZE];

  memset(im, 0, sizeof(im));

  if (DUMP_FIRST_ANALYSIS) {
    for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE; i++) {
      debug_printf("%d,", sig[i]);
    }
    debug_printf("\n");
  }

  // FFT
  windowHann(wsig, sig, 0, AUDIO_ANALYZER_FFT_SIZE, FFT_SINE(AUDIO_ANALYZER_FFT_SIZE));
  fftTwiddle(sig, im, AUDIO_ANALYZER_FFT_SIZE);
  fftForward(sig, im, AUDIO_ANALYZER_FFT_SIZE, FFT_SINE(AUDIO_ANALYZER_FFT_SIZE));

  // Magnitude spectrum
  long long mag_spec;
  for (int i=0; i<AUDIO_ANALYZER_FFT_SIZE; i++) {
    mag_spec = sig[i]*sig[i] + im[i]*im[i];
    magSpectrum[i] = mag_spec; // >> 32;
#if LOG_SPEC
  magSpectrum[i] = (magSpectrum[i]>0)? 10*log(magSpectrum[i]):0;
#endif
  }

  if (DUMP_FIRST_ANALYSIS) {
    for (int i = 0; i < AUDIO_ANALYZER_FFT_SIZE; i++) {
      debug_printf("%d,", magSpectrum[i]);
    }
    debug_printf("\n");
    exit(0);
  }
}

#define PEAK_RANGE      5
#define OTHER_ENERGY_THRESH 50000   //TODO: adjust its validity during tests
#define GLITCH_THRESHOLD  100000  //TODO: adjust its validity during tests

void audio_analyzer(server interface audio_analysis_if get_data)
{
  unsigned mag_spec[AUDIO_ANALYZER_FFT_SIZE];
  unsigned max_mag_spec_val = 0;
  unsigned max_mag_spec_idx = 0;
  unsigned peak_energy;
  unsigned other_energy;
  unsigned other_energy_ctr = 0;
  int initial_buffer[AUDIO_ANALYZER_FFT_SIZE];
  int * movable buf = initial_buffer;
  debug_printf("Starting audio analyzer task\n");
  while (1) {
    // Wait until the other side gives us a buffer to analyze
    select {
    case get_data.do_analysis_and_swap_buffers(int * movable &other):
      int * movable tmp;
      tmp = move(buf);
      buf = move(other);
      other = move(tmp);
      break;
    }

    //if (read_data_buffer->depth > AUDIO_ANALYZER_FFT_SIZE/2) {
    if (1) {
      peak_energy = 0;
      other_energy = 0;
      other_energy_ctr = 0;

      magnitude_spectrum(buf, mag_spec);
      mag_spec[0] = 0;  // Set DC component to 0
      max_mag_spec_val = 0;
      max_mag_spec_idx = 0;

      for (int i=0; i<AUDIO_ANALYZER_FFT_SIZE; i++) {
        xscope_int(AUDIO_ANALYZER_MAG_SPEC, mag_spec[i]);
      }

      /* compute spectral peak */
      for (int i=0; i<AUDIO_ANALYZER_FFT_SIZE/2; i++) {
        if (max_mag_spec_val < mag_spec[i]) {
          max_mag_spec_val = mag_spec[i];
          max_mag_spec_idx = i;
        }
      }
      write_spectral_result(max_mag_spec_idx, max_mag_spec_val);

      //perform glitch analysis
      int tmp_idx = 0;
      for(int i=(-PEAK_RANGE); i<= PEAK_RANGE;i++) {
        tmp_idx = max_mag_spec_idx+i;
        if (( tmp_idx >= 0) && (tmp_idx < (AUDIO_ANALYZER_FFT_SIZE/2)))
            peak_energy += mag_spec[tmp_idx];
      }
      for (int i=0; i<AUDIO_ANALYZER_FFT_SIZE/2; i++) {
        if((i < (max_mag_spec_idx-PEAK_RANGE)) || (i > (max_mag_spec_idx+PEAK_RANGE))) {
          if(mag_spec[i] > OTHER_ENERGY_THRESH) {
            other_energy += mag_spec[i];
            other_energy_ctr++;
          }
        }
      }

      peak_energy /= (PEAK_RANGE*2+1);
      //other_energy /= (other_energy_ctr-(PEAK_RANGE*2+1));
      if (other_energy_ctr > 0) {
        other_energy /= other_energy_ctr;
        if(other_energy > GLITCH_THRESHOLD) {
          debug_printf("glitch suspected!!!\n");
        }
      }
    }

    if (do_spectral_analysis())
      analyze_spectral_peaks();
  } //end of while(1)
}
