#ifndef UNI_SWIFT_BOARD_H
#define UNI_SWIFT_BOARD_H

#include <stdint.h>

void board_init(void);
void board_wait_ms(uint32_t milliseconds);
void board_set_led(uint32_t edges);
void board_uart_write(const uint8_t *bytes, uint32_t length);

#endif
