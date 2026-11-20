use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use crate::{Firmware, Programmer, Result, run};

pub(super) fn run_check(firmware: Firmware, flags: &[String]) -> Result<()> {
    let mut hardware = false;
    let mut trace = false;
    let mut programmer = None;
    let mut arguments = flags.iter();
    while let Some(flag) = arguments.next() {
        match flag.as_str() {
            "--hardware" if !hardware => hardware = true,
            "--trace" if !trace => trace = true,
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
    if trace && !matches!(firmware, Firmware::Stm32Cube | Firmware::FreeRtos) {
        return Err("--trace supports stm32cube and freertos".into());
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
    let stages = ["build", "analyze", "simulate"]
        .into_iter()
        .chain(trace.then_some("trace"))
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
        } else if stage == "trace" {
            let mut command = Command::new("tools/check-tonbandgeraet.sh");
            command.arg(name).arg(directory.join("trace"));
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
            Ok(()) => "passed",
            Err(error) => {
                failed_stage = Some((stage, error));
                "failed"
            }
        };
        let elapsed = stage_start.elapsed().as_millis();
        writeln!(report, "{stage}\t{status}\t{elapsed}\t{log_name}")?;
    }

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
