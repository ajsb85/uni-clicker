#include <stdio.h>
#include <stdint.h>

#include "board.h"
#include "ztimer.h"

volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

static void write_banner(void)
{
    static const char banner[] = "Hello, UNI Clicker from RIOT!\r\n";
    fputs(banner, stdout);
    fflush(stdout);
    uni_tx_bytes += sizeof(banner) - 1;
}

int main(void)
{
    write_banner();
    for (;;) {
        ztimer_sleep(ZTIMER_MSEC, 500);
        LED0_TOGGLE;
        ++uni_heartbeat;
        ztimer_sleep(ZTIMER_MSEC, 500);
        LED0_TOGGLE;
        ++uni_heartbeat;
        write_banner();
    }
}
