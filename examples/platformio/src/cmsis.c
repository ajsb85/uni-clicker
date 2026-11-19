#include "../../frameworks/common/board.c"

int main(void)
{
    uni_board_init();
    SysTick->LOAD = 16000U - 1U;
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk;

    const char *banner = "Hello, UNI Clicker from CMSIS!\r\n";
    uni_write_banner(banner);
    for (;;) {
        SysTick->VAL = 0;
        for (unsigned elapsed = 0; elapsed < 500; ++elapsed) {
            while (!(SysTick->CTRL & SysTick_CTRL_COUNTFLAG_Msk)) {}
        }
        uni_tick_led();
        if ((uni_heartbeat & 1U) == 0) {
            uni_write_banner(banner);
        }
    }
}
