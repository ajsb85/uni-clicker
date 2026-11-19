const microzig = @import("microzig");
const peripherals = microzig.chip.peripherals;

const rcc = @intFromPtr(peripherals.RCC);
const gpioc = @intFromPtr(peripherals.GPIOC);
const gpiod = @intFromPtr(peripherals.GPIOD);
const usart6 = @intFromPtr(peripherals.USART6);
const systick = 0xe000e010;
const hsi_hz = 16_000_000;
const baud = 115_200;
const led_bit = 1 << 7;
const banner = "Hello, UNI Clicker from Zig!\r\n";

pub const panic = microzig.panic;
pub const std_options = microzig.std_options(.{});

export var uni_heartbeat: u32 = 0;
export var uni_tx_bytes: u32 = 0;

comptime {
    microzig.export_startup();
}

fn register(address: usize) *volatile u32 {
    return @ptrFromInt(address);
}

fn update(address: usize, mask: u32, value: u32) void {
    const word = register(address);
    word.* = (word.* & ~mask) | value;
}

fn initBoard() void {
    update(rcc + 0x30, 0, (1 << 2) | (1 << 3));
    update(rcc + 0x44, 0, 1 << 5);
    _ = register(rcc + 0x30).*;
    _ = register(rcc + 0x44).*;

    register(gpiod + 0x18).* = led_bit << 16;
    update(gpiod, 3 << 14, 1 << 14);

    update(gpioc + 0x20, 0xff << 24, 0x88 << 24);
    update(gpioc, 0x0f << 12, 0x0a << 12);
    register(usart6 + 0x0c).* = (hsi_hz + baud / 2) / baud;
    register(usart6).* = (1 << 3) | (1 << 2) | 1;

    register(systick + 4).* = hsi_hz / 1000 - 1;
    register(systick).* = (1 << 2) | 1;
}

fn waitMs(milliseconds: u32) void {
    register(systick + 8).* = 0;
    for (0..milliseconds) |_| {
        while (register(systick).* & (1 << 16) == 0) {}
    }
}

fn writeBanner() void {
    for (banner) |byte| {
        while (register(usart6 + 0x1c).* & (1 << 7) == 0) {}
        register(usart6 + 0x28).* = byte;
    }
    while (register(usart6 + 0x1c).* & (1 << 6) == 0) {}
    const tx_bytes: *volatile u32 = &uni_tx_bytes;
    tx_bytes.* +%= banner.len;
}

pub fn main() noreturn {
    zig_entry();
}

export fn zig_entry() noreturn {
    initBoard();
    writeBanner();

    var edges: u32 = 0;
    const heartbeat: *volatile u32 = &uni_heartbeat;
    while (true) {
        waitMs(500);
        edges +%= 1;
        const lit = edges & 1 != 0;
        register(gpiod + 0x18).* = if (lit) led_bit else led_bit << 16;
        heartbeat.* = edges;
        if (!lit) writeBanner();
    }
}
