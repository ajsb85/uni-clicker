#![no_main]
#![no_std]

use core::panic::PanicInfo;
use core::ptr::{addr_of_mut, read_volatile, write_volatile};
use cortex_m::peripheral::{SYST, syst::SystClkSource};

mod board;
use board::HSI_HZ;

#[unsafe(no_mangle)]
static mut uni_heartbeat: u32 = 0;
#[unsafe(no_mangle)]
static mut uni_tx_bytes: u32 = 0;

fn write_banner() {
    let message = b"Hello, UNI Clicker from Rust!\r\n";
    board::write_uart(message);
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
    board::init();
    write_banner();

    let mut edges = 0u32;
    loop {
        wait_ms(&mut timer, 500);
        edges = edges.wrapping_add(1);
        let led_on = edges & 1 != 0;
        board::set_led(led_on);
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
