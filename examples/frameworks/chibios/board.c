#include "hal.h"

void __early_init(void)
{
    stm32_clock_init();
}

void boardInit(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN | RCC_AHB1ENR_GPIODEN;
    (void)RCC->AHB1ENR;
}
