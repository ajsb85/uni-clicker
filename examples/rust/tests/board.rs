#![no_std]
#![no_main]

#[path = "../src/board.rs"]
mod board;

use core::sync::atomic::{AtomicU32, Ordering::Relaxed};
use cortex_m::peripheral::syst::SystClkSource;
use rtt_target::{rprintln, rtt_init_print};

static INTERRUPTS: AtomicU32 = AtomicU32::new(0);

#[cortex_m_rt::exception]
fn SysTick() {
    INTERRUPTS.fetch_add(1, Relaxed);
}

#[embedded_test::tests]
mod tests {
    use super::*;

    #[init]
    fn init() {
        rtt_init_print!();
        board::init();
    }

    #[test]
    fn pd7_output() {
        assert_eq!((board::read(board::GPIOD) >> 14) & 3, 1);
        for on in [true, false] {
            board::set_led(on);
            assert_eq!((board::read(board::GPIOD + 0x14) >> 7) & 1, u32::from(on));
        }
        rprintln!("PD7 output high and low");
    }

    #[test]
    #[timeout(3)]
    fn systick_interrupts() {
        let mut timer = cortex_m::Peripherals::take().unwrap().SYST;
        timer.set_clock_source(SystClkSource::Core);
        timer.set_reload(board::HSI_HZ / 1_000 - 1);
        timer.clear_current();
        timer.enable_interrupt();
        timer.enable_counter();
        while INTERRUPTS.load(Relaxed) < 3 {
            cortex_m::asm::wfi();
        }
        timer.disable_counter();
        timer.disable_interrupt();
        rprintln!("SysTick delivered {} interrupts", INTERRUPTS.load(Relaxed));
    }

    #[test]
    #[timeout(3)]
    fn usart6_transmit() {
        assert_eq!(board::read(board::GPIOC + 0x20) >> 24, 0x88);
        assert_eq!((board::read(board::GPIOC) >> 12) & 0x0f, 0x0a);
        assert_eq!(board::read(board::USART6 + 0x0c), 0x8b);
        board::write_uart(b"UNI Clicker board test\r\n");
        assert_ne!(board::read(board::USART6 + 0x1c) & (1 << 6), 0);
        rprintln!("USART6 transmit complete");
    }

    #[test]
    fn fault_registers() {
        assert_eq!(board::read(0xe000_ed28), 0);
        assert_eq!(board::read(0xe000_ed2c), 0);
        rprintln!("CFSR and HFSR are clear");
    }

    #[test]
    #[should_panic]
    fn runner_reports_panic() {
        rprintln!("Triggering expected test panic");
        panic!("expected board test panic");
    }
}
