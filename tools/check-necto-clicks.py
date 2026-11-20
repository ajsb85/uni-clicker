#!/usr/bin/env python3
"""Run registered UNI Clicker firmware and external peripheral pairs under librenode."""

import argparse
import hashlib
import json
import math
import shutil
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PLATFORMS = ROOT / "sim/clicks"
COMPLETED = "Firmware regression completed"


def capture(command, log, timeout):
    with log.open("wb") as output:
        try:
            subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                           stdout=output, stderr=subprocess.STDOUT,
                           timeout=timeout, check=True)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            raise SystemExit(f"{error}. See {log}") from error


def monitor_path(path):
    name = str(path)
    if any(char in name for char in ('\\', '\r', '\n')):
        raise ValueError(f"cannot quote Renode path {path}")
    return '"' + name.replace('"', '\\"') + '"'


def renode_commands(commands, register_log):
    for command in commands:
        if isinstance(command, str):
            yield command
            continue
        address = int(command["read_u32"], 0)
        file_path = json.dumps(str(register_log), ensure_ascii=False)
        # Embedded Renode can drop Monitor output from nested include commands.
        # The file preserves register evidence for both launchers.
        python = ("from System.IO import File; "
                  f"File.AppendAllText({file_path}, "
                  f"str(monitor.Machine.SystemBus.ReadDoubleWord({address:#x})) + chr(10))")
        yield f"python {monitor_path(python)}"


def select_firmware(case, definition, compiler, out, build_index):
    if driver := definition.get("driver"):
        if not build_index:
            sdk_build = out / "sdk"
            capture([ROOT / "tools/build-click-sdk.py", "--case", driver, "--compiler", compiler,
                     "--out", sdk_build], out / "build-command.log", 180)
            build_index = sdk_build / "build-index.json"
        builds = json.loads(build_index.read_text())["drivers"]
        build = builds.get(driver)
        if not build or build["toolchain"] != compiler or build["stages"]["artifacts"] != "passed":
            raise SystemExit(f"No passing {compiler} build for {driver} in {build_index}")
        firmware = build_index.parent / driver
        elf = firmware / "example.elf"
        if not elf.is_file() or hashlib.sha256(elf.read_bytes()).hexdigest() != build["elf_sha256"]:
            raise SystemExit(f"{driver} ELF does not match the SDK build index")
        shutil.copyfile(firmware / build["build_log"], out / "build.log")
        return elf, build["compiler"]
    capture([ROOT / "tools/build-necto-click.sh", case.stem, compiler], out / "build.log", 180)
    firmware = ROOT / "build/clicks" / case.stem / compiler
    return firmware / "example.elf", (firmware / "compiler.txt").read_text().splitlines()[0]


