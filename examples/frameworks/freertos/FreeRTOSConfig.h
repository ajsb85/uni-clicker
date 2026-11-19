#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#define configCPU_CLOCK_HZ                  16000000U
#define configTICK_RATE_HZ                  1000U
#define configUSE_PREEMPTION                1
#define configUSE_IDLE_HOOK                 0
#define configUSE_TICK_HOOK                 0
#define configMAX_PRIORITIES                4
#define configMINIMAL_STACK_SIZE            128U
#define configMAX_TASK_NAME_LEN             12
#define configUSE_16_BIT_TICKS              0
#define configSUPPORT_DYNAMIC_ALLOCATION    0
#define configSUPPORT_STATIC_ALLOCATION     1
#define configKERNEL_PROVIDED_STATIC_MEMORY 1
#define configKERNEL_INTERRUPT_PRIORITY     0xF0
#define configMAX_SYSCALL_INTERRUPT_PRIORITY 0x50
#define configUSE_TIMERS                    0
#define INCLUDE_vTaskDelay                  1

#define configASSERT(ok) do { if (!(ok)) { __asm volatile ("cpsid i"); for (;;) {} } } while (0)

#define vPortSVCHandler SVC_Handler
#define xPortPendSVHandler PendSV_Handler
#define xPortSysTickHandler SysTick_Handler

#endif
