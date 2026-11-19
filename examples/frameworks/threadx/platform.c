#include "stm32f7xx.h"
#include "tx_api.h"

extern void *_tx_initialize_unused_memory;
extern void _tx_timer_interrupt(void);

void _tx_initialize_low_level(void)
{
    __disable_irq();
    _tx_initialize_unused_memory = 0;
    SysTick->LOAD = 16000000U / TX_TIMER_TICKS_PER_SECOND - 1;
    SysTick->VAL = 0;
    NVIC_SetPriority(SVCall_IRQn, 15);
    NVIC_SetPriority(PendSV_IRQn, 15);
    NVIC_SetPriority(SysTick_IRQn, 4);
    SysTick->CTRL = SysTick_CTRL_CLKSOURCE_Msk | SysTick_CTRL_ENABLE_Msk |
                    SysTick_CTRL_TICKINT_Msk;
}

void SysTick_Handler(void)
{
    _tx_timer_interrupt();
}
