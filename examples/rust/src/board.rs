use core::ptr::{read_volatile, write_volatile};

const RCC_AHB1ENR: usize = 0x4002_3830;
const RCC_APB2ENR: usize = 0x4002_3844;
pub(crate) const GPIOC: usize = 0x4002_0800;
pub(crate) const GPIOD: usize = 0x4002_0c00;
pub(crate) const USART6: usize = 0x4001_1400;
const GPIO_MODER: usize = 0x00;
const GPIO_BSRR: usize = 0x18;
const GPIO_AFRL: usize = 0x20;
const USART_BRR: usize = 0x0c;
const USART_ISR: usize = 0x1c;
const USART_TDR: usize = 0x28;
pub(crate) const HSI_HZ: u32 = 16_000_000;
const BAUD: u32 = 115_200;

pub(crate) fn read(address: usize) -> u32 {
    // The caller supplies an aligned STM32F746 peripheral register.
    unsafe { read_volatile(address as *const u32) }
}

fn write(address: usize, value: u32) {
    unsafe { write_volatile(address as *mut u32, value) }
}

fn update(address: usize, mask: u32, value: u32) {
    write(address, (read(address) & !mask) | value);
}

pub(crate) fn set_led(on: bool) {
    write(GPIOD + GPIO_BSRR, if on { 1 << 7 } else { 1 << 23 });
}

pub(crate) fn init() {
    update(RCC_AHB1ENR, 0, (1 << 2) | (1 << 3));
    update(RCC_APB2ENR, 0, 1 << 5);
    let _ = read(RCC_AHB1ENR);
    let _ = read(RCC_APB2ENR);

    set_led(false);
    update(GPIOD + GPIO_MODER, 3 << 14, 1 << 14);
    update(GPIOC + GPIO_AFRL, 0xff << 24, 0x88 << 24);
    update(GPIOC + GPIO_MODER, 0x0f << 12, 0x0a << 12);

    write(USART6 + USART_BRR, (HSI_HZ + BAUD / 2) / BAUD);
    write(USART6, (1 << 3) | (1 << 2) | 1);
}

pub(crate) fn write_uart(message: &[u8]) {
    for &byte in message {
        while read(USART6 + USART_ISR) & (1 << 7) == 0 {} // TXE
        write(USART6 + USART_TDR, u32::from(byte));
    }
    while read(USART6 + USART_ISR) & (1 << 6) == 0 {} // TC
}
