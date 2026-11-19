#include "ch.h"
#include "hal.h"

static const uint8_t banner[] = "Hello, UNI Clicker from ChibiOS!\r\n";
static event_listener_t transmit_end;
volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

static void write_banner(void)
{
    const size_t written = chnWrite(&SD6, banner, sizeof(banner) - 1);
    chEvtWaitAny(EVENT_MASK(0));
    chEvtGetAndClearFlags(&transmit_end);
    uni_tx_bytes += written;
}

int main(void)
{
    const ioline_t led = PAL_LINE(GPIOD, 7);
    const SerialConfig serial = {115200, 0, 0, 0};

    halInit();
    chSysInit();
    palSetLineMode(led, PAL_MODE_OUTPUT_PUSHPULL);
    palClearLine(led);
    palSetLineMode(PAL_LINE(GPIOC, 6), PAL_MODE_ALTERNATE(8));
    palSetLineMode(PAL_LINE(GPIOC, 7), PAL_MODE_ALTERNATE(8) | PAL_STM32_PUPDR_PULLUP);
    sdStart(&SD6, &serial);
    chEvtRegisterMaskWithFlags(chnGetEventSource(&SD6), &transmit_end, EVENT_MASK(0), CHN_TRANSMISSION_END);

    write_banner();
    for (;;) {
        chThdSleepMilliseconds(500);
        palSetLine(led);
        ++uni_heartbeat;
        chThdSleepMilliseconds(500);
        palClearLine(led);
        ++uni_heartbeat;
        write_banner();
    }
}
