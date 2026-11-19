#include <Arduino.h>

extern "C" {
volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;
}

Uart boardUart(PC_7, PC_6);
constexpr char banner[] = "Hello, UNI Clicker from Arduino!\r\n";

extern "C" void SystemClock_Config(void) {
    // Keep the reset clock at 16 MHz HSI, shared with the other examples.
}

void writeBanner() {
    const size_t written = boardUart.write(
        reinterpret_cast<const uint8_t *>(banner), sizeof(banner) - 1);
    boardUart.flush();
    uni_tx_bytes = uni_tx_bytes + written;
}

void setup() {
    pinMode(PD7, OUTPUT);
    digitalWrite(PD7, LOW);
    boardUart.begin(115200, SERIAL_8N1);
    writeBanner();
}

void loop() {
    delay(500);
    const uint32_t next = uni_heartbeat + 1;
    digitalWrite(PD7, (next & 1U) ? HIGH : LOW);
    uni_heartbeat = next;
    if ((next & 1U) == 0) {
        writeBanner();
    }
}
