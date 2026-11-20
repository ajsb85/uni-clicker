#ifndef UNI_CLICKER_NECTO_LOG_H
#define UNI_CLICKER_NECTO_LOG_H

typedef struct { unsigned baud; } log_cfg_t;
typedef log_cfg_t log_t;

#define LOG_MAP_USB_UART(cfg) ((cfg).baud = 115200)
void log_init(log_t *logger, const log_cfg_t *cfg);
void log_printf(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));
void log_info(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));
void log_error(log_t *logger, const char *format, ...)
    __attribute__((format(printf, 2, 3)));

#endif
