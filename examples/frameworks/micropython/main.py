from machine import Pin, UART
from time import sleep_ms

led = Pin(Pin.cpu.D7, Pin.OUT, value=0)
uart = UART(6, baudrate=115200)
banner = b"Hello, UNI Clicker from MicroPython!\r\n"

while True:
    uart.write(banner)
    sleep_ms(500)
    led.value(1)
    sleep_ms(500)
    led.value(0)
