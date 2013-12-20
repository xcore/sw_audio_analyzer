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
  void swap_buffers(int * movable &buffer);
};

interface audio_analysis_scheduler_if {
  [[notification]] slave void ready();
  [[clears_notification]] void do_analysis();
};


/** An FFT based audio analyzer.
 *
 */
[[combinable]]
void audio_analyzer(server interface audio_analysis_if get_data,
                    server interface audio_analysis_scheduler_if i_sched,
                    unsigned sample_rate, unsigned chan_id);

[[combinable]]
void analysis_scheduler(client interface audio_analysis_scheduler_if i[n], unsigned n);

void i2s_tap(streaming chanend c_i2s,
             streaming chanend c_samples_out,
             client interface audio_analysis_if analyzer[n],
             unsigned n);

#endif /* AUDIO_ANALYZER_H_ */
