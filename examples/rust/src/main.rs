#![no_main]
#![no_std]

use core::panic::PanicInfo;
use core::ptr::{addr_of_mut, read_volatile, write_volatile};
use cortex_m::peripheral::{SYST, syst::SystClkSource};

const RCC_AHB1ENR: usize = 0x4002_3830;
const RCC_APB2ENR: usize = 0x4002_3844;
const GPIOC: usize = 0x4002_0800;
const GPIOD: usize = 0x4002_0c00;
const USART6: usize = 0x4001_1400;
const GPIO_MODER: usize = 0x00;
const GPIO_BSRR: usize = 0x18;
const GPIO_AFRL: usize = 0x20;
const USART_BRR: usize = 0x0c;
const USART_ISR: usize = 0x1c;
const USART_TDR: usize = 0x28;
const HSI_HZ: u32 = 16_000_000;
const BAUD: u32 = 115_200;

#[unsafe(no_mangle)]
static mut uni_heartbeat: u32 = 0;
#[unsafe(no_mangle)]
static mut uni_tx_bytes: u32 = 0;

fn read(address: usize) -> u32 {
    // Each address used here is an aligned STM32F746 peripheral register.
    unsafe { read_volatile(address as *const u32) }
}

fn write(address: usize, value: u32) {
    unsafe { write_volatile(address as *mut u32, value) }
}

fn update(address: usize, mask: u32, value: u32) {
    write(address, (read(address) & !mask) | value);
}

fn init_board() {
    update(RCC_AHB1ENR, 0, (1 << 2) | (1 << 3));
    update(RCC_APB2ENR, 0, 1 << 5);
    let _ = read(RCC_AHB1ENR);
    let _ = read(RCC_APB2ENR);

    write(GPIOD + GPIO_BSRR, 1 << (7 + 16));
    update(GPIOD + GPIO_MODER, 3 << 14, 1 << 14);
    update(GPIOC + GPIO_AFRL, 0xff << 24, 0x88 << 24);
    update(GPIOC + GPIO_MODER, 0x0f << 12, 0x0a << 12);

    write(USART6 + USART_BRR, (HSI_HZ + BAUD / 2) / BAUD);
    write(USART6, (1 << 3) | (1 << 2) | 1); // TE, RE, UE
}

fn write_banner() {
    let message = b"Hello, UNI Clicker from Rust!\r\n";
    for &byte in message {
        while read(USART6 + USART_ISR) & (1 << 7) == 0 {} // TXE
        write(USART6 + USART_TDR, u32::from(byte));
    }
    while read(USART6 + USART_ISR) & (1 << 6) == 0 {} // TC
    unsafe {
        let bytes = addr_of_mut!(uni_tx_bytes);
        write_volatile(
            bytes,
            read_volatile(bytes).wrapping_add(message.len() as u32),
        );
    }
}

fn wait_ms(timer: &mut SYST, milliseconds: u32) {
    timer.clear_current();
    for _ in 0..milliseconds {
        while !timer.has_wrapped() {}
    }
}

#[cortex_m_rt::entry]
fn main() -> ! {
    let mut timer = cortex_m::Peripherals::take().unwrap().SYST;
    timer.set_clock_source(SystClkSource::Core);
    timer.set_reload(HSI_HZ / 1_000 - 1);
    timer.enable_counter();
    init_board();
    write_banner();

    let mut edges = 0u32;
    loop {
        wait_ms(&mut timer, 500);
        edges = edges.wrapping_add(1);
        let led_on = edges & 1 != 0;
        write(GPIOD + GPIO_BSRR, if led_on { 1 << 7 } else { 1 << 23 });
        unsafe { write_volatile(addr_of_mut!(uni_heartbeat), edges) };
        if !led_on {
            write_banner();
        }
    }
}

#[panic_handler]
fn panic(_: &PanicInfo) -> ! {
    loop {
        cortex_m::asm::bkpt();
    }
}
