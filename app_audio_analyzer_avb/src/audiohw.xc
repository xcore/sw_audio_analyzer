#include <xs1.h>
#include <print.h>
#include <platform.h>
#include <assert.h>
#include "i2c.h"
#include "app_global.h"
#include "audiohw.h"

#define CODEC_DEV_ID_ADDR           0x01
#define CODEC_PWR_CTRL_ADDR         0x02
#define CODEC_MODE_CTRL_ADDR        0x03
#define CODEC_ADC_DAC_CTRL_ADDR     0x04
#define CODEC_TRAN_CTRL_ADDR        0x05
#define CODEC_MUTE_CTRL_ADDR        0x06
#define CODEC_DACA_VOL_ADDR         0x07
#define CODEC_DACB_VOL_ADDR         0x08

static unsigned char codec_regaddr[8] = { CODEC_PWR_CTRL_ADDR,
                                    CODEC_MODE_CTRL_ADDR,
                                    CODEC_ADC_DAC_CTRL_ADDR,
                                    CODEC_TRAN_CTRL_ADDR,
                                    CODEC_MUTE_CTRL_ADDR,
                                    CODEC_DACA_VOL_ADDR,
                                    CODEC_DACB_VOL_ADDR,
                                    CODEC_PWR_CTRL_ADDR
                                  };
static unsigned char codec_regdata[8] = {0x01,0x35,0x09,0x60,0x00,0x00,0x00,0x00};

// CODEC control ports
#define PORT_I2C_SCL      on tile[AUDIO_IO_TILE]:XS1_PORT_1M
#define PORT_I2C_SDA      on tile[AUDIO_IO_TILE]:XS1_PORT_1N
#define PORT_PLL_REF      on tile[AUDIO_IO_TILE]:XS1_PORT_1P
#define PORT_AUD_CFG      on tile[AUDIO_IO_TILE]:XS1_PORT_4E

/* I2C ports */
on tile[AUDIO_IO_TILE]: struct r_i2c i2cPorts = {PORT_I2C_SCL, PORT_I2C_SDA};

/* Reference clock to external fractional-N clock multiplier */
on tile[AUDIO_IO_TILE]: out port p_pll_ref    = PORT_PLL_REF;
on tile[AUDIO_IO_TILE]: out port p_codec_reset  = PORT_AUD_CFG;

static unsigned char pll_regaddr[9] = {0x09,0x08,0x07,0x06,0x17,0x16,0x05,0x03,0x1E};
static unsigned char pll_regdata[9] = {0x00,0x00,0x00,0x00,0x00,0x08,0x01,0x01,0x00};

// Set up the multiplier in the PLL clock generator
void audio_clock_CS2100CP_init(struct r_i2c &r_i2c, unsigned multiplier)
{
  int deviceAddr = 0x4E;
  unsigned int mult[1];

  // this is the muiltiplier in the PLL, which takes the PLL reference clock and
  // multiplies it up to the MCLK frequency. The PLL takes it in the 20.12 format.
  mult[0] = multiplier << 12;
  pll_regdata[0] = (mult,char[])[0];
  pll_regdata[1] = (mult,char[])[1];
  pll_regdata[2] = (mult,char[])[2];
  pll_regdata[3] = (mult,char[])[3];

  i2c_master_init(r_i2c);

  for(int i = 8; i >= 0; i--) {
    unsigned char data[1];
    data[0] = (pll_regdata,unsigned char[])[i];
    i2c_master_write_reg(deviceAddr, pll_regaddr[i], data, 1, r_i2c);
  }
}

void audio_codec_CS4270_init(int codec_addr, struct r_i2c &r_i2c)
{
  for (int i = 0; i < 8; i++) {
    char data[1];
    data[0] = codec_regdata[i];
    i2c_master_write_reg(codec_addr, codec_regaddr[i], data, 1, r_i2c);
  }
}

void AudioHwInit(void)
{
  timer tmr;
  unsigned time;

  i2c_master_init(i2cPorts);

  // The PLL takes a 24MHz crystal input
  audio_clock_CS2100CP_init(i2cPorts, MCLK_FREQ/300);

  delay_seconds(1);

  // Bring codec out of reset
  p_codec_reset <: 0xF;

  tmr :> time;
  time += 100;
  tmr when timerafter(time) :> int _;

  audio_codec_CS4270_init(0x48, i2cPorts);
  audio_codec_CS4270_init(0x49, i2cPorts);

  return;
}

/* Core to generate 300Hz reference to CS2100 PLL */
void genclock()
{
    timer t;
    unsigned time;
    unsigned pinVal = 0;

    t :> time;
    while(1)
    {
        p_pll_ref <: pinVal;
        pinVal = ~pinVal;
        time += 166667;
        t when timerafter(time) :> void;
    }
}


