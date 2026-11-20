#ifndef UNI_CLICKER_NECTO_LOG_H
#define UNI_CLICKER_NECTO_LOG_H

typedef struct { unsigned baud; } log_cfg_t;

#ifdef UNI_CLICKER_UART_LOG
#include "drv_uart.h"
typedef struct {
    uart_t uart;
    uint8_t tx[256];
    uint8_t rx[256];
} log_t;
int8_t log_read(log_t *logger, uint8_t *buffer, uint8_t max_len);
#else
typedef log_cfg_t log_t;
#endif

#define LOG_MAP_USB_UART(cfg) ((cfg).baud = 115200)
void log_init(log_t *logger, const log_cfg_t *cfg);
void log_printf(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));
void log_info(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));
void log_error(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));
void log_warning(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));

#endif
