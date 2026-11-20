#include "stm32f7xx_hal.h"

#ifdef UNI_TBAND_TRACE
#include "uni_trace.h"
#endif

volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

static UART_HandleTypeDef uart;
static const char banner[] = "Hello, UNI Clicker from STM32Cube!\r\n";

static void require_ok(HAL_StatusTypeDef status)
{
    if (status != HAL_OK) {
        __BKPT(0);
        for (;;) {}
    }
}

static void write_banner(void)
{
    require_ok(HAL_UART_Transmit(&uart, (const uint8_t *)banner, sizeof(banner) - 1, 100));
    uni_tx_bytes += sizeof(banner) - 1;
}

void SysTick_Handler(void)
{
    HAL_IncTick();
#ifdef UNI_TBAND_TRACE
    uni_trace_tick();
#endif
}

int main(void)
{
    require_ok(HAL_Init());
    __HAL_RCC_GPIOD_CLK_ENABLE();
    __HAL_RCC_GPIOC_CLK_ENABLE();
    __HAL_RCC_USART6_CLK_ENABLE();

    GPIO_InitTypeDef led = {
        .Pin = GPIO_PIN_7,
        .Mode = GPIO_MODE_OUTPUT_PP,
    };
    HAL_GPIO_Init(GPIOD, &led);
    HAL_GPIO_WritePin(GPIOD, GPIO_PIN_7, GPIO_PIN_RESET);

    GPIO_InitTypeDef serial = {
        .Pin = GPIO_PIN_6 | GPIO_PIN_7,
        .Mode = GPIO_MODE_AF_PP,
        .Pull = GPIO_PULLUP,
        .Speed = GPIO_SPEED_FREQ_HIGH,
        .Alternate = GPIO_AF8_USART6,
    };
    HAL_GPIO_Init(GPIOC, &serial);

    uart.Instance = USART6;
    uart.Init = (UART_InitTypeDef){
        .BaudRate = 115200,
        .WordLength = UART_WORDLENGTH_8B,
        .StopBits = UART_STOPBITS_1,
        .Parity = UART_PARITY_NONE,
        .Mode = UART_MODE_TX_RX,
        .HwFlowCtl = UART_HWCONTROL_NONE,
        .OverSampling = UART_OVERSAMPLING_16,
    };
    require_ok(HAL_UART_Init(&uart));

#ifdef UNI_TBAND_TRACE
    tband_gather_system_metadata();
    tband_evtmarker_name(0, "LED C wait");
    tband_valmarker_name(0, "Heartbeat");
    uni_trace_start();
#endif
    write_banner();
    for (;;) {
#ifdef UNI_TBAND_TRACE
        tband_evtmarker_begin(0, "500 ms delay");
#endif
        HAL_Delay(500);
#ifdef UNI_TBAND_TRACE
        tband_evtmarker_end(0);
#endif
        HAL_GPIO_TogglePin(GPIOD, GPIO_PIN_7);
        ++uni_heartbeat;
#ifdef UNI_TBAND_TRACE
        tband_valmarker(0, uni_heartbeat);
#endif
        if ((uni_heartbeat & 1U) == 0) {
            write_banner();
#ifdef UNI_TBAND_TRACE
            if (uni_heartbeat == 2) {
                uni_trace_stop();
                for (;;) {
                    __WFI();
                }
            }
#endif
        }
    }
}
