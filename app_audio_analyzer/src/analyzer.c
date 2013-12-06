#include "analyzer.h"
#include "debug_print.h"

#define SIG_ENERGY_THRESH	50000000  //TODO: to derive a meaningful value for this
#define NUM_LUT_ENTRIES		6

//base fn: 2048*sin(2*3.1415926535*(SIGNAL_FREQ/SAMP_FREQ)*i);
//i<=(XS1_TIMER_HZ/SAMP_FREQ)
unsigned lkup_fft_256[NUM_LUT_ENTRIES][2] = {
		{5,693130},   //1000 hz
		{11, 693130}, //2000 hz
		{21, 706210}, //4000 hz
		{53, 711209}, //10000 hz
		{107, 714825}, //20000 hz
		{123, 699005}, //23000 hz
};

typedef struct spectral_buf {
  unsigned value[FFT_PEAK_POINTS][2];//{peak_index:value} pairs
  unsigned index;
  unsigned depth;
} spectral_buf;

spectral_buf spectral_peaks;


void write_spectral_result(unsigned peak_index, unsigned peak_value)
{
  int index = spectral_peaks.index;
  spectral_peaks.value[index][0] = peak_index;
  spectral_peaks.value[index][1] = peak_value;
  spectral_peaks.index = (index+1)%FFT_PEAK_POINTS;
  spectral_peaks.depth = (spectral_peaks.depth+1)%FFT_PEAK_POINTS;
}

unsigned do_spectral_analysis()
{
  return spectral_peaks.depth;
}

/* identifies whether listener signal peak and frequency are in valid range? */
/* detects audio presence/absence */
void analyze_spectral_peaks()
{
  int depth = spectral_peaks.depth;
  int index = spectral_peaks.index;
  int iter = 0;
  int lkup_done = 0;
  int lkup_val = 0;
  int delta = 0;
  for (int i=0; i<depth; i++) {
	/* check if index and magnitude are well with in a tolerance limit */
	iter = (index-i)%FFT_PEAK_POINTS;
	if (iter < 0)
	  iter += FFT_PEAK_POINTS;

	/* for the entire depth, lookup once to identify valid range */
	for (int j=0; (j<NUM_LUT_ENTRIES)&&(!lkup_done); j++) {
	  if (lkup_fft_256[j][0] <= spectral_peaks.value[iter][0]) {
		lkup_done = 1;
		lkup_val = lkup_fft_256[j][1];
	  }
	}

	if ((delta = spectral_peaks.value[iter][1] - lkup_val) < 0)
	  delta *= -1;

	if (delta < SIG_ENERGY_THRESH) {
	  int temp = (spectral_peaks.value[iter][0]*1000)/5.5;
	  debug_printf("detected signal : freq = %d, energy is Ok\n", temp);
	}
	else {
	  debug_printf("absence of signal: either silence detected or talker not active?\n");
	}
  }
  spectral_peaks.depth -= depth;
}

