#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"
#include "board.h"
#include "stm32f7xx.h"

#include <stdbool.h>
#include <string.h>

#ifdef UNI_TBAND_TRACE
#include "uni_trace.h"
#endif

enum { QUEUE_DEPTH = 4, LINE_CAPACITY = 24, ISR_RX_BUDGET = 64 };

typedef struct {
    char text[LINE_CAPACITY];
    bool malformed;
#ifdef UNI_TBAND_TRACE
    uint32_t sequence;
#endif
} CommandLine;

static StaticQueue_t queue_state;
static uint8_t queue_storage[QUEUE_DEPTH * sizeof(CommandLine)];
static QueueHandle_t lines;
static StaticTask_t console_task;
static StackType_t console_stack[512];
static CommandLine input;
static size_t used;
static bool saw_cr;

volatile uint32_t uni_console_ready;
volatile uint32_t uni_rx_dropped;
volatile uint32_t uni_rx_errors;

static void receive_byte(uint8_t byte, BaseType_t *wake)
{
    if (byte == '\n') {
        input.text[used] = '\0';
#ifdef UNI_TBAND_TRACE
        ++input.sequence;
#endif
        if (xQueueSendFromISR(lines, &input, wake) != pdPASS) {
            ++uni_rx_dropped;
        }
#ifdef UNI_TBAND_TRACE
        else {
            tband_valmarker(0, input.sequence);
        }
#endif
        input.malformed = false;
        saw_cr = false;
        used = 0;
    } else if (!saw_cr && byte == '\r') {
        saw_cr = true;
    } else if (saw_cr || byte < 0x20 || byte > 0x7e || used == LINE_CAPACITY - 1) {
        input.malformed = true;
    } else if (!input.malformed) {
        input.text[used++] = (char)byte;
    }
}

void USART6_IRQHandler(void)
{
    BaseType_t wake = pdFALSE;
    for (unsigned i = 0; i < ISR_RX_BUDGET; ++i) {
        const uint32_t status = USART6->ISR;
        const uint32_t errors = status & (USART_ISR_ORE | USART_ISR_FE | USART_ISR_NE | USART_ISR_PE);
        if (errors) {
            // USART6 uses the same bit positions for these status and clear flags.
            USART6->ICR = errors;
            ++uni_rx_errors;
            input.malformed = true;
        }
        if (!(status & USART_ISR_RXNE)) {
            break;
        }
        receive_byte((uint8_t)USART6->RDR, &wake);
    }
    portYIELD_FROM_ISR(wake);
}

static void write_count(uint32_t count)
{
    char digits[11];
    char *digit = &digits[sizeof(digits) - 1];
    *digit = '\0';
    do {
        *--digit = '0' + count % 10;
        count /= 10;
    } while (count);
    uni_write_banner(digit);
}

static void write_status(void)
{
    uni_write_banner(GPIOD->ODR & (1U << 7) ? "OK led=on dropped=" : "OK led=off dropped=");
    write_count(uni_rx_dropped);
    uni_write_banner(" errors=");
    write_count(uni_rx_errors);
    uni_write_banner("\r\n");
}

static void reply(const CommandLine *line)
{
    if (line->malformed || line->text[0] == '\0') {
        uni_write_banner("ERR malformed\r\n");
    } else if (strcmp(line->text, "ping") == 0) {
        uni_write_banner("OK pong\r\n");
    } else if (strcmp(line->text, "led on") == 0) {
        GPIOD->BSRR = 1U << 7;
        uni_write_banner("OK led on\r\n");
    } else if (strcmp(line->text, "led off") == 0) {
        GPIOD->BSRR = 1U << 23;
        uni_write_banner("OK led off\r\n");
    } else if (strcmp(line->text, "status") == 0) {
        write_status();
#ifdef UNI_TBAND_TRACE
    } else if (strcmp(line->text, "trace") == 0) {
        uni_write_banner(uni_trace_stop() ? "OK trace\r\n" : "ERR trace unavailable\r\n");
#endif
    } else {
        uni_write_banner("ERR unknown\r\n");
    }
}

static void command_task(void *argument)
{
    (void)argument;
    NVIC_SetPriority(USART6_IRQn, configMAX_SYSCALL_INTERRUPT_PRIORITY >> (8 - __NVIC_PRIO_BITS));
    NVIC_ClearPendingIRQ(USART6_IRQn);
    USART6->CR3 |= USART_CR3_EIE;
    USART6->CR1 |= USART_CR1_RXNEIE;
    NVIC_EnableIRQ(USART6_IRQn);
    uni_write_banner("READY 115200 8N1\r\n");
    uni_console_ready = 1;

    CommandLine line;
    for (;;) {
        if (xQueueReceive(lines, &line, portMAX_DELAY) == pdPASS) {
#ifdef UNI_TBAND_TRACE
            tband_valmarker(1, line.sequence);
#endif
            reply(&line);
        }
    }
}

int main(void)
{
    uni_board_init();
#ifdef UNI_TBAND_TRACE
    uni_trace_clock_init();
    tband_gather_system_metadata();
    tband_valmarker_name(0, "USART6 enqueued");
    tband_valmarker_name(1, "Command dequeued");
    uni_trace_start();
#endif
    lines = xQueueCreateStatic(QUEUE_DEPTH, sizeof(CommandLine), queue_storage, &queue_state);
    configASSERT(lines != NULL);
#ifdef UNI_TBAND_TRACE
    tband_freertos_queue_name(lines, "USART6 RX");
#endif
    configASSERT(xTaskCreateStatic(command_task, "console", 512, NULL, 2, console_stack, &console_task));
    vTaskStartScheduler();
    for (;;) {}
}
