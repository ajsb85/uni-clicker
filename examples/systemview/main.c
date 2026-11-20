#include "SEGGER_RTT.h"
#include "SEGGER_SYSVIEW.h"
#include "board.h"
#include "stm32f7xx.h"

static volatile uint32_t ticks;

void SysTick_Handler(void)
{
    ++ticks;
}

uint32_t uni_systemview_timestamp(void)
{
    return ticks;
}

static void describe(void)
{
    SEGGER_SYSVIEW_SendSysDesc("N=UNI Clicker,D=STM32F746ZG,O=Bare metal");
    SEGGER_SYSVIEW_NameMarker(0, "PD7 heartbeat");
}

int main(void)
{
    uni_board_init();
    SysTick_Config(SystemCoreClock / 1000);
    SEGGER_SYSVIEW_Init(1000, SystemCoreClock, 0, describe);
    SEGGER_SYSVIEW_SetRAMBase(0x20000000);
    SEGGER_RTT_WriteString(0, "UNI Clicker RTT ready\n");
    uni_write_banner("Hello, UNI Clicker from SystemView!\r\n");

    uint32_t last_heartbeat = ticks;
    for (;;) {
        // IsStarted also handles the host's RTT start and stop commands.
        if (!SEGGER_SYSVIEW_IsStarted()) {
            last_heartbeat = ticks;
        } else if (ticks - last_heartbeat >= 250) {
            last_heartbeat += 250;
            uni_tick_led();
            SEGGER_SYSVIEW_Mark(0);
        }
        __WFI();
    }
}
