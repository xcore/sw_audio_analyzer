#ifndef __audiohw_h__
#define __audiohw_h__

#define AUDIO_SETTLE_IGNORE_COUNT          20000
#define AUDIO_SIGNAL_DETECT_THRESHOLD   90000000
#define AUDIO_NOISE_FLOOR                     25

void AudioHwInit(void);
void genclock(void);

#endif // __audiohw_h__
