cmake_minimum_required(VERSION 3.19)
project(uni_clicker_necto LANGUAGES C ASM)

set(STM32CUBE_F7 "" CACHE PATH "STM32CubeF7 root")
set(NECTO_SDK_ROOT "" CACHE PATH "NECTO mikroSDK_v2/src root")

set(cmsis "${STM32CUBE_F7}/Drivers/CMSIS")
set(device "${cmsis}/Device/ST/STM32F7xx")
set(mikroe "${NECTO_SDK_ROOT}/targets/arm/mikroe")
set(stm32 "${mikroe}/stm32")
set(common "${mikroe}/common/include")
set(shared "${CMAKE_CURRENT_SOURCE_DIR}/../../firmware")
set(cpu -mcpu=cortex-m7 -mthumb -mfloat-abi=soft)

if(NOT EXISTS "${stm32}/src/gpio/implementation_1/hal_ll_gpio_port.c")
    message(FATAL_ERROR "Set NECTO_SDK_ROOT to the installed mikroSDK_v2/src tree")
endif()
if(NOT EXISTS "${device}/Include/stm32f746xx.h")
    message(FATAL_ERROR "Set STM32CUBE_F7 to the SDK tree with its CMSIS Device populated")
endif()

set(MACRO_LIST2 "#define FLATTEN_ME_LEVEL FLATTEN_ME_LEVEL_NONE\n")
configure_file("${NECTO_SDK_ROOT}/cmake/InstallHeadersFlatten.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/flatten_me.h" @ONLY)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/core_header.h" "#include <stm32f7xx.h>\n")

add_executable(hello
    main.c
    "${stm32}/src/gpio/implementation_1/hal_ll_gpio_port.c"
    "${device}/Source/Templates/gcc/startup_stm32f746xx.s"
    "${device}/Source/Templates/system_stm32f7xx.c"
    "${shared}/startup_support.c"
)
set_target_properties(hello PROPERTIES SUFFIX ".elf" LINK_DEPENDS "${shared}/stm32f746.ld")
target_include_directories(hello PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${cmsis}/Include" "${device}/Include"
    "${stm32}/include" "${stm32}/include/gpio"
    "${common}" "${common}/mcu_definitions/STM32/STM32F746ZGTx"
    "${common}/mcu_reg_addresses/STM32/STM32F746ZG"
)
target_compile_definitions(hello PRIVATE STM32F746xx STM32F7xx __hal_ll_gpio_subset_1__)
target_compile_options(hello PRIVATE ${cpu} -g3 -Og -ffunction-sections -fdata-sections)
target_link_options(hello PRIVATE ${cpu} -nostdlib
    "-T${shared}/stm32f746.ld" "-Wl,--gc-sections,-z,noexecstack,-Map,hello.map"
)
