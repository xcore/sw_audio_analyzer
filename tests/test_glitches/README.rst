Glitch Test
===========

This test first ensures that the audio can be heard without glitches at each of
the test frequencies. Then it ensures that glitches are detected regardless of
where in the sine wave they are inserted.

It is run using:
  python test.py <xtag adapter-id>

It is designed to run on the L16 core board with the XA-SK-AUDIO-PLL slice (AVB slice)
as it runs that binary from this repo.

