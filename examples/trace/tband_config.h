#ifndef UNI_TBAND_CONFIG_H
#define UNI_TBAND_CONFIG_H

#define tband_configENABLE 1
#define tband_configISR_TRACE_ENABLE 0
#define tband_configUSE_BACKEND_SNAPSHOT 1
#ifdef UNI_TBAND_FREERTOS
#define tband_configFREERTOS_TRACE_ENABLE 1
#define tband_configMETADATA_BUF_SIZE 512
#ifdef UNI_TBAND_MICROSECOND_CLOCK
#define tband_configBACKEND_SNAPSHOT_BUF_SIZE 8192
#else
#define tband_configBACKEND_SNAPSHOT_BUF_SIZE 4096
#endif
#else
#define tband_configBACKEND_SNAPSHOT_BUF_SIZE 512
#endif

#endif
