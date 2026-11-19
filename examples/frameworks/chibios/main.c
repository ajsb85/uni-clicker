#include "ch.h"
#include "hal.h"

int main(void)
{
    static const uint8_t banner[] = "Hello, UNI Clicker from ChibiOS!\r\n";
    const ioline_t led = PAL_LINE(GPIOD, 7);
    const SerialConfig serial = {115200, 0, 0, 0};

    halInit();
    chSysInit();
    palSetLineMode(led, PAL_MODE_OUTPUT_PUSHPULL);
    palClearLine(led);
    palSetLineMode(PAL_LINE(GPIOC, 6), PAL_MODE_ALTERNATE(8));
    palSetLineMode(PAL_LINE(GPIOC, 7), PAL_MODE_ALTERNATE(8) | PAL_STM32_PUPDR_PULLUP);
    sdStart(&SD6, &serial);

    for (;;) {
        chnWrite(&SD6, banner, sizeof(banner) - 1);
        chThdSleepMilliseconds(500);
        palSetLine(led);
        chThdSleepMilliseconds(500);
        palClearLine(led);
    }
}
