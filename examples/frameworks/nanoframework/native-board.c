#include "hal.h"

void __early_init(void)
{
    stm32_clock_init();
}

void boardInit(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOCEN | RCC_AHB1ENR_GPIODEN;
    (void)RCC->AHB1ENR;
    palSetLineMode(PAL_LINE(GPIOC, 6), PAL_MODE_ALTERNATE(8));
    palSetLineMode(PAL_LINE(GPIOC, 7), PAL_MODE_ALTERNATE(8) | PAL_STM32_PUPDR_PULLUP);
    palClearLine(LINE_LED1);
    palSetLineMode(LINE_LED1, PAL_MODE_OUTPUT_PUSHPULL);
}
