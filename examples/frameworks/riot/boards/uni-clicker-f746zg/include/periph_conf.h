#pragma once

#include "periph_cpu.h"
#include "clk/f2f4f7/cfg_clock_default.h"
#include "cfg_timer_tim2.h"

static const uart_conf_t uart_config[] = {
    {
        .dev = USART6,
        .rcc_mask = RCC_APB2ENR_USART6EN,
        .rx_pin = GPIO_PIN(PORT_C, 7),
        .tx_pin = GPIO_PIN(PORT_C, 6),
        .rx_af = GPIO_AF8,
        .tx_af = GPIO_AF8,
        .bus = APB2,
        .irqn = USART6_IRQn,
    },
};

#define UART_0_ISR isr_usart6
#define UART_NUMOF ARRAY_SIZE(uart_config)
