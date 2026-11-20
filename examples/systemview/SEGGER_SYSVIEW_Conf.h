#ifndef UNI_SEGGER_SYSVIEW_CONF_H
#define UNI_SEGGER_SYSVIEW_CONF_H

#include <stdint.h>

uint32_t uni_systemview_timestamp(void);

#define SEGGER_SYSVIEW_GET_TIMESTAMP() uni_systemview_timestamp()
#define SEGGER_SYSVIEW_RTT_CHANNEL 1
#define SEGGER_SYSVIEW_RTT_BUFFER_SIZE 2048

#endif
