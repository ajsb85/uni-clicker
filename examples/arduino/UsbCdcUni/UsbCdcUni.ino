#include <Arduino.h>

volatile uint32_t uni_usb_ready;

extern "C" void SystemClock_Config(void)
{
    // HIGH selects the UNI Clicker USB device role.
    __HAL_RCC_GPIOB_CLK_ENABLE();
    GPIOB->BSRR = GPIO_PIN_15;
    GPIO_InitTypeDef role = {};
    role.Pin = GPIO_PIN_15;
    role.Mode = GPIO_MODE_OUTPUT_PP;
    HAL_GPIO_Init(GPIOB, &role);

    __HAL_RCC_PWR_CLK_ENABLE();
    __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);
    RCC_OscInitTypeDef osc = {};
    osc.OscillatorType = RCC_OSCILLATORTYPE_HSE;
    osc.HSEState = RCC_HSE_ON;
    osc.PLL.PLLState = RCC_PLL_ON;
    osc.PLL.PLLSource = RCC_PLLSOURCE_HSE;
    osc.PLL.PLLM = 25;
    osc.PLL.PLLN = 384;
    osc.PLL.PLLP = RCC_PLLP_DIV4;
    osc.PLL.PLLQ = 8;
    if (HAL_RCC_OscConfig(&osc) != HAL_OK) {
        Error_Handler();
    }

    RCC_ClkInitTypeDef clk = {};
    clk.ClockType = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK |
                    RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
    clk.AHBCLKDivider = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV4;
    clk.APB2CLKDivider = RCC_HCLK_DIV2;
    if (HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_3) != HAL_OK) {
        Error_Handler();
    }

    RCC_PeriphCLKInitTypeDef usb = {};
    usb.PeriphClockSelection = RCC_PERIPHCLK_CLK48;
    usb.Clk48ClockSelection = RCC_CLK48SOURCE_PLL;
    if (HAL_RCCEx_PeriphCLKConfig(&usb) != HAL_OK) {
        Error_Handler();
    }
}

void setup()
{
    pinMode(PD7, OUTPUT);
    digitalWrite(PD7, LOW);
    Serial.begin(115200);
    uni_usb_ready = 1;
}

void loop()
{
    static char line[24];
    static size_t used;
    static bool invalid;
    while (Serial.available()) {
        const int byte = Serial.read();
        if (byte == '\n') {
            line[used] = '\0';
            if (!invalid && strcmp(line, "ping") == 0) {
                Serial.println("OK USB pong");
            } else if (!invalid && strcmp(line, "led on") == 0) {
                digitalWrite(PD7, HIGH);
                Serial.println("OK led on");
            } else if (!invalid && strcmp(line, "led off") == 0) {
                digitalWrite(PD7, LOW);
                Serial.println("OK led off");
            } else {
                Serial.println("ERR command");
            }
            used = 0;
            invalid = false;
        } else if (byte != '\r') {
            if (byte < 0x20 || byte > 0x7e || used == sizeof(line) - 1) {
                invalid = true;
            } else if (!invalid) {
                line[used++] = byte;
            }
        }
    }
}