def verify(case, compiler, report, cli, renode, build_index):
    out = report / case.stem
    out.mkdir()
    definition = json.loads(case.read_text())
    elf, version = select_firmware(case, definition, compiler, out, build_index)
    provenance = {
        "case": case.stem,
        "compiler": version,
        "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest(),
    }
    (out / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")

    for run in definition["runs"]:
        log = out / f'{run["name"]}.log'
        uart = log.with_suffix(".uart")
        registers = log.with_suffix(".registers")
        script = log.with_suffix(".resc")
        uart_ports = {"usart6": (uart, run["uart"])}
        for port, expected in run.get("additional_uart", {}).items():
            uart_ports[port] = (log.with_suffix(f".{port}.uart"), expected)
        commands = []
        if model := run.get("model"):
            commands.append(f"include {monitor_path(ROOT / model)}")
        commands.extend([
            'mach create "uni-clicker"',
            f'machine LoadPlatformDescription {monitor_path(ROOT / run["platform"])}',
            f"sysbus LoadELF {monitor_path(elf)}",
            "cpu VectorTableOffset 0x08000000",
            *(f"sysbus.{port} CreateFileBackend {monitor_path(path)} true"
              for port, (path, _) in uart_ports.items()),
            *renode_commands(run["commands"], registers),
            'mach rem "uni-clicker"',
        ])
        if renode:
            commands.extend([f"python \"print('{COMPLETED}')\"", "quit"])
        script.write_text("\n".join(commands) + "\n")
        if renode:
            capture([renode, "--console", "--disable-gui", "--plain", script], log, 45)
            if COMPLETED not in [line.strip() for line in log.read_text().splitlines()]:
                raise SystemExit(f"{case.stem}/{run['name']} did not finish. See {log}")
        else:
            capture([cli, "renode-script", script], log, 45)
        if "register_words" in run:
            words = [int(line) for line in registers.read_text().splitlines()] if registers.exists() else []
            if words != run["register_words"]:
                raise SystemExit(f"{case.stem}/{run['name']} register mismatch: {words!r}. See {log}")
        for port, (path, expected) in uart_ports.items():
            observed = [line.strip() for line in path.read_text().splitlines()] if path.exists() else []
            if observed != expected:
                raise SystemExit(f"{case.stem}/{run['name']} {port} mismatch: {observed!r}. See {log}")
        print(f"{case.stem}/{run['name']} passed ({compiler})", flush=True)


def inventory(cases, corpus):
    tree = subprocess.check_output(
        ["git", "-C", corpus, "ls-tree", "-r", "--name-only", "HEAD:clicks"], text=True
    )
    files = set(tree.splitlines())
    examples = {
        path.split("/")[0] for path in files
        if path.endswith("/example/main.c") and path.count("/") == 2
    }
    registered = {driver for case in cases if (driver := json.loads(case.read_text()).get("driver"))}
    cohort = set(json.loads((ROOT / "examples/necto-click/cohort.json").read_text()))
    if missing := (registered | cohort) - examples:
        raise SystemExit(f"Missing corpus examples: {', '.join(sorted(missing))}")
    return {
        "upstream_examples": len(examples),
        "build_cohort": sorted(cohort),
        "registered_upstream_examples": sorted(registered),
        "unregistered_upstream_examples": sorted(examples - registered),
        "standalone_cases": sorted(case.stem for case in cases if case.stem not in registered),
    }


def compare_lan8651(simulation, hardware):
    sim = json.loads((simulation / "provenance.json").read_text())
    hardware_hash = (hardware / "firmware.sha256").read_text().split()[0]
    if sim["elf_sha256"] != hardware_hash:
        raise SystemExit("Simulation and SWD captures used different firmware ELF files")

    physical = {
        key: int(value, 16)
        for key, value in json.loads((hardware / "result.json").read_text()).items()
    }
    if physical["result"] != 0x86510000:
        raise SystemExit("The hardware did not report LAN8651 PASS")
    expected = [
        f"LAN8651 OA={physical['idver']:08X} ID={physical['devid']:08X} "
        f"protected={physical['protected_id']:08X}",
        f"LAN8651 RESET={physical['initial_status']:08X}/{physical['cleared_status']:08X}/"
        f"{physical['reset_status']:08X} IRQ={physical['initial_irq']}/"
        f"{physical['cleared_irq']}/{physical['acknowledged_irq']}",
        f"LAN8651 FOOTER={physical['footer']:08X}",
        "LAN8651 PASS",
    ]
    observed = (simulation / "control.uart").read_text().splitlines()
    if observed != expected:
        raise SystemExit(f"LAN8651 simulation and SWD results differ\nSimulation: {observed!r}\nHardware: {expected!r}")
    result = {"elf_sha256": hardware_hash, "matched": observed}
    (hardware / "parity.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"LAN8651 simulated UART and physical SWD results match. See {hardware / 'parity.json'}")


def main():
    cases = sorted(PLATFORMS.glob("*.json"))
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    matrix = commands.add_parser("matrix", help="emit the GitHub Actions shard matrix")
    matrix.add_argument("--per-job", type=int, default=20)
    catalog = commands.add_parser("inventory", help="report registered and unregistered upstream examples")
    catalog.add_argument("--corpus", type=Path, default=ROOT / ".cache/vendor/mikrosdk-click-v2")
    compare = commands.add_parser("compare-lan8651", help="compare the simulation and physical probe")
    compare.add_argument("simulation", type=Path, help="the lan8651 directory inside the simulation report")
    compare.add_argument("hardware", type=Path, help="the bench report directory")
    run = commands.add_parser("verify", help="build and run registered firmware")
    run.add_argument("--compiler", choices=("gcc", "necto"), default="gcc")
    run.add_argument("--case", choices=[case.stem for case in cases])
    run.add_argument("--build-index", type=Path, help="Use cohort ELFs for SDK-backed cases")
    run.add_argument("--renode", type=Path, help="Use the portable Renode executable")
    run.add_argument("--shard", type=int, default=0)
    run.add_argument("--shards", type=int, default=1)
    args = parser.parse_args()

    if args.command == "matrix":
        if args.per_job < 1:
            parser.error("--per-job must be positive")
        shards = max(1, math.ceil(len(cases) / args.per_job))
        print(json.dumps({"include": [{"shard": i, "shards": shards} for i in range(shards)]}))
        return
    if args.command == "inventory":
        print(json.dumps(inventory(cases, args.corpus), indent=2))
        return
    if args.command == "compare-lan8651":
        compare_lan8651(args.simulation, args.hardware)
        return
    if not 0 <= args.shard < args.shards:
        parser.error("--shard must index one of --shards")

    selected = [case for case in cases if args.case is None or case.stem == args.case]
    report_root = ROOT / ".cache/verification"
    report_root.mkdir(parents=True, exist_ok=True)
    report = Path(tempfile.mkdtemp(prefix=f"clicks.{args.compiler}.", dir=report_root))
    print(f"Click reports in {report}", flush=True)
    renode = args.renode.resolve(strict=True) if args.renode else None
    build_index = args.build_index.resolve(strict=True) if args.build_index else None
    if not renode:
        capture(["make", "cli"], report / "cli-build.log", 180)
    cli = ROOT / "build/cli/debug/uni-cli"
    results = {}
    for case in selected[args.shard::args.shards]:
        try:
            verify(case, args.compiler, report, cli, renode, build_index)
        except SystemExit as error:
            results[case.stem] = {"status": "fail", "detail": str(error)}
            print(error, flush=True)
        else:
            results[case.stem] = {"status": "pass"}
    (report / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    if any(result["status"] == "fail" for result in results.values()):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
