# UNI Clicker USB-C device console

The baseboard manual describes USB mode selection on printed pages 12–13. The baseboard schematic shows CN3 and its PTN5150AHXMP CC controller on page 1. Page 2 shows the USB nets on the SiBRAIN socket. The STM32F746ZG card schematic maps those nets to the MCU. The SiBRAIN guidelines document the connector conventions. Local text and schematic images are indexed at `.cache/references/uni-clicker/README.md`. Run `tools/export-board-references.sh` to regenerate them from the four PDFs in the Windows workspace.

| Signal | Board connection |
| --- | --- |
| USB D− and D+ | CN3 to PA11 and PA12, respectively, using OTG_FS AF10 |
| VBUS detect | CN3 VBUS through R33 to the SiBRAIN PA9 VBUS net |
| USB role ID | PTN5150 ID to PA10 through the SiBRAIN socket |
| USB PSW | PB15 on SiBRAIN socket pin 129. High selects device and low selects host. |
| USB-C power | In device mode the connector accepts VBUS. In host mode the baseboard sources VBUS from its 5 V rail. |
| USB reference clock | The SiBRAIN 25 MHz HSE drives the PLL. `PLLM=25`, `PLLN=384`, and `PLLQ=8` produce 48 MHz. |

The `UsbCdcUni` sketch drives PB15 high before configuring the clock and starts the STM32duino USB CDC class in device mode. The core CPU runs at 96 MHz. The USB CDC class exposes a virtual COM port to Windows under the STM32duino generic F7 VID/PID `0483:5740`. Use a data-capable cable to CN3 while the board is in device mode. The manual warns against connecting the board to a PC in host mode.

```bash
source tools/bench-env.sh
make arduino-usb-cdc
tools/verify-usb-cdc.sh --hardware build/arduino-usb-cdc/UsbCdcUni.ino.elf
powershell.exe -NoProfile -NonInteractive -Command 'Get-CimInstance Win32_SerialPort | Where-Object PNPDeviceID -like "*VID_0483&PID_5740*" | Select-Object DeviceID,Name'
```

The SWD check verifies flash, steps the matching ELF, and checks PB15, PA11/PA12 alternate functions, the USB PLL, current device mode and CPU fault registers. If Windows assigns the device COM7, run the following to check ping, PD7 on and off, and the invalid-command reply. The script enables DTR for CDC and records the bytes under the output directory.

```bash
python3 tools/console_uart.py --usb-cdc --port COM7 --output .cache/verification/usb-cdc-serial
```

This CDC device provides a separate USB debug console. For USART6 IRQ-to-task measurements, use the 3.3 V adapter at J2.16 and J2.15 and the FreeRTOS UART regression. [Bench commands](../AGENT.MD#timing-captures-and-usart6-console)
