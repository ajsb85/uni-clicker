#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/kernel.h>

static const struct gpio_dt_spec led = GPIO_DT_SPEC_GET(DT_NODELABEL(uni_led), gpios);
static const struct device *const uart = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));
volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

static void write_banner(void)
{
    static const char banner[] = "Hello, UNI Clicker from Zephyr!\r\n";

    for (size_t i = 0; i < sizeof(banner) - 1; ++i) {
        uart_poll_out(uart, banner[i]);
    }
    uni_tx_bytes += sizeof(banner) - 1;
}

int main(void)
{
    if (!device_is_ready(uart) || !gpio_is_ready_dt(&led) ||
        gpio_pin_configure_dt(&led, GPIO_OUTPUT_INACTIVE) != 0) {
        return 1;
    }

    write_banner();
    for (;;) {
        k_msleep(500);
        gpio_pin_set_dt(&led, 1);
        ++uni_heartbeat;
        k_msleep(500);
        gpio_pin_set_dt(&led, 0);
        ++uni_heartbeat;
        write_banner();
    }
}
