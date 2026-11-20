#ifndef UNI_TBAND_PORT_H
#define UNI_TBAND_PORT_H

#include "stm32f7xx.h"

extern volatile uint64_t uni_trace_ticks;
#define tband_portTIMESTAMP() (uni_trace_ticks)
#define tband_portTIMESTAMP_RESOLUTION_NS 1000000ULL
#define tband_portNUMBER_OF_CORES 1
#define tband_portGET_CORE_ID() 0
#define tband_portENTER_CRITICAL_FROM_ANY() \
    uint32_t saved_primask = __get_PRIMASK(); \
    __disable_irq()
#define tband_portEXIT_CRITICAL_FROM_ANY() __set_PRIMASK(saved_primask)

#endif
