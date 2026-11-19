use std::env;
use std::error::Error;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

type Result<T> = std::result::Result<T, Box<dyn Error>>;

const FLASH_BASE: u32 = 0x0800_0000;
const FLASH_ITCM_ALIAS: u32 = 0x0020_0000;
const FLASH_SIZE: usize = 1024 * 1024;
const RAM_BASE: u32 = 0x2000_0000;
const RAM_TOP: u32 = 0x2005_0000;
const HELP: &str = "uni-cli <command> [firmware] [endpoint]
  build <firmware|all>                     Build firmware with Make
  analyze <firmware>                      Inspect vectors, sections, and symbols
  probe                                   Identify the MCU over STM32CubeProgrammer SWD
  flash <firmware>                        Program, verify, and reset the UNI Clicker
  debug <firmware> [localhost:3333]         Open an interactive GDB session
  verify <firmware> [localhost:3333]        Check reset, entry, and three LED edges in GDB
  simulate <firmware> [smoke|gpio|trace|gdb] Run the firmware in Renode

Profiles: stm32cube arduino rust swift zig necto necto-windows mikroc mikroc-source-check
          freertos threadx libopencm3 riot chibios zephyr mbed-os
          pio-arduino pio-stm32cube pio-cmsis pio-libopencm3 pio-zephyr";

#[derive(Clone, Copy)]
enum Firmware {
    Stm32Cube,
    Arduino,
    Rust,
    Swift,
    Zig,
    Necto,
    NectoWindows,
    Mikroc,
    MikrocSourceCheck,
    FreeRtos,
    ThreadX,
    LibOpenCm3,
    Riot,
    ChibiOs,
    Zephyr,
    MbedOs,
    PioArduino,
    PioStm32Cube,
    PioCmsis,
    PioLibOpenCm3,
    PioZephyr,
}

impl Firmware {
    fn parse(name: &str) -> Result<Self> {
        match name {
            "stm32cube" => Ok(Self::Stm32Cube),
            "arduino" => Ok(Self::Arduino),
            "rust" => Ok(Self::Rust),
            "swift" => Ok(Self::Swift),
            "zig" => Ok(Self::Zig),
            "necto" => Ok(Self::Necto),
            "necto-windows" => Ok(Self::NectoWindows),
            "mikroc" => Ok(Self::Mikroc),
            "mikroc-source-check" => Ok(Self::MikrocSourceCheck),
            "freertos" => Ok(Self::FreeRtos),
            "threadx" => Ok(Self::ThreadX),
            "libopencm3" => Ok(Self::LibOpenCm3),
            "riot" => Ok(Self::Riot),
            "chibios" => Ok(Self::ChibiOs),
            "zephyr" => Ok(Self::Zephyr),
            "mbed-os" => Ok(Self::MbedOs),
            "pio-arduino" => Ok(Self::PioArduino),
            "pio-stm32cube" => Ok(Self::PioStm32Cube),
            "pio-cmsis" => Ok(Self::PioCmsis),
            "pio-libopencm3" => Ok(Self::PioLibOpenCm3),
            "pio-zephyr" => Ok(Self::PioZephyr),
            _ => Err(format!("unknown firmware {name:?}").into()),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Stm32Cube => "stm32cube",
            Self::Arduino => "arduino",
            Self::Rust => "rust",
            Self::Swift => "swift",
            Self::Zig => "zig",
            Self::Necto => "necto",
            Self::NectoWindows => "necto-windows",
            Self::Mikroc => "mikroc",
            Self::MikrocSourceCheck => "mikroc-source-check",
            Self::FreeRtos => "freertos",
            Self::ThreadX => "threadx",
            Self::LibOpenCm3 => "libopencm3",
            Self::Riot => "riot",
            Self::ChibiOs => "chibios",
            Self::Zephyr => "zephyr",
            Self::MbedOs => "mbed-os",
            Self::PioArduino => "pio-arduino",
            Self::PioStm32Cube => "pio-stm32cube",
            Self::PioCmsis => "pio-cmsis",
            Self::PioLibOpenCm3 => "pio-libopencm3",
            Self::PioZephyr => "pio-zephyr",
        }
    }

