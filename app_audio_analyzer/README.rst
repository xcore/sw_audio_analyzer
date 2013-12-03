Audio analyzer
==============

:scope: Test application
:description: An application to detect the audio signal presence, report its frequency, indetify any silence or glitches
:keywords: FFT, signal, spectrum
:boards: XA-SKC-L16, XA-SK-AUDIO

Description
-----------

This demonstration uses the L16 core board to perform fft on a received stereo signal, analyze its spectrum for valid signal frequency, identify silence or glitches.

Some features:

*detect and report the frequency of the incoming (listener) audio signal
*derive audio source presence, identify silence and glitches on a real-time basis


Notes
-----

* FFT provides a stable spectrum for a test signal of a standard frequency. Run time spectral analysis of the test signal would indicate the audio presence and spectral peak should indicate about the validity of the signal
* For silence/gap detection, a simplest approach is followed by ascertaining the time windowed magnitude spectral peak and perform a running envelope of these peaks
* For glitch detection, presence of a spectral peak in regions other than spectral peak range with sufficient energy might indicate a glitch
* For a sample sinusoidal test signal of a fixed frquency, same sample is provided as input to both the channels


Audio test setup
----------------

* XA-SK-AUDIO sliceCARD is connected to a tester L16 sliceKIT board.
* Test signal generated from a L16 core is fed to the i2s DAC and is connected as input to a talker source of an AVB board
* Audio signal to be analyzed from a listener is fed back to the ADC channel of the tester board's XA-SK-AUDIO sliceCARD 


To do
-----

* I2S integration and related tests
* periodic reporting to host
* integration into existing avb test framework
* xscope cmd handling for signal generation control

