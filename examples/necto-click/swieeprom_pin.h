#ifndef UNI_CLICKER_NECTO_SWIEEPROM_PIN_H
#define UNI_CLICKER_NECTO_SWIEEPROM_PIN_H

#include "stm32f7xx.h"

/* SIO connects to the MikroBUS 1 PWM pin. The Click pulls the line high. */
#define SIO_MODE GPIO_MODER_MODER12
#define SIO_OUTPUT GPIO_MODER_MODER12_0
#define SIO_PIN (1u << 12)

void pin_init(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIODEN;
    (void)RCC->AHB1ENR;
    GPIOD->MODER &= ~SIO_MODE;
    GPIOD->OTYPER |= SIO_PIN;
}

void pin_low(void)
{
    GPIOD->BSRR = SIO_PIN << 16;
    GPIOD->MODER = (GPIOD->MODER & ~SIO_MODE) | SIO_OUTPUT;
}

void pin_release(void)
{
    GPIOD->MODER &= ~SIO_MODE;
}

uint8_t pin_get(void)
{
    pin_release();
    return (GPIOD->IDR & SIO_PIN) != 0;
}

#endif
