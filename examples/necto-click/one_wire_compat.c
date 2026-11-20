/* Supply the SDK's OneWire command definitions to its STM32 implementation. */
#include "common_macros.h"

#undef __weak
#define __weak __attribute__((weak))
#include "hal_ll_one_wire.c"
