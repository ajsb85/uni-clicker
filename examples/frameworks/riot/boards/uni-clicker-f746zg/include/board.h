#pragma once

#include "periph/gpio.h"

#define LED0_PIN GPIO_PIN(PORT_D, 7)
#define LED0_ON gpio_set(LED0_PIN)
#define LED0_OFF gpio_clear(LED0_PIN)
#define LED0_TOGGLE gpio_toggle(LED0_PIN)
