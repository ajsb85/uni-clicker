#include "stm32f7xx.h"
#include "hal_ll_gpio_port.h"

enum { hsi_hz = 16000000, baud = 115200 };

volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

static const char banner[] = "Hello, UNI Clicker from NECTO!\r\n";

static void configure_uart(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN;
    RCC->APB2ENR |= RCC_APB2ENR_USART6EN;
    (void)RCC->AHB1ENR;
    (void)RCC->APB2ENR;

    GPIOC->AFR[0] = (GPIOC->AFR[0] & ~(0xffU << 24)) | (0x88U << 24);
    GPIOC->MODER = (GPIOC->MODER & ~(0x0fU << 12)) | (0x0aU << 12);
    USART6->BRR = (hsi_hz + baud / 2) / baud;
    USART6->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
}

static void write_banner(void)
{
    for (unsigned i = 0; i < sizeof(banner) - 1; ++i) {
        while (!(USART6->ISR & USART_ISR_TXE)) {}
        USART6->TDR = (uint8_t)banner[i];
    }
    while (!(USART6->ISR & USART_ISR_TC)) {}
    uni_tx_bytes += sizeof(banner) - 1;
}

static void wait_ms(unsigned milliseconds)
{
    SysTick->VAL = 0;
    for (unsigned elapsed = 0; elapsed < milliseconds; ++elapsed) {
        while (!(SysTick->CTRL & SysTick_CTRL_COUNTFLAG_Msk)) {}
    }
}

int main(void)
{
    hal_ll_gpio_digital_output((uint32_t *)GPIOD_BASE, 1U << 7);
    GPIOD->BSRR = 1U << 23;
    configure_uart();

    SysTick->LOAD = hsi_hz / 1000 - 1;
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk;
    write_banner();

    for (;;) {
        wait_ms(500);
        uint32_t next = uni_heartbeat + 1;
        GPIOD->BSRR = (next & 1) ? 1U << 7 : 1U << 23;
        uni_heartbeat = next;
        if ((next & 1) == 0) {
            write_banner();
        }
    }
}
