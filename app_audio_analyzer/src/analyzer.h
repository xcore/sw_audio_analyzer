#ifndef ANALYZER_H_
#define ANALYZER_H_

#define FFT_POINTS 		256			// Number of signal samples chosen for FFT computation. It is double the level meter bands.
#define FFT_SINE 		sine_256	// Sine wave selected for FFT computation
#define FFT_PEAK_POINTS 128			// Number of signal samples chosen for FFT computation. It is double the level meter bands.
#define SIGNAL_FREQ		8000		//Frequency of test sine wave signal

void write_audio_data(unsigned data);
unsigned get_audio_data();
unsigned do_spectral_analysis();
void write_spectral_result(unsigned peak_index, unsigned peak_value);
void analyze_spectral_peaks();

#endif /* ANALYZER_H_ */
