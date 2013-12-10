#ifndef AUDIO_ANALYZER_H_
#define AUDIO_ANALYZER_H_

#ifdef __audio_analyzer_conf_h_exists__
#include "audio_analyzer_conf.h"
#endif

#ifndef AUDIO_ANALYZER_FFT_SIZE
#define AUDIO_ANALYZER_FFT_SIZE 1024
#endif

interface audio_analysis_if {
  /* This function will signal to the analyzer to do the analysis on the
   * provided buffer. The buffer variable will be updated to the previously
   * analyzed buffer to be re-filled.
   */
  void do_analysis_and_swap_buffers(int * movable &buffer);
};

/** An FFT based audio analyzer.
 *
 */
void audio_analyzer(server interface audio_analysis_if get_data);

void i2s_tap(streaming chanend c_i2s,
             streaming chanend c_samples_out,
             client interface audio_analysis_if analyzer);

#endif /* AUDIO_ANALYZER_H_ */
