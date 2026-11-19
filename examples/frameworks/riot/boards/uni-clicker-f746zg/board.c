#include "board.h"

void board_init(void)
{
    gpio_init(LED0_PIN, GPIO_OUT);
    gpio_clear(LED0_PIN);
}
