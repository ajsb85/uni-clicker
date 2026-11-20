mod capture;
mod descriptions;
mod events;
mod packet;
mod recording;

use std::collections::BTreeMap;
use std::env;
use std::error::Error;
use std::fs;
use std::io::{self, BufWriter, Read, Write};
use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use serde_json::{Value, json};

use crate::capture::Transport;
use crate::descriptions::Descriptions;
use crate::events::State;
use crate::packet::Cursor;
use crate::recording::Recording;

const USAGE: &str = "systemview-cli reads SEGGER SystemView traces and emits JSON.

Usage:
  systemview-cli decode <file|-> [--core N] [--event NAME] [--limit N] [--descriptions DIR]
  systemview-cli summary <file|-> [--core N] [--descriptions DIR]
  systemview-cli capture <host:port> --seconds N [--transport ip|rtt|uart-bridge] > trace.bin

Decode emits one JSON object per event. NAME accepts an event kind or an API symbol.
Capture writes raw packets to stdout. Use rtt for an OpenOCD RTT channel socket.
";

#[derive(Default)]
struct DecodeOptions {
    core: Option<u32>,
    event: Option<String>,
    limit: Option<usize>,
    descriptions: Option<PathBuf>,
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            if error
                .downcast_ref::<io::Error>()
                .is_some_and(|e| e.kind() == io::ErrorKind::BrokenPipe)
            {
                return ExitCode::SUCCESS;
            }
            eprintln!("systemview-cli: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), Box<dyn Error>> {
    let mut args = env::args().skip(1);
    let Some(command) = args.next() else {
        print!("{USAGE}");
        return Ok(());
    };
    if matches!(command.as_str(), "-h" | "--help") {
        print!("{USAGE}");
        return Ok(());
    }
    if !matches!(command.as_str(), "decode" | "summary" | "capture") {
        return Err(format!("unknown command {command:?}. See --help.").into());
    }
    let input = args.next().ok_or("missing input. See --help.")?;
    if matches!(input.as_str(), "-h" | "--help") {
        print!("{USAGE}");
        return Ok(());
    }
    let mut out = BufWriter::new(io::stdout().lock());
    if command == "capture" {
        let mut duration = None;
        let mut transport = Transport::Ip;
        while let Some(flag) = args.next() {
            let value = args
                .next()
                .ok_or_else(|| format!("missing value for {flag}"))?;
            match flag.as_str() {
                "--seconds" => {
                    let seconds = value.parse::<u64>()?;
                    if seconds == 0 {
                        return Err("--seconds must be greater than zero".into());
                    }
                    duration = Some(Duration::from_secs(seconds));
                }
                "--transport" => match value.as_str() {
                    "ip" => transport = Transport::Ip,
                    "rtt" => transport = Transport::Rtt,
                    "uart-bridge" => transport = Transport::UartBridge,
                    _ => return Err("--transport must be ip, rtt or uart-bridge".into()),
                },
                _ => return Err(format!("unknown option {flag}").into()),
            }
        }
        capture::capture(
            &input,
            transport,
            duration.ok_or("missing --seconds")?,
            &mut out,
        )?;
        return Ok(());
    }

    let mut options = DecodeOptions::default();
    while let Some(flag) = args.next() {
        let value = args
            .next()
            .ok_or_else(|| format!("missing value for {flag}"))?;
        match flag.as_str() {
            "--core" => options.core = Some(value.parse()?),
            "--descriptions" => options.descriptions = Some(value.into()),
            "--event" if command == "decode" => options.event = Some(value),
            "--limit" if command == "decode" => options.limit = Some(value.parse()?),
            _ => return Err(format!("unknown option {flag} for {command}").into()),
        }
    }
    let bytes = if input == "-" {
        let mut bytes = Vec::new();
        io::stdin().lock().read_to_end(&mut bytes)?;
        bytes
    } else {
        fs::read(&input).map_err(|error| format!("{input}: {error}"))?
    };
    let descriptions = options
        .descriptions
        .as_deref()
        .map(|path| {
            Descriptions::load(path).map_err(|error| format!("{}: {error}", path.display()))
        })
        .transpose()?
        .unwrap_or_default();
    let recording = Recording::parse(&bytes)?;
    read_events(
        &recording,
        &descriptions,
        &options,
        command == "summary",
        &mut out,
    )?;
    out.flush()?;
    Ok(())
}

fn read_events(
    recording: &Recording<'_>,
    descriptions: &Descriptions,
    options: &DecodeOptions,
    summary: bool,
    out: &mut impl Write,
) -> Result<(), Box<dyn Error>> {
    let mut core_summaries = Vec::new();
    let mut emitted = 0;
    if let Some(id) = options.core
        && !recording.cores.iter().any(|core| core.id == id)
    {
        return Err(format!("recording has no core {id}").into());
    }
    for core in recording
        .cores
        .iter()
        .filter(|core| options.core.is_none_or(|id| core.id == id))
    {
        let mut cursor = Cursor::new(core.bytes);
        let mut state = State::default();
        let mut counts = BTreeMap::new();
        let mut count = 0u64;
        let mut ticks = 0u64;
        let mut dropped = 0u64;
        let mut time_ns = None;
        loop {
            if options.limit == Some(emitted) {
                return Ok(());
            }
            let Some(packet) = cursor
                .next_packet(core.offset)
                .map_err(|error| format!("core {} {error}", core.id))?
            else {
                break;
            };
            if count > 0 {
                ticks += u64::from(packet.delta);
            }
            let event = state.decode(&packet, descriptions);
            time_ns = state.timestamp_hz.and_then(|hz| {
                u64::try_from(u128::from(ticks) * 1_000_000_000 / u128::from(hz)).ok()
            });
            if summary {
                *counts.entry(event.kind).or_insert(0u64) += 1;
                dropped += event
                    .data
                    .get("dropped")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
            } else if options.event.as_deref().is_none_or(|name| {
                name == event.kind || event.data.get("symbol").and_then(Value::as_str) == Some(name)
            }) {
                write_json(
                    out,
                    &json!({
                        "core": core.id, "index": count, "offset": packet.offset, "event_id": packet.id,
                        "event": event.kind, "delta_ticks": packet.delta, "ticks": ticks,
                        "time_ns": time_ns, "data": event.data
                    }),
                )?;
                emitted += 1;
            }
            count += 1;
        }
        if summary {
            core_summaries.push(json!({
                "core": core.id, "offset": core.offset, "bytes": core.bytes.len(), "events": count,
                "counts": counts, "reported_dropped": dropped, "duration_ticks": ticks,
                "duration_ns": time_ns, "timestamp_hz": state.timestamp_hz, "cpu_hz": state.cpu_hz,
                "system": state.system, "tasks": state.tasks, "interrupts": state.interrupts,
                "resources": state.resources
            }));
        }
    }
    if summary {
        write_json(
            out,
            &json!({"header": recording.metadata, "cores": core_summaries}),
        )?;
    }
    Ok(())
}

fn write_json(out: &mut impl Write, value: &Value) -> io::Result<()> {
    serde_json::to_writer(&mut *out, value).map_err(|error| {
        error
            .io_error_kind()
            .map_or_else(|| io::Error::other(error.to_string()), io::Error::from)
    })?;
    writeln!(out)
}
