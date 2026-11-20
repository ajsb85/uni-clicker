#ifndef UNI_CLICKER_NECTO_SONICLIB_EXTI_H
#define UNI_CLICKER_NECTO_SONICLIB_EXTI_H

/* SonicLib's BSP holds sensor_group_ptr and includes this at its MCU selection. */
void EXTI3_IRQHandler(void)
{
    if (EXTI->PR & EXTI_PR_PR3) {
        EXTI->PR = EXTI_PR_PR3;
        ch_interrupt(sensor_group_ptr, 0);
    }
}

void chbsp_ext_int_enable(void)
{
    RCC->APB2ENR |= RCC_APB2ENR_SYSCFGEN;
    (void)RCC->APB2ENR;
    SYSCFG->EXTICR[0] = (SYSCFG->EXTICR[0] & ~SYSCFG_EXTICR1_EXTI3)
                        | SYSCFG_EXTICR1_EXTI3_PD;
    EXTI->RTSR &= ~EXTI_RTSR_TR3;
    EXTI->FTSR |= EXTI_FTSR_TR3;
    EXTI->PR = EXTI_PR_PR3;
    NVIC_ClearPendingIRQ(EXTI3_IRQn);
    EXTI->IMR |= EXTI_IMR_IM3;
    NVIC_EnableIRQ(EXTI3_IRQn);
}

void chbsp_ext_int_disable(void)
{
    EXTI->IMR &= ~EXTI_IMR_IM3;
    NVIC_DisableIRQ(EXTI3_IRQn);
}

#endif
