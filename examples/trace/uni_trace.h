#ifndef UNI_TRACE_H
#define UNI_TRACE_H

#include "tband.h"
#include <stdbool.h>

void uni_trace_start(void);
#ifdef UNI_TBAND_MICROSECOND_CLOCK
void uni_trace_clock_init(void);
#else
void uni_trace_tick(void);
#endif
bool uni_trace_stop(void);

#endif
