APPLICATION = uni_clicker_hello
BOARD ?= uni-clicker-f746zg
RIOTBASE ?= $(CURDIR)/../../../.cache/vendor/RIOT
EXTERNAL_BOARD_DIRS += $(CURDIR)/boards
USEMODULE += ztimer_msec
ifeq ($(BOARD),uni-clicker-f746zg)
  USEMODULE += stdio_uart_rx
  DISABLE_MODULE += stdio_uart_onlcr
endif
include $(RIOTBASE)/Makefile.include
