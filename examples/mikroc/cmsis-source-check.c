#include "stm32f7xx.h"

/* These lvalues match the legacy compiler's STM32F746ZG SFR definitions. */
#define RCC_AHB1ENR (RCC->AHB1ENR)
#define RCC_APB2ENR (RCC->APB2ENR)
#define GPIOD_BSRR (GPIOD->BSRR)
#define GPIOD_MODER (GPIOD->MODER)
#define GPIOC_AFRL (GPIOC->AFR[0])
#define GPIOC_MODER (GPIOC->MODER)
#define USART6_BRR (USART6->BRR)
#define USART6_CR1 (USART6->CR1)
#define USART6_ISR (USART6->ISR)
#define USART6_TDR (USART6->TDR)

#define main mikroc_source_entry
#include "hello.c"
#undef main

int main(void)
{
    mikroc_source_entry();
    return 0;
}
