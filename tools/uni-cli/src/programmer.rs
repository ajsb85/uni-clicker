use std::env;
use std::ffi::OsStr;
use std::process::Command;

use crate::{Firmware, Image, Result, cube_flash, host_path, read_stdout, run, tool};

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
    let mut command = Command::new(program);
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

fn probe_rs_flash(firmware: Firmware) -> Result<()> {
    let program = tool("PROBE_RS", "probe-rs");
    let image = host_path(&program, &firmware.artifact("elf"))?;
    let id = read_stdout(probe_rs(&program, "read").args([
        "-f",
        "simple-hex",
        "b32",
        "0xe0042000",
        "1",
    ]))?;
    let capacity = read_stdout(probe_rs(&program, "read").args([
        "-f",
        "simple-hex",
        "b16",
        "0x1ff0f442",
        "1",
    ]))?;
    let device_id = u32::from_str_radix(id.trim(), 16)? & 0xfff;
    let flash_kib = u32::from_str_radix(capacity.trim(), 16)?;
    if device_id != 0x449 || flash_kib != 1024 {
        return Err(
            format!("unexpected SWD target: ID {device_id:#x}, flash {flash_kib} KiB").into(),
        );
    }
    println!("probe-rs target ID {device_id:#x}, flash {flash_kib} KiB");
    run(probe_rs(&program, "download")
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
    run(&mut probe_rs(&program, "reset"))
}
