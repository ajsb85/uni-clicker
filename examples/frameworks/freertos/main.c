#include "FreeRTOS.h"
#include "task.h"
#include "board.h"

#ifdef UNI_TBAND_TRACE
#include "queue.h"
#include "uni_trace.h"

static StaticQueue_t heartbeat_queue_state;
static uint8_t heartbeat_queue_storage[sizeof(uint32_t)];
static QueueHandle_t heartbeat_queue;
static StaticTask_t receiver_task;
static StackType_t receiver_stack[256];

void vApplicationTickHook(void)
{
    uni_trace_tick();
}

static void receive_heartbeat(void *argument)
{
    (void)argument;
    uint32_t value;
    for (;;) {
        configASSERT(xQueueReceive(heartbeat_queue, &value, portMAX_DELAY) == pdTRUE);
        tband_valmarker(0, value);
    }
}

static void trace_edge(uint32_t value)
{
    configASSERT(xQueueSend(heartbeat_queue, &value, 0) == pdTRUE);
}
#endif

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
#ifdef UNI_TBAND_TRACE
        trace_edge(1);
#endif
        vTaskDelay(pdMS_TO_TICKS(500));
        uni_tick_led();
#ifdef UNI_TBAND_TRACE
        trace_edge(2);
#endif
        uni_write_banner(banner);
#ifdef UNI_TBAND_TRACE
        uni_trace_stop();
        for (;;) {
            vTaskDelay(portMAX_DELAY);
        }
#endif
    }
}

int main(void)
{
    uni_board_init();
#ifdef UNI_TBAND_TRACE
    tband_gather_system_metadata();
    tband_valmarker_name(0, "Received heartbeat");
    uni_trace_start();
    heartbeat_queue = xQueueCreateStatic(1, sizeof(uint32_t), heartbeat_queue_storage, &heartbeat_queue_state);
    configASSERT(heartbeat_queue != NULL);
    tband_freertos_queue_name(heartbeat_queue, "Heartbeat");
    configASSERT(xTaskCreateStatic(receive_heartbeat, "receiver", 256, NULL, 2, receiver_stack, &receiver_task));
#endif
    configASSERT(xTaskCreateStatic(greet, "hello", 256, NULL, 1, hello_stack, &hello_task));
    vTaskStartScheduler();
    for (;;) {}
}
