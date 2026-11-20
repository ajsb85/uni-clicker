#include <stdbool.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

#include "stm32f7xx.h"
#include "delays.h"
#include "hal_ll_rcc.h"
#include "log.h"

#ifdef UNI_CLICKER_UART_LOG
#include "hal_ll_pin_names.h"
#endif

enum { hsi_hz = 16000000 };

void RCC_GetClocksFrequency(rcc_clocks_t *clocks)
{
    uint32_t cfgr = RCC->CFGR;

    /* This profile keeps the reset HSI clock source. */
    clocks->sysclk = hsi_hz;
    clocks->hclk = hsi_hz >> AHBPrescTable[(cfgr & RCC_CFGR_HPRE) >> RCC_CFGR_HPRE_Pos];
    clocks->pclk1 = clocks->hclk >> APBPrescTable[(cfgr & RCC_CFGR_PPRE1) >> RCC_CFGR_PPRE1_Pos];
    clocks->pclk2 = clocks->hclk >> APBPrescTable[(cfgr & RCC_CFGR_PPRE2) >> RCC_CFGR_PPRE2_Pos];
}

static void wait_systick(unsigned ticks, unsigned periods)
{
    if (periods == 0) {
        return;
    }
    SysTick->LOAD = ticks - 1;
    SysTick->VAL = 0;
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk;
    while (periods--) {
        while (!(SysTick->CTRL & SysTick_CTRL_COUNTFLAG_Msk)) {}
    }
    SysTick->CTRL = 0;
}

void Delay_ms(unsigned milliseconds)
{
    wait_systick(hsi_hz / 1000, milliseconds);
}

void Delay_us(unsigned microseconds)
{
    wait_systick(hsi_hz / 1000000, microseconds);
}

void log_init(log_t *logger, const log_cfg_t *cfg)
{
#ifdef UNI_CLICKER_UART_LOG
    uart_config_t uart_cfg;
    uart_configure_default(&uart_cfg);
    uart_cfg.tx_pin = GPIO_PC6;
    uart_cfg.rx_pin = GPIO_PC7;
    uart_cfg.baud = cfg->baud;
    uart_cfg.tx_ring_size = sizeof(logger->tx);
    uart_cfg.rx_ring_size = sizeof(logger->rx);
    logger->uart.tx_ring_buffer = logger->tx;
    logger->uart.rx_ring_buffer = logger->rx;
    if (uart_open(&logger->uart, &uart_cfg) != UART_ERROR) {
        uart_set_baud(&logger->uart, cfg->baud);
        uart_set_blocking(&logger->uart, true);
    }
#else
    *logger = *cfg;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    RCC->APB2ENR |= RCC_APB2ENR_USART6EN;
    (void)RCC->AHB1ENR;
    (void)RCC->APB2ENR;

    GPIOC->AFR[0] = (GPIOC->AFR[0] & ~(0xffU << 24)) | (0x88U << 24);
    GPIOC->MODER = (GPIOC->MODER & ~(0x0fU << 12)) | (0x0aU << 12);
    USART6->BRR = (hsi_hz + logger->baud / 2) / logger->baud;
    USART6->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
#endif
}

#ifdef UNI_CLICKER_UART_LOG
int8_t log_read(log_t *logger, uint8_t *buffer, uint8_t max_len)
{
    return uart_read(&logger->uart, buffer, max_len);
}
#endif

static void log_byte(log_t *logger, char value)
{
#ifdef UNI_CLICKER_UART_LOG
    uint8_t byte = value;
    uart_write(&logger->uart, &byte, 1);
#else
    (void)logger;
    while (!(USART6->ISR & USART_ISR_TXE)) {}
    USART6->TDR = (uint8_t)value;
#endif
}

static void log_vprintf(log_t *logger, const char *prefix, bool newline, const char *format, va_list args)
{
    char text[128];
    int count = vsnprintf(text, sizeof(text), format, args);
    int length = count < (int)sizeof(text) ? count : (int)sizeof(text) - 1;
    for (; *prefix; ++prefix) {
        log_byte(logger, *prefix);
    }
    for (int i = 0; i < length; ++i) {
        log_byte(logger, text[i]);
    }
    if (newline && (length <= 0 || text[length - 1] != '\n')) {
        log_byte(logger, '\r');
        log_byte(logger, '\n');
    }
#ifndef UNI_CLICKER_UART_LOG
    while (!(USART6->ISR & USART_ISR_TC)) {}
#endif
}

void log_printf(log_t *logger, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    log_vprintf(logger, "", false, format, args);
    va_end(args);
}

void log_info(log_t *logger, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    log_vprintf(logger, "", true, format, args);
    va_end(args);
}

void log_error(log_t *logger, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    log_vprintf(logger, "ERROR ", true, format, args);
    va_end(args);
}

void log_warning(log_t *logger, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    log_vprintf(logger, "[WARNING]: ", true, format, args);
    va_end(args);
}

/* newlib-nano's floating-point formatter uses a small heap. */
void *_sbrk(ptrdiff_t increment)
{
    static _Alignas(8) uint8_t heap[2048];
    static ptrdiff_t used;
    if (increment < -used || increment > (ptrdiff_t)sizeof(heap) - used) {
        return (void *)-1;
    }
    void *previous = heap + used;
    used += increment;
    return previous;
}
