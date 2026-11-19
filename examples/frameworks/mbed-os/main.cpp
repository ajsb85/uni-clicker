#include "mbed.h"

using namespace std::chrono_literals;

extern "C" {
volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;
}

int main()
{
    mbed::DigitalOut led(PD_7, 0);
    mbed::BufferedSerial uart(PC_6, PC_7, 115200);
    constexpr char banner[] = "Hello, UNI Clicker from Mbed OS!\r\n";

    for (;;) {
        const auto written = uart.write(banner, sizeof(banner) - 1);
        if (written > 0) {
            uni_tx_bytes += static_cast<uint32_t>(written);
        }
        rtos::ThisThread::sleep_for(500ms);
        led = 1;
        ++uni_heartbeat;
        rtos::ThisThread::sleep_for(500ms);
        led = 0;
        ++uni_heartbeat;
    }
}
