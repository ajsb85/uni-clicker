#include "uni_trace.h"

#ifdef UNI_TBAND_MICROSECOND_CLOCK
#include "stm32f7xx.h"
#endif

volatile struct {
    uint32_t length;
    uint8_t data[tband_configMETADATA_BUF_SIZE + tband_configBACKEND_SNAPSHOT_BUF_SIZE];
} uni_trace_capture;

void uni_trace_start(void)
{
    if (tband_trigger_snapshot() != 0) {
        for (;;) {}
    }
}

#ifdef UNI_TBAND_MICROSECOND_CLOCK
void uni_trace_clock_init(void)
{
    RCC->APB1ENR |= RCC_APB1ENR_TIM2EN;
    (void)RCC->APB1ENR;
    TIM2->PSC = 15; // The bench uses 16 MHz HSI with APB1 undivided.
    TIM2->ARR = UINT32_MAX;
    TIM2->EGR = TIM_EGR_UG;
    TIM2->SR = 0;
    TIM2->CR1 = TIM_CR1_CEN;
}

uint64_t uni_trace_timestamp(void)
{
    // The tband port holds PRIMASK while observing the 32-bit timer.
    static uint64_t rollover;
    static uint32_t previous;
    const uint32_t current = TIM2->CNT;
    if (current < previous) {
        rollover += UINT64_C(1) << 32;
    }
    previous = current;
    return rollover + current;
}
#else
volatile uint64_t uni_trace_ticks;

void uni_trace_tick(void)
{
    ++uni_trace_ticks;
}
#endif

bool uni_trace_stop(void)
{
    if (tband_stop_snapshot() != 0 || !tband_tracing_finished()) {
        return false;
    }

    const volatile uint8_t *metadata = tband_get_metadata_buf(0);
    const volatile uint8_t *events = tband_get_core_snapshot_buf(0);
    const size_t metadata_length = tband_get_metadata_buf_amnt(0);
    const size_t events_length = tband_get_core_snapshot_buf_amnt(0);
    for (size_t i = 0; i < metadata_length; i++) {
        uni_trace_capture.data[i] = metadata[i];
    }
    for (size_t i = 0; i < events_length; i++) {
        uni_trace_capture.data[metadata_length + i] = events[i];
    }
    uni_trace_capture.length = metadata_length + events_length;
    return true;
}
