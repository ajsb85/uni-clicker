#include "uni_trace.h"

volatile uint64_t uni_trace_ticks;
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

void uni_trace_tick(void)
{
    ++uni_trace_ticks;
}

void uni_trace_stop(void)
{
    if (tband_stop_snapshot() != 0 || !tband_tracing_finished()) {
        return;
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
}
