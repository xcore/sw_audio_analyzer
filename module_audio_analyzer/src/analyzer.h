#ifndef ANALYZER_H_
#define ANALYZER_H_

#define FFT_POINTS 		256			// Number of signal samples chosen for FFT computation
#define FFT_PEAK_POINTS 128			// Number of spectral peaks; for envelope detection
#define SIGNAL_FREQ		5500		//Frequency of test sine wave signal

unsigned do_spectral_analysis();
void write_spectral_result(unsigned peak_index, unsigned peak_value);
void analyze_spectral_peaks();

#endif /* ANALYZER_H_ */