    fn artifact(self, suffix: &str) -> PathBuf {
        if let Some(profile) = self.name().strip_prefix("pio-") {
            let build_dir = env::var_os("PLATFORMIO_BUILD_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("examples/platformio/.pio/build"));
            return build_dir.join(profile).join(format!("firmware.{suffix}"));
        }
        let basename = match self {
            Self::Arduino => "HelloUni.ino",
            _ => "hello",
        };
        PathBuf::from(format!("build/{}/{basename}.{suffix}", self.name()))
    }

    fn entry(self) -> &'static str {
        match self {
            Self::Arduino | Self::PioArduino => "setup",
            Self::Swift => "uni_swift_main",
            Self::Zig => "zig_entry",
            Self::Mikroc => "mikroc_app_entry",
            Self::MikrocSourceCheck => "mikroc_source_entry",
            _ => "main",
        }
    }

    fn banner_size(self) -> usize {
        let language = match self {
            Self::Stm32Cube | Self::PioStm32Cube => "STM32Cube",
            Self::Arduino | Self::PioArduino => "Arduino",
            Self::Rust => "Rust",
            Self::Swift => "Embedded Swift",
            Self::Zig => "Zig",
            Self::Necto | Self::NectoWindows => "NECTO",
            Self::Mikroc | Self::MikrocSourceCheck => "mikroC",
            Self::FreeRtos => "FreeRTOS",
            Self::ThreadX => "ThreadX",
            Self::LibOpenCm3 | Self::PioLibOpenCm3 => "libopencm3",
            Self::Riot => "RIOT",
            Self::ChibiOs => "ChibiOS",
            Self::Zephyr | Self::PioZephyr => "Zephyr",
            Self::MbedOs => "Mbed OS",
            Self::PioCmsis => "CMSIS",
        };
        "Hello, UNI Clicker from !\r\n".len() + language.len()
    }

    fn uart_divisor(self) -> u16 {
        match self {
            Self::Riot => 138,
            Self::MbedOs => 938,
            _ => 139,
        }
    }
}

struct Image {
    stack: u32,
    reset: u32,
    length: usize,
}

impl Image {
    fn read(path: &Path, firmware: Firmware) -> Result<Self> {
        let bytes = fs::read(path)?;
        if !(8..=FLASH_SIZE).contains(&bytes.len()) {
            return Err(format!("{} exceeds the STM32F746 flash limits", path.display()).into());
        }
        let stack = u32::from_le_bytes(bytes[..4].try_into()?);
        let reset = u32::from_le_bytes(bytes[4..8].try_into()?);
        let reset_address = reset & !1;
        let image_size = bytes.len() as u32;
        let reset_in_flash = (FLASH_BASE..FLASH_BASE + image_size).contains(&reset_address);
        let reset_in_alias = matches!(firmware, Firmware::ChibiOs)
            && (FLASH_ITCM_ALIAS..FLASH_ITCM_ALIAS + image_size).contains(&reset_address);
        // Native mikroC starts at a word-aligned MSP and aligns it in the first instruction.
        let stack_alignment = if matches!(firmware, Firmware::Mikroc) {
            4
        } else {
            8
        };
        if !(RAM_BASE + 8..=RAM_TOP).contains(&stack)
            || stack % stack_alignment != 0
            || !(reset_in_flash || reset_in_alias)
            || reset & 1 == 0
        {
            return Err(
                format!("invalid vector table: MSP {stack:#010x}, reset {reset:#010x}").into(),
            );
        }
        Ok(Self {
            stack,
            reset,
            length: bytes.len(),
        })
    }
}

fn tool(setting: &str, fallback: &str) -> OsString {
    env::var_os(setting).unwrap_or_else(|| fallback.into())
}

