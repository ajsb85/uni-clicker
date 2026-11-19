#include "FreeRTOS.h"
#include "task.h"
#include "board.h"

static StaticTask_t hello_task;
static StackType_t hello_stack[256];
static const char banner[] = "Hello, UNI Clicker from FreeRTOS!\r\n";

static void greet(void *argument)
{
    (void)argument;
    uni_write_banner(banner);
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(500));
        uni_tick_led();
        vTaskDelay(pdMS_TO_TICKS(500));
        uni_tick_led();
        uni_write_banner(banner);
    }
}

int main(void)
{
    uni_board_init();
    configASSERT(xTaskCreateStatic(greet, "hello", 256, NULL, 1, hello_stack, &hello_task));
    vTaskStartScheduler();
    for (;;) {}
}
