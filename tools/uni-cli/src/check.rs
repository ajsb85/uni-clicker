use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use crate::{Firmware, Programmer, Result, read_stdout, run, tool};

pub(super) fn run_check(firmware: Firmware, flags: &[String]) -> Result<()> {
    let mut hardware = false;
    let mut trace = false;
    let mut hardware_trace = false;
    let mut uart = None;
    let mut runs = None;
    let mut programmer = None;
    let mut arguments = flags.iter();
    while let Some(flag) = arguments.next() {
        match flag.as_str() {
            "--hardware" if !hardware => hardware = true,
            "--trace" if !trace => trace = true,
            "--hardware-trace" if !hardware_trace => hardware_trace = true,
            "--uart" if uart.is_none() => {
                uart = Some(
                    arguments
                        .next()
                        .ok_or("--uart requires a Windows COM port")?,
                );
            }
            "--runs" if runs.is_none() => {
                let value: usize = arguments.next().ok_or("--runs requires a count")?.parse()?;
                if !(1..=10).contains(&value) {
                    return Err("--runs must be between 1 and 10".into());
                }
                runs = Some(value);
            }
            "--programmer" if programmer.is_none() => {
                programmer = Some(Programmer::parse(
                    arguments.next().ok_or("--programmer requires a value")?,
                )?);
            }
            _ => return Err(format!("unexpected check option {flag:?}").into()),
        }
    }
    if programmer.is_some() && !hardware {
        return Err("--programmer requires --hardware".into());
    }
    let programmer = programmer.unwrap_or(Programmer::Cube);
    programmer.validate(firmware)?;
    if trace
        && !matches!(
            firmware,
            Firmware::Stm32Cube | Firmware::FreeRtos | Firmware::FreeRtosConsole
        )
    {
        return Err("trace checks support stm32cube, freertos, and freertos-console".into());
    }
    let console_hardware = hardware_trace && matches!(firmware, Firmware::FreeRtosConsole);
    if console_hardware && uart.is_none() {
        return Err("freertos-console --hardware-trace requires --uart COMx".into());
    }
    if !console_hardware && (uart.is_some() || runs.is_some()) {
        return Err("--uart and --runs require freertos-console --hardware-trace".into());
    }
    if hardware_trace
        && !matches!(
            firmware,
            Firmware::Stm32Cube | Firmware::FreeRtos | Firmware::FreeRtosConsole
        )
    {
        return Err(
            "hardware trace checks support stm32cube, freertos, and freertos-console".into(),
        );
    }

    let name = firmware.name();
    let cli = env::current_exe()?;
    let reports = env::current_dir()?.join(".cache/verification");
    fs::create_dir_all(&reports)?;
    let timestamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let directory = reports.join(format!("check.{name}.{timestamp}.{}", std::process::id()));
    let mut run_dir = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        run_dir.mode(0o700);
    }
    run_dir.create(&directory)?;
    let report_path = directory.join("report.tsv");
    let mut report = File::create(&report_path)?;
    writeln!(report, "stage\tstatus\telapsed_ms\tlog")?;
    println!("Report {}", report_path.display());

    // flock keeps the lock on this open file description across subprocesses.
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(reports.join(format!("check.{name}.lock")))?;
    let locked = Command::new("flock")
        .args(["-n", "-E", "75", "0"])
        .stdin(lock.try_clone()?)
        .status();
    match locked {
        Ok(status) if status.success() => {}
        Ok(status) if status.code() == Some(75) => {
            writeln!(report, "result\tbusy\t0\t-")?;
            return Err(format!("another check for {name} is running").into());
        }
        failed => {
            writeln!(report, "result\tfailed\t0\t-")?;
            return Err(match failed {
                Ok(status) => format!("flock exited with {status}").into(),
                Err(error) => format!("could not run flock: {error}").into(),
            });
        }
    }

    let started = Instant::now();
    let mut failed_stage = None;
    let mut built = false;
    let stages = ["build", "analyze", "simulate"]
        .into_iter()
        .chain(trace.then_some("trace"))
        .chain(hardware_trace.then_some("hardware-trace"))
        .chain(["hardware"]);
    for stage in stages {
        if failed_stage.is_some() || (stage == "hardware" && !hardware) {
            writeln!(report, "{stage}\tskipped\t0\t-")?;
            continue;
        }
        let mut command = if stage == "hardware" {
            let mut command = Command::new("tools/verify-bench.sh");
            command
                .arg(name)
                .env("UNI_VERIFY_CLI", &cli)
                .env("UNI_VERIFY_PROGRAMMER", programmer.name())
                .env("UNI_VERIFY_LOG_DIR", directory.join("hardware"));
            command
        } else if matches!(stage, "trace" | "hardware-trace") {
            let mut command = Command::new("tools/check-tonbandgeraet.sh");
            command
                .arg(name)
                .arg(directory.join(stage))
                .env("UNI_TRACE_CLI", &cli);
            if stage == "hardware-trace" {
                command.arg("--hardware");
                if let Some(port) = uart {
                    command.arg(port).arg(runs.unwrap_or(3).to_string());
                }
            }
            command
        } else {
            let mut command = Command::new(&cli);
            command.args([stage, name]);
            command
        };
        let log_name = format!("{stage}.log");
        println!("Running {stage} for {name}");
        let stage_start = Instant::now();
        let status = match run_logged(&mut command, &directory.join(&log_name)) {
            Ok(()) => {
                if stage == "build" {
                    built = true;
                }
                "passed"
            }
            Err(error) => {
                failed_stage = Some((stage, error));
                "failed"
            }
        };
        let elapsed = stage_start.elapsed().as_millis();
        writeln!(report, "{stage}\t{status}\t{elapsed}\t{log_name}")?;
    }
    let provenance_start = Instant::now();
    let provenance = "provenance.tsv";
    let status = match write_provenance(
        &directory,
        firmware,
        built,
        hardware,
        hardware_trace,
        programmer,
    ) {
        Ok(()) => "passed",
        Err(error) => {
            writeln!(File::create(directory.join("provenance.log"))?, "{error}")?;
            if failed_stage.is_none() {
                failed_stage = Some(("provenance", error));
            }
            "failed"
        }
    };
    let log = if status == "passed" {
        provenance
    } else {
        "provenance.log"
    };
    writeln!(
        report,
        "provenance\t{status}\t{}\t{log}",
        provenance_start.elapsed().as_millis()
    )?;

    let elapsed = started.elapsed().as_millis();
    if let Some((stage, error)) = failed_stage {
        writeln!(report, "result\tfailed\t{elapsed}\t{stage}.log")?;
        return Err(format!(
            "{name} failed at {stage}: {error}. See {}",
            report_path.display()
        )
        .into());
    }
    writeln!(report, "result\tpassed\t{elapsed}\t-")?;
    println!("{name} passed");
    Ok(())
}

