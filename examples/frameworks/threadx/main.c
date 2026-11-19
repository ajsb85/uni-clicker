#include "tx_api.h"
#include "board.h"

static TX_THREAD hello_thread;
static ULONG hello_stack[256];
static const char banner[] = "Hello, UNI Clicker from ThreadX!\r\n";

static void greet(ULONG argument)
{
    (void)argument;
    uni_write_banner(banner);
    for (;;) {
        tx_thread_sleep(TX_TIMER_TICKS_PER_SECOND / 2);
        uni_tick_led();
        tx_thread_sleep(TX_TIMER_TICKS_PER_SECOND / 2);
        uni_tick_led();
        uni_write_banner(banner);
    }
}

void tx_application_define(void *first_unused_memory)
{
    (void)first_unused_memory;
    UINT result = tx_thread_create(&hello_thread, "hello", greet, 0, hello_stack,
                                   sizeof(hello_stack), 1, 1, TX_NO_TIME_SLICE, TX_AUTO_START);
    if (result != TX_SUCCESS) {
        for (;;) {}
    }
}

int main(void)
{
    uni_board_init();
    tx_kernel_enter();
    for (;;) {}
}
