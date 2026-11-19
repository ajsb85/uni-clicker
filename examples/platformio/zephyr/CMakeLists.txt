cmake_minimum_required(VERSION 3.20)

set(UNI_ZEPHYR "${CMAKE_CURRENT_LIST_DIR}/../../frameworks/zephyr")
set(CONF_FILE "${UNI_ZEPHYR}/prj.conf")
set(DTC_OVERLAY_FILE "${UNI_ZEPHYR}/app.overlay;${CMAKE_CURRENT_LIST_DIR}/platformio.overlay")
find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(uni_clicker_hello)
target_sources(app PRIVATE ../src/zephyr.c)
