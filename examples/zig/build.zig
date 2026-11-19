const std = @import("std");
const microzig = @import("microzig");
const MicroBuild = microzig.MicroBuild(.{ .stm32 = true });

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const mb = MicroBuild.init(b, b.dependency("microzig", .{})) orelse return;
    const target = mb.ports.stm32.chips.STM32F746ZG.derive(.{
        .stack = .{ .ram_region_name = "SRAM" },
    });
    const firmware = mb.add_firmware(.{
        .name = "hello",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    mb.install_firmware(firmware, .{ .format = .elf });
}
