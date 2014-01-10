#ifndef AUDIO_ANALYZER_H_
#define AUDIO_ANALYZER_H_

#ifndef AUDIO_ANALYZER_FFT_SIZE
#define AUDIO_ANALYZER_FFT_SIZE 1024
#endif

interface error_reporting_if {
  /*
   * Set the channel id of the interface reporting errors.
   */
  void set_chan_id(unsigned id);

  /*
   * A glitch has been detected, but could be due to signal ending so just
   * provide samples for now.
   */
  void glitch_detected(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                       int cur[AUDIO_ANALYZER_FFT_SIZE/2],
                       unsigned average, unsigned max);

  /*
   * Dump the current signal data
   */
  void signal_dump(int prev[AUDIO_ANALYZER_FFT_SIZE/2],
                   int cur[AUDIO_ANALYZER_FFT_SIZE/2]);

  /*
   * Report the glitch to the host.
   */
  void report_glitch();

  /*
   * Was not a glitch, but rather the end of the signal, so don't report it.
   */
  void cancel_glitch();
};

interface analysis_control_if {
  /*
   * Get a dump of the current signal data.
   */
  void request_signal_dump();

  /*
   * Host has re-configured the channel id
   */
  void set_chan_id(unsigned id);
};

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
                    unsigned sample_rate, unsigned chan_id,
                    client interface error_reporting_if i_error_reporting,
                    server interface analysis_control_if i_control);

[[combinable]]
void analysis_scheduler(client interface audio_analysis_scheduler_if i[n], unsigned n);

void i2s_tap(streaming chanend c_i2s,
             streaming chanend c_samples_out,
             client interface audio_analysis_if analyzer[n],
             unsigned n);

void analyze_ramp(streaming chanend c_dig_in, unsigned chan_id);

#endif /* AUDIO_ANALYZER_H_ */
