#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

static const struct gpio_dt_spec led = GPIO_DT_SPEC_GET(DT_NODELABEL(uni_led), gpios);

int main(void)
{
    if (!gpio_is_ready_dt(&led) || gpio_pin_configure_dt(&led, GPIO_OUTPUT_INACTIVE) != 0) {
        return 1;
    }

    for (;;) {
        printk("Hello, UNI Clicker from Zephyr!\n");
        k_msleep(500);
        gpio_pin_set_dt(&led, 1);
        k_msleep(500);
        gpio_pin_set_dt(&led, 0);
    }
}
