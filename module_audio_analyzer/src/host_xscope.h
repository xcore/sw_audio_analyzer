#ifndef __host_xscope_h__
#define __host_xscope_h__

enum xscope_host_commands {
  HOST_ENABLE_ALL,
  HOST_ENABLE_ONE,
  HOST_DISABLE_ALL,
  HOST_DISABLE_ONE,
  HOST_CONFIGURE_ONE,
  HOST_ACK_DATA,
  HOST_SIGNAL_DUMP_ONE,
  HOST_SET_VOLUME,
  HOST_SET_BASE,
  HOST_RELAY_OPEN,
  HOST_RELAY_CLOSE,
};

#endif // __host_xscope_h__
