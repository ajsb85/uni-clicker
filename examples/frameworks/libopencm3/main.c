#include <libopencm3/cm3/systick.h>
#include <libopencm3/stm32/gpio.h>
#include <libopencm3/stm32/rcc.h>
#include <libopencm3/stm32/usart.h>

volatile uint32_t uni_heartbeat;
volatile uint32_t uni_tx_bytes;

static void write_banner(void)
{
    static const char banner[] = "Hello, UNI Clicker from libopencm3!\r\n";
    for (unsigned i = 0; i < sizeof(banner) - 1; ++i) {
        usart_send_blocking(USART6, banner[i]);
    }
    usart_wait_send_ready(USART6);
    while (!(USART_ISR(USART6) & USART_ISR_TC)) {}
    uni_tx_bytes += sizeof(banner) - 1;
}

int main(void)
{
    rcc_periph_clock_enable(RCC_GPIOC);
    rcc_periph_clock_enable(RCC_GPIOD);
    rcc_periph_clock_enable(RCC_USART6);
    gpio_mode_setup(GPIOD, GPIO_MODE_OUTPUT, GPIO_PUPD_NONE, GPIO7);
    gpio_clear(GPIOD, GPIO7);
    gpio_mode_setup(GPIOC, GPIO_MODE_AF, GPIO_PUPD_PULLUP, GPIO6 | GPIO7);
    gpio_set_af(GPIOC, GPIO_AF8, GPIO6 | GPIO7);
    usart_set_baudrate(USART6, 115200);
    usart_set_mode(USART6, USART_MODE_TX_RX);
    usart_enable(USART6);

    systick_set_clocksource(STK_CSR_CLKSOURCE_AHB);
    systick_set_reload(15999);
    systick_counter_enable();
    write_banner();
    for (;;) {
        systick_clear();
        for (unsigned elapsed = 0; elapsed < 500; ++elapsed) {
            while (!systick_get_countflag()) {}
        }
        gpio_toggle(GPIOD, GPIO7);
        if ((++uni_heartbeat & 1U) == 0) {
            write_banner();
        }
    }
}
