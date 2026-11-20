use std::env;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

use crate::{
    Firmware, Image, RAM_BASE, RAM_TOP, Result, cube_flash, host_path, read_stdout, run, tool,
};

#[derive(Clone, Copy)]
pub(super) enum Programmer {
    Cube,
    ProbeRs,
}

impl Programmer {
    pub(super) fn parse(value: &str) -> Result<Self> {
        match value {
            "cubeprogrammer" => Ok(Self::Cube),
            "probe-rs" => Ok(Self::ProbeRs),
            _ => Err(format!("unknown programmer {value:?}").into()),
        }
    }

    pub(super) fn name(self) -> &'static str {
        match self {
            Self::Cube => "cubeprogrammer",
            Self::ProbeRs => "probe-rs",
        }
    }

    pub(super) fn validate(self, firmware: Firmware) -> Result<()> {
        if matches!(self, Self::ProbeRs) && !matches!(firmware, Firmware::Rust) {
            return Err("the probe-rs programmer supports the rust profile".into());
        }
        Ok(())
    }

    pub(super) fn flash(self, firmware: Firmware) -> Result<()> {
        self.validate(firmware)?;
        Image::read(firmware)?;
        match self {
            Self::Cube => cube_flash(firmware),
            Self::ProbeRs => probe_rs_flash(firmware),
        }
    }
}

fn probe_rs(program: &OsStr, subcommand: &str) -> Command {
    let mut command = Command::new("timeout");
    command
        .args([
            "--kill-after=2s",
            if subcommand == "download" {
                "60s"
            } else {
                "8s"
            },
        ])
        .arg(program);
    let probe = match env::var("UNI_PROBE_SERIAL") {
        Ok(serial) => format!("0483:3748:{serial}"),
        Err(_) => "0483:3748".to_owned(),
    };
    command.args([
        subcommand,
        "--chip",
        "STM32F746ZG",
        "--protocol",
        "swd",
        "--probe",
        &probe,
        "--speed",
        "240",
        "--non-interactive",
    ]);
    command
}

fn probe_rs_words(program: &OsStr, width: &str, address: u32, count: &str) -> Result<String> {
    read_stdout(probe_rs(program, "read").args([
        "-f",
        "simple-hex",
        width,
        &format!("{address:#x}"),
        count,
    ]))
}

fn probe_rs_flash_elf(program: &OsStr, elf: &Path) -> Result<()> {
    let image = host_path(program, elf)?;
    let id = probe_rs_words(program, "b32", 0xe0042000, "1")?;
    let capacity = probe_rs_words(program, "b16", 0x1ff0f442, "1")?;
    let device_id = u32::from_str_radix(id.trim(), 16)? & 0xfff;
    let flash_kib = u32::from_str_radix(capacity.trim(), 16)?;
    if device_id != 0x449 || flash_kib != 1024 {
        return Err(
            format!("unexpected SWD target: ID {device_id:#x}, flash {flash_kib} KiB").into(),
        );
    }
    println!("probe-rs target ID {device_id:#x}, flash {flash_kib} KiB");
    run(probe_rs(program, "download")
        .args([
            "--connect-under-reset",
            "--preverify",
            "--verify",
            "--disable-progressbars",
            "--binary-format",
            "elf",
        ])
        .arg(image))?;
    println!("probe-rs completed flash verification");
    run(&mut probe_rs(program, "reset"))
}

fn probe_rs_flash(firmware: Firmware) -> Result<()> {
    probe_rs_flash_elf(&tool("PROBE_RS", "probe-rs"), &firmware.artifact("elf"))
}

pub(super) fn capture_trace(elf: &Path, directory: &Path, uart: Option<&str>) -> Result<()> {
    let symbols = read_stdout(
        Command::new("arm-none-eabi-nm")
            .args(["-S", "--defined-only"])
            .arg(elf),
    )?;
    let mut fields = symbols
        .lines()
        .find(|line| line.split_whitespace().last() == Some("uni_trace_capture"))
        .ok_or("trace ELF has no capture buffer")?
        .split_whitespace();
    let address = u32::from_str_radix(fields.next().ok_or("missing capture address")?, 16)?;
    let size = u32::from_str_radix(fields.next().ok_or("missing capture size")?, 16)?;
    if address < RAM_BASE
        || address & 3 != 0
        || size <= 4
        || address.checked_add(size).is_none_or(|end| end > RAM_TOP)
    {
        return Err("trace capture buffer is outside SRAM".into());
    }

    fs::create_dir_all(directory)?;
    fs::create_dir_all(".cache")?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(".cache/probe.lock")?;
    let status = Command::new("flock")
        .args(["-n", "0"])
        .stdin(lock.try_clone()?)
        .status()?;
    if !status.success() {
        return Err("another bench run owns the probe".into());
    }

    let program = tool("PROBE_RS", "probe-rs");
    probe_rs_flash_elf(&program, elf)?;
    if let Some(port) = uart {
        let reset = probe_rs(&program, "reset");
        run(Command::new("python3")
            .arg("tools/console_uart.py")
            .args(["--port", port, "--trace", "--output"])
            .arg(directory)
            .arg("--")
            .arg(reset.get_program())
            .args(reset.get_args()))?;
    }
    let started = Instant::now();
    let length = loop {
        let output = probe_rs_words(&program, "b32", address, "1")?;
        let length = u32::from_str_radix(output.trim(), 16)?;
        if length != 0 {
            break length;
        }
        if started.elapsed() >= Duration::from_secs(8) {
            return Err("the board did not finalize its trace snapshot in 8 seconds".into());
        }
        thread::sleep(Duration::from_millis(100));
    };
    if length > size - 4 {
        return Err(format!("invalid trace snapshot length {length}, buffer size {size}").into());
    }

    let snapshot = directory.join("sram.bin");
    File::create(&snapshot)?;
    let path = host_path(&program, &snapshot)?;
    run(probe_rs(&program, "read")
        .args(["-f", "binary", "-o"])
        .arg(path)
        .args(["b8", &format!("{address:#x}"), &(length + 4).to_string()]))?;
    if fs::metadata(&snapshot)?.len() != u64::from(length + 4) {
        return Err("SWD read returned a truncated trace snapshot".into());
    }
    let faults = probe_rs_words(&program, "b32", 0xe000ed28, "2")?;
    if !faults.split_whitespace().eq(["00000000", "00000000"]) {
        return Err(format!("hardware trace fault status: {}", faults.trim()).into());
    }
    if uart.is_some() {
        let gpio = probe_rs_words(&program, "b32", 0x40020c14, "1")?;
        if u32::from_str_radix(gpio.trim(), 16)? & (1 << 7) != 0 {
            return Err("PD7 is high after the console requested led off".into());
        }
    }
    println!("Read {length} trace bytes over SWD, CFSR and HFSR clear");
    Ok(())
}
