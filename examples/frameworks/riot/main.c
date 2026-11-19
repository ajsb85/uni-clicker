#include <stdio.h>

#include "board.h"
#include "ztimer.h"

int main(void)
{
    for (;;) {
        puts("Hello, UNI Clicker from RIOT!");
        ztimer_sleep(ZTIMER_MSEC, 500);
        LED0_TOGGLE;
        ztimer_sleep(ZTIMER_MSEC, 500);
        LED0_TOGGLE;
    }
}
