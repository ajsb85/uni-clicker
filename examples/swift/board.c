#include "board.h"
#include "stm32f7xx.h"

enum { hsi_hz = 16000000, baud = 115200, led_pin = 7 };

volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

extern void uni_swift_main(void);

void board_init(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN | RCC_AHB1ENR_GPIODEN;
    RCC->APB2ENR |= RCC_APB2ENR_USART6EN;
    (void)RCC->AHB1ENR;
    (void)RCC->APB2ENR;

    GPIOD->BSRR = 1U << (led_pin + 16);
    GPIOD->MODER = (GPIOD->MODER & ~(3U << (2 * led_pin))) | (1U << (2 * led_pin));
    GPIOC->AFR[0] = (GPIOC->AFR[0] & ~(0xffU << 24)) | (0x88U << 24);
    GPIOC->MODER = (GPIOC->MODER & ~(0x0fU << 12)) | (0x0aU << 12);

    USART6->BRR = (hsi_hz + baud / 2) / baud;
    USART6->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
    SysTick->LOAD = hsi_hz / 1000 - 1;
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk;
}

void board_wait_ms(uint32_t milliseconds)
{
    SysTick->VAL = 0;
    for (uint32_t elapsed = 0; elapsed < milliseconds; ++elapsed) {
        while (!(SysTick->CTRL & SysTick_CTRL_COUNTFLAG_Msk)) {}
    }
}

void board_set_led(uint32_t edges)
{
    GPIOD->BSRR = (edges & 1) ? 1U << led_pin : 1U << (led_pin + 16);
    uni_heartbeat = edges;
}

void board_uart_write(const uint8_t *bytes, uint32_t length)
{
    for (uint32_t i = 0; i < length; ++i) {
        while (!(USART6->ISR & USART_ISR_TXE)) {}
        USART6->TDR = bytes[i];
    }
    while (!(USART6->ISR & USART_ISR_TC)) {}
    uni_tx_bytes += length;
}

int main(void)
{
    uni_swift_main();
    return 0;
}
