#include "mbed.h"

using namespace std::chrono_literals;

int main()
{
    mbed::DigitalOut led(PD_7, 0);
    mbed::BufferedSerial uart(PC_6, PC_7, 115200);
    constexpr char banner[] = "Hello, UNI Clicker from Mbed OS!\r\n";

    for (;;) {
        uart.write(banner, sizeof(banner) - 1);
        rtos::ThisThread::sleep_for(500ms);
        led = 1;
        rtos::ThisThread::sleep_for(500ms);
        led = 0;
    }
}
