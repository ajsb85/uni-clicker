#ifndef UNI_CLICKER_NECTO_ME_BUILT_IN_H
#define UNI_CLICKER_NECTO_ME_BUILT_IN_H

#include <stdint.h>

/* Byte and halfword extractions used by the SDK conversion library. */
static inline uint8_t Hi(uint16_t value)
{
    return (uint8_t)(value >> 8);
}

static inline uint8_t Lo(uint16_t value)
{
    return (uint8_t)value;
}

static inline uint16_t HiWord(uint32_t value)
{
    return (uint16_t)(value >> 16);
}

static inline uint16_t LoWord(uint32_t value)
{
    return (uint16_t)value;
}

#endif
