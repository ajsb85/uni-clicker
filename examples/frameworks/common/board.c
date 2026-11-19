#include "board.h"
#include "stm32f7xx.h"

volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

void uni_board_init(void)
{
    SCB->VTOR = FLASH_BASE;
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN | RCC_AHB1ENR_GPIODEN;
    RCC->APB2ENR |= RCC_APB2ENR_USART6EN;
    (void)RCC->AHB1ENR;
    (void)RCC->APB2ENR;

    GPIOD->BSRR = 1U << 23;
    GPIOD->MODER = (GPIOD->MODER & ~(3U << 14)) | (1U << 14);
    GPIOC->AFR[0] = (GPIOC->AFR[0] & ~(0xffU << 24)) | (0x88U << 24);
    GPIOC->MODER = (GPIOC->MODER & ~(0x0fU << 12)) | (0x0aU << 12);
    USART6->BRR = 139;
    USART6->CR1 = USART_CR1_TE | USART_CR1_RE | USART_CR1_UE;
}

void uni_write_banner(const char *message)
{
    uint32_t length = 0;
    for (; message[length]; ++length) {
        while (!(USART6->ISR & USART_ISR_TXE)) {}
        USART6->TDR = (uint8_t)message[length];
    }
    while (!(USART6->ISR & USART_ISR_TC)) {}
    uni_tx_bytes += length;
}

void uni_tick_led(void)
{
    uint32_t next = uni_heartbeat + 1;
    GPIOD->BSRR = (next & 1) ? (1U << 7) : (1U << 23);
    uni_heartbeat = next;
}
