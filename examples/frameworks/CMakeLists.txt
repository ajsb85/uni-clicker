cmake_minimum_required(VERSION 3.19)
project(uni_clicker_rtos LANGUAGES C ASM)

set(FRAMEWORK "" CACHE STRING "freertos, freertos-console or threadx")
set(KERNEL_DIR "" CACHE PATH "Upstream kernel source directory")
set(STM32CUBE_F7 "" CACHE PATH "STM32CubeF7 root")
set(TONBAND_ROOT "" CACHE PATH "Tonbandgeraet sources for the FreeRTOS trace build")
set(cmsis "${STM32CUBE_F7}/Drivers/CMSIS")
set(device "${cmsis}/Device/ST/STM32F7xx")
set(shared "${CMAKE_CURRENT_SOURCE_DIR}/../../firmware")
set(cpu -mcpu=cortex-m7 -mthumb -mfpu=fpv5-sp-d16 -mfloat-abi=hard)

add_executable(hello
    common/board.c
    "${device}/Source/Templates/gcc/startup_stm32f746xx.s"
    "${device}/Source/Templates/system_stm32f7xx.c"
    "${shared}/startup_support.c"
)
set_target_properties(hello PROPERTIES SUFFIX ".elf" LINK_DEPENDS "${shared}/stm32f746.ld")
target_include_directories(hello PRIVATE common "${cmsis}/Include" "${device}/Include")
target_compile_definitions(hello PRIVATE STM32F746xx)
target_compile_options(hello PRIVATE ${cpu} -Og -g3 -ffunction-sections -fdata-sections)
target_link_options(hello PRIVATE ${cpu} -nostartfiles --specs=nano.specs --specs=nosys.specs
    "-T${shared}/stm32f746.ld" "-Wl,--gc-sections,-z,noexecstack,-Map,hello.map")

if(FRAMEWORK STREQUAL "freertos" OR FRAMEWORK STREQUAL "freertos-console")
    set(port "${KERNEL_DIR}/portable/GCC/ARM_CM7/r0p1")
    target_sources(hello PRIVATE "${FRAMEWORK}/main.c" "${KERNEL_DIR}/tasks.c"
        "${KERNEL_DIR}/list.c" "${KERNEL_DIR}/queue.c" "${port}/port.c")
    target_include_directories(hello PRIVATE freertos "${KERNEL_DIR}/include" "${port}")
    if(TONBAND_ROOT)
        target_compile_definitions(hello PRIVATE UNI_TBAND_TRACE UNI_TBAND_FREERTOS)
        if(FRAMEWORK STREQUAL "freertos-console")
            target_compile_definitions(hello PRIVATE UNI_TBAND_MICROSECOND_CLOCK)
        endif()
        target_include_directories(hello PRIVATE ../trace "${TONBAND_ROOT}/tband/inc")
        target_sources(hello PRIVATE ../trace/uni_trace.c
            "${TONBAND_ROOT}/tband/src/tband.c"
            "${TONBAND_ROOT}/tband/src/tband_backend.c"
            "${TONBAND_ROOT}/tband/src/tband_freertos.c")
    endif()
elseif(FRAMEWORK STREQUAL "threadx")
    set(port "${KERNEL_DIR}/ports/cortex_m7/gnu")
    file(GLOB kernel CONFIGURE_DEPENDS "${KERNEL_DIR}/common/src/*.c" "${port}/src/*.S")
    target_sources(hello PRIVATE threadx/main.c threadx/platform.c ${kernel})
    target_include_directories(hello PRIVATE "${KERNEL_DIR}/common/inc" "${port}/inc")
    target_compile_definitions(hello PRIVATE TX_TIMER_TICKS_PER_SECOND=1000)
else()
    message(FATAL_ERROR "Set FRAMEWORK to freertos, freertos-console or threadx")
endif()