fn run(command: &mut Command) -> Result<()> {
    let status = command.status()?;
    if !status.success() {
        return Err(format!("{:?} exited with {status}", command.get_program()).into());
    }
    Ok(())
}

fn read_stdout(command: &mut Command) -> Result<String> {
    let output = command.output()?;
    if !output.status.success() {
        return Err(format!(
            "{:?} exited with {}\n{}{}",
            command.get_program(),
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        )
        .into());
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

fn cube(program: &OsStr) -> Command {
    let mut command = Command::new(program);
    command.args(["-q", "-c", "port=SWD", "mode=UR", "freq=400"]);
    if let Ok(serial) = env::var("UNI_PROBE_SERIAL") {
        command.arg(format!("sn={serial}"));
    }
    command
}

fn probe(program: &OsStr) -> Result<()> {
    let output = read_stdout(&mut cube(program))?;
    print!("{output}");
    if !output.lines().any(|line| {
        line.split_once(':')
            .is_some_and(|(key, value)| key.trim() == "Device ID" && value.trim() == "0x449")
    }) || !output.lines().any(|line| {
        line.split_once(':')
            .is_some_and(|(key, value)| key.trim() == "NVM size" && value.trim() == "1 MBytes")
    }) {
        return Err("expected STM32F74x/F75x device ID 0x449 and 1 MiB of flash".into());
    }
    Ok(())
}

fn flash(firmware: Firmware) -> Result<()> {
    let binary = firmware.artifact("bin");
    Image::read(&binary, firmware)?;
    let path = binary.canonicalize()?;
    let programmer = tool("CUBE_PROG", "STM32_Programmer_CLI");
    let windows_exe = Path::new(&programmer)
        .extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("exe"));
    let path = if cfg!(target_os = "linux") && windows_exe {
        read_stdout(Command::new("wslpath").arg("-w").arg(path))?
            .trim_end_matches(['\r', '\n'])
            .into()
    } else {
        path.into_os_string()
    };
    probe(&programmer)?;
    let output =
        read_stdout(
            cube(&programmer)
                .arg("-d")
                .arg(path)
                .args(["0x08000000", "-v", "-rst"]),
        )?;
    print!("{output}");
    if !output
        .lines()
        .any(|line| line.contains("Download verified successfully"))
    {
        return Err("STM32CubeProgrammer did not confirm flash verification".into());
    }
    Ok(())
}

fn read_symbols(elf: &Path) -> Result<String> {
    read_stdout(Command::new("arm-none-eabi-nm").arg("-n").arg(elf))
}

fn symbol_line<'a>(symbols: &'a str, name: &str) -> Result<&'a str> {
    symbols
        .lines()
        .find(|line| line.split_whitespace().last() == Some(name))
        .ok_or_else(|| format!("missing ELF symbol: {name}").into())
}

fn analyze(firmware: Firmware) -> Result<()> {
    let binary = firmware.artifact("bin");
    let elf = firmware.artifact("elf");
    let image = Image::read(&binary, firmware)?;
    println!(
        "{} bytes at {FLASH_BASE:#010x}, initial MSP {:#010x}, reset vector {:#010x}",
        image.length, image.stack, image.reset
    );
    run(Command::new("arm-none-eabi-size").arg(&elf))?;
    run(Command::new("arm-none-eabi-readelf")
        .args(["-h", "-l", "-A"])
        .arg(&elf))?;

    let symbols = read_symbols(&elf)?;
    for symbol in [firmware.entry(), "uni_heartbeat", "uni_tx_bytes"] {
        println!("{}", symbol_line(&symbols, symbol)?);
    }
    Ok(())
}

