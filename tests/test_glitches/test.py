import sys
import os
import time
rootDir = os.path.join(os.path.dirname(os.path.realpath(__file__)),'..','..','..')
sys.path.append(os.path.join(rootDir,'test_framework'))

from twisted.internet import reactor
from twisted.internet.defer import inlineCallbacks

from xmos.test.base import AllOf, OneOf, NoneOf, Sequence, Expected
import xmos.test.base as base
import xmos.test.master
import xmos.test.process as process

from xmos.test.xmos_logging import *

def xrunProcess(master, adapter_id, name, xe):
  p = process.XrunProcess(name, master, output_file="{name}.log".format(name=name), verbose=True)
  exe_name = base.exe_name('xrun')
  xrun = base.file_abspath(exe_name) # Windows requires the absolute path of xrun
  reactor.spawnProcess(p, xrun, [xrun, '--adapter-id', adapter_id, '--xscope-port', 'localhost:12346', xe],
    env=os.environ, )
  return p

@inlineCallbacks
def runTest(args):
  master = xmos.test.master.Master()

  analysis_bin = os.path.join(rootDir, 'sw_audio_analyzer', 'app_audio_analyzer_avb',
                             'bin', 'audio_analyzer.xe')
  xrun = xrunProcess(master, args.adapter_id, "xrun", analysis_bin)

  controller_path = os.path.join(rootDir, 'sw_audio_analyzer', 'host_audio_analyzer')
  controller_id = 'controller'
  controller = process.Process(controller_id, master, output_file="controller.log", verbose=True)
  reactor.spawnProcess(controller, './audio_analyzer', ['./audio_analyzer'],
    env=os.environ, path=controller_path)

  # Wait for the controller to have started
  yield master.expect(Expected(controller_id, "^Starting I2S$", 10)) 

  # Allow time for everything to settle
  yield base.sleep(5)

  master.sendLine(controller_id, "d a")
  yield master.expect(Expected(controller_id, "Channel 0: disabled", 15))

  # There needs to be small delays to allow the audio signals to settle, otherwise
  # spurious glitches are detected.
  delay = 0.5
  test_frequencies = [1000, 2000, 4000, 8000]

  # Ensure that there is no glitch by default
  for freq in test_frequencies:
    master.sendLine(controller_id, "d 0")
    yield master.expect(Expected(controller_id, "Channel 0: disabled", 15))
    yield base.sleep(delay)
    master.sendLine(controller_id, "c 0 {freq}".format(freq=freq))
    yield master.expect(Expected(controller_id, "Generating sine table for chan 0", 15))
    yield base.sleep(delay)
    master.sendLine(controller_id, "e 0")
    yield master.expect(Sequence([
        Expected(controller_id, "Channel 0: enabled", 5),
        Expected(controller_id, "Channel 0: Signal detected", 10),
        Expected(controller_id, "Channel 0: Frequency %d" % freq, 5)]))
    yield master.expect(NoneOf([Expected(controller_id, "ERROR: Channel 0: glitch detected", 30)]))

  offset = 5000
  for freq in test_frequencies:
    log_info("-----------------")
    log_info("Test %d Hz" % freq)
    num_points = int(48000/freq);
    for period in range(0, num_points):
      log_info("Test for glitch at %d (%d/%d)" % (freq, period + 1, num_points))

      # Disable all channels
      master.sendLine(controller_id, "d 0")
      yield master.expect(Expected(controller_id, "Channel 0: disabled", 15))
      yield base.sleep(delay)
      master.sendLine(controller_id, "c 0 {freq} -1 0 {period}".format(freq=freq, period=period+offset))
      yield master.expect(Expected(controller_id, "Generating sine table for chan 0", 15))
      yield base.sleep(delay)
      master.sendLine(controller_id, "e 0")
      yield master.expect(Sequence([
          Expected(controller_id, "Channel 0: enabled", 5),
          Expected(controller_id, "Channel 0: Signal detected", 10),
          Expected(controller_id, "Channel 0: Frequency %d" % freq, 5)]))
      yield master.expect(Expected(controller_id, "ERROR: Channel 0: glitch detected", 15))
      yield base.sleep(delay)

  base.testComplete(reactor)


if __name__ == "__main__":
  parser = base.getParser()
  parser.add_argument("adapter_id", type=str)
  args = parser.parse_args()

  configure_logging(level_file='DEBUG')
  base.testStart(runTest, args)

