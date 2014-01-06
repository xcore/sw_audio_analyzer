#ifndef __audiohw_h__
#define __audiohw_h__

#define AUDIO_IO_TILE 0

#define AUDIO_SETTLE_IGNORE_COUNT         100000
#define AUDIO_SIGNAL_DETECT_THRESHOLD   15000000
#define AUDIO_NOISE_FLOOR                     15


void AudioHwInit(void);
void genclock(void);

#endif // __audiohw_h__