fn debug(firmware: Firmware, endpoint: Option<&str>, verify: bool) -> Result<()> {
    let endpoint = endpoint.unwrap_or("localhost:3333");
    if endpoint.is_empty()
        || !endpoint
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || b".:[]-_".contains(&byte))
    {
        return Err("invalid GDB endpoint".into());
    }

    let gdb = tool("GDB", "gdb-multiarch");
    let mut command = if verify {
        let mut timeout = Command::new("timeout");
        timeout
            .args(["--kill-after=2s", "30s"])
            .arg(gdb)
            .arg("-batch");
        timeout
    } else {
        Command::new(gdb)
    };
    let elf = firmware.artifact("elf");
    command
        .args(["-q", "-nx"])
        .arg(&elf)
        .args(["-ex", "set remotetimeout 5"])
        .arg("-ex")
        .arg(format!("target extended-remote {endpoint}"));

    if verify {
        let image = Image::read(&firmware.artifact("bin"), firmware)?;
        let symbols = read_symbols(&elf)?;
        for (variable, symbol) in [
            ("uni_entry", firmware.entry()),
            ("uni_heartbeat_address", "uni_heartbeat"),
            ("uni_tx_address", "uni_tx_bytes"),
        ] {
            let line = symbol_line(&symbols, symbol)?;
            let address = line
                .split_whitespace()
                .next()
                .ok_or("missing symbol address")?;
            let address = u32::from_str_radix(address, 16)?;
            command
                .arg("-ex")
                .arg(format!("set ${variable} = {address:#x}"));
        }
        command
            .arg("-ex")
            .arg(format!("set $uni_expected_msp = {:#x}", image.stack))
            .arg("-ex")
            .arg(format!("set $uni_expected_vector = {:#x}", image.reset))
            .arg("-ex")
            .arg(format!("set $uni_banner_size = {}", firmware.banner_size()))
            .arg("-ex")
            .arg(format!(
                "set $uni_expected_brr = {}",
                firmware.uart_divisor()
            ))
            .arg("-ex")
            .arg(format!(
                "set $uni_buffered_uart = {}",
                u8::from(matches!(firmware, Firmware::ChibiOs))
            ))
            .args(["-x", "debug/verify.gdb"]);
    }
    run(&mut command)
}

fn execute(args: &[String]) -> Result<()> {
    let firmware = match args {
        [] => return Err(HELP.into()),
        [cmd] if cmd == "help" || cmd == "--help" || cmd == "-h" => {
            println!("{HELP}");
            return Ok(());
        }
        _ => args,
    };
    let cwd = env::current_dir()?;
    let root = cwd.ancestors().find(|directory| {
        directory.join("Makefile").is_file() && directory.join("debug/verify.gdb").is_file()
    });
    env::set_current_dir(root.ok_or("run uni-cli from the UNI Clicker repository")?)?;

    match firmware {
        [cmd, name] if cmd == "build" => {
            let target = if name == "all" {
                "all"
            } else {
                Firmware::parse(name)?.name()
            };
            run(Command::new("make").arg(target))
        }
        [cmd] if cmd == "probe" => probe(&tool("CUBE_PROG", "STM32_Programmer_CLI")),
        [cmd, name] if cmd == "analyze" => analyze(Firmware::parse(name)?),
        [cmd, name] if cmd == "flash" => flash(Firmware::parse(name)?),
        [cmd, name, rest @ ..] if cmd == "simulate" && rest.len() <= 1 => {
            let firmware = Firmware::parse(name)?;
            let mut command = Command::new("tools/simulate.sh");
            if let Some(profile) = firmware.name().strip_prefix("pio-") {
                command
                    .arg(profile)
                    .env("UNI_SIM_ELF", firmware.artifact("elf").canonicalize()?);
            } else {
                command.arg(firmware.name());
            }
            run(command.args(rest))
        }
        [cmd, name, endpoint] if cmd == "debug" || cmd == "verify" => {
            debug(Firmware::parse(name)?, Some(endpoint), cmd == "verify")
        }
        [cmd, name] if cmd == "debug" || cmd == "verify" => {
            debug(Firmware::parse(name)?, None, cmd == "verify")
        }
        _ => Err(HELP.into()),
    }
}

fn main() -> ExitCode {
    match execute(&env::args().skip(1).collect::<Vec<_>>()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}