fn write_provenance(
    directory: &Path,
    firmware: Firmware,
    built: bool,
    hardware: bool,
    hardware_trace: bool,
    programmer: Programmer,
) -> Result<()> {
    let mut file = File::create(directory.join("provenance.tsv"))?;
    writeln!(file, "kind\tname\tvalue")?;
    let revision = read_stdout(Command::new("git").args(["rev-parse", "HEAD"]))?;
    let status = read_stdout(Command::new("git").args(["status", "--porcelain", "-uno"]))?;
    writeln!(file, "source\tcommit\t{}", revision.trim())?;
    writeln!(
        file,
        "source\ttracked_changes\t{}",
        !status.trim().is_empty()
    )?;

    if built {
        record_hash(&mut file, "firmware", &firmware.artifact("elf"))?;
    }
    for stage in ["trace", "hardware-trace"] {
        let path = directory.join(stage).join("hello.elf");
        if path.is_file() {
            record_hash(&mut file, stage, &path)?;
        }
    }

    let mut programs = vec![
        ("renode", "RENODE", "renode", "--version"),
        (
            "arm-none-eabi-gcc",
            "STM32_GCC",
            "arm-none-eabi-gcc",
            "--version",
        ),
    ];
    match firmware {
        Firmware::Rust => programs.extend([
            ("cargo", "CARGO", "cargo", "--version"),
            ("rustc", "RUSTC", "rustc", "--version"),
        ]),
        Firmware::Arduino => {
            programs.push(("arduino-cli", "ARDUINO_CLI", "arduino-cli", "version"))
        }
        Firmware::Swift => programs.push(("swiftc", "SWIFTC", "swiftc", "--version")),
        Firmware::Zig => programs.push(("zig", "ZIG", "zig", "version")),
        _ if firmware.name().starts_with("pio-") => {
            programs.push(("platformio", "PLATFORMIO", "pio", "--version"));
        }
        _ => {}
    }
    if hardware {
        programs.extend([
            ("gdb", "GDB", "gdb-multiarch", "--version"),
            ("openocd", "OPENOCD", "openocd", "--version"),
        ]);
        if matches!(programmer, Programmer::Cube) {
            programs.push((
                "cubeprogrammer",
                "CUBE_PROG",
                "STM32_Programmer_CLI",
                "--version",
            ));
        }
    }
    if hardware_trace || hardware && matches!(programmer, Programmer::ProbeRs) {
        programs.push(("probe-rs", "PROBE_RS", "probe-rs", "--version"));
    }
    for (name, variable, fallback, arg) in programs {
        let output = Command::new("timeout")
            .args(["--kill-after=1s", "5s"])
            .arg(tool(variable, fallback))
            .arg(arg)
            .output();
        let version = output
            .ok()
            .filter(|result| result.status.success())
            .and_then(|result| {
                [result.stdout, result.stderr]
                    .iter()
                    .flat_map(|stream| stream.split(|byte| matches!(byte, b'\r' | b'\n')))
                    .map(String::from_utf8_lossy)
                    .find(|line| line.bytes().any(|byte| byte.is_ascii_digit()))
                    .map(|line| line.trim().replace('\t', " "))
            });
        writeln!(
            file,
            "tool\t{name}\t{}",
            version.as_deref().unwrap_or("unavailable")
        )?;
    }
    Ok(())
}

fn record_hash(file: &mut File, name: &str, path: &Path) -> Result<()> {
    let output = read_stdout(Command::new("sha256sum").arg("--").arg(path))?;
    let hash = output
        .split_whitespace()
        .next()
        .ok_or("empty sha256sum output")?;
    writeln!(file, "elf_sha256\t{name}\t{hash}")?;
    Ok(())
}

fn run_logged(command: &mut Command, path: &Path) -> Result<()> {
    let mut log = File::create(path)?;
    let result = run(command
        .stdin(Stdio::null())
        .stdout(log.try_clone()?)
        .stderr(log.try_clone()?));
    if let Err(error) = &result {
        writeln!(log, "{error}")?;
    }
    result
}
