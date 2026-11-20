#!/usr/bin/env python3
"""Compile unmodified Click libraries and examples for UNI Clicker socket 1."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "examples/necto-click"
COHORT = ADAPTER / "cohort.json"
PILOT = ADAPTER / "pilot64.json"
CACHED_SOURCES = ROOT / ".cache/vendor"
DRIVER = re.compile(r"[a-z0-9_]+")
INCLUDES = re.compile(rb'^\s*#\s*include\s*[<"]([a-z0-9_]+)\.h[>"]', re.MULTILINE)
POSITIONS = re.compile(rb'^\s*#\s*define\s+MIKROBUS_POSITION_\w+\s+MIKROBUS_(\d+)\b', re.MULTILINE)

# Low-level variants selected by the SDK's STM32F7 CMake rules.
PERIPHERALS = {
    "i2c_master": ("i2c", "i2c", "implementation_2", "hal_ll_i2c_master",
                   ["__hal_ll_i2c_subset_2__"]),
    "spi_master": ("spi", "spi_master", "implementation_1", "hal_ll_spi_master",
                   ["__hal_ll_spi_master_subset_1__"]),
    "uart": ("uart", "uart", "implementation_2", "hal_ll_uart", []),
    "analog_in": ("adc", "adc", "implementation_1/subimplementation_1", "hal_ll_adc", [
        "HAL_LL_ADC_RESOLUTION_CMAKE=HAL_LL_ADC_RESOLUTION_12_BIT",
        "HAL_ADC_RESOLUTION_CMAKE=HAL_ADC_RESOLUTION_12_BIT",
        "ANALOG_IN_RESOLUTION_CMAKE=ANALOG_IN_RESOLUTION_12_BIT",
    ]),
    "pwm": ("pwm", "tim", "implementation_1", "hal_ll_tim", []),
    "one_wire": ("one_wire", "one_wire", "", "hal_ll_one_wire", ["MACRO_USAGE_ONE_WIRE"]),
}
GPIO = {"digital_in", "digital_out", "port"}
SHAPE_FLAGS = [
    "-mcpu=cortex-m7", "-mthumb", "-mfloat-abi=soft", "-g3", "-Og",
    "-ffunction-sections", "-fdata-sections", "-DSTM32F746xx", "-DSTM32F7xx",
    "-D__hal_ll_gpio_subset_1__", "-Wno-error=int-conversion",
    "-Wno-error=incompatible-pointer-types",
]
LINK_FLAGS = ["-nostartfiles", "-specs=nano.specs", "-specs=nosys.specs",
              "-Wl,--gc-sections,-z,noexecstack,-u,_printf_float"]


class BuildError(Exception):
    """A build stage returned an error that should appear in the report."""


def git(dir_path, *args):
    result = subprocess.run(["git", "-C", str(dir_path), *args],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    return result.stdout if result.returncode == 0 else None


def git_revision(dir_path):
    prefix = git(dir_path, "rev-parse", "--show-prefix")
    if prefix is None or prefix.strip() not in (b"", b"clicks/"):
        return None
    revision = git(dir_path, "rev-parse", "HEAD")
    return revision.decode().strip() if revision else None


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def driver_hash(files):
    # Match clickforge_parser::corpus::hash_click byte for byte.
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(path.name.encode("utf-8") + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def sdk_files(click):
    libs = sorted(lib for lib in click.glob("lib_*")
                  if (lib / "include").is_dir() and (lib / "src").is_dir())
    preferred = click / f"lib_{click.name}"
    lib = preferred if preferred in libs else libs[0] if len(libs) == 1 else None
    if lib is None:
        raise BuildError("no uniquely identifiable SDK library with include/ and src/")
    headers = sorted((lib / "include").glob("*.h"))
    sources = sorted((lib / "src").glob("*.c"))
    primary = lib / "include" / f"{lib.name[4:]}.h"
    if not sources or (primary not in headers and len(headers) != 1):
        raise BuildError("missing primary header or C sources")
    return lib / "include", headers, sources


def dependencies(files):
    return {match.decode() for path in files for match in INCLUDES.findall(path.read_bytes())}


def run(command, log, cwd=ROOT, timeout=120):
    with log.open("a", encoding="utf-8") as stream:
        stream.write(f"$ {shlex.join(command)}\n")
        stream.flush()
        try:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=timeout, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise BuildError(str(error)) from error
        if result.returncode:
            raise BuildError(f"tool exited with {result.returncode}")


class Target:
    def __init__(self, args):
        self.sdk = args.sdk.resolve(strict=True)
        self.cube = args.cube.resolve(strict=True)
        windows = Path(os.environ.get("UNI_WINDOWS_ROOT", "/mnt/c/Users/gbast/dev/uni-clicker"))
        self.toolchain = args.compiler
        self.objcopy = os.environ.get("OBJCOPY", "arm-none-eabi-objcopy")
        self.cwd = ROOT
        self.cc = [os.environ.get("STM32_GCC", "arm-none-eabi-gcc")]
        if self.toolchain == "necto":
            self.cwd = Path(os.environ.get(
                "NECTO_WIN_GCC_ROOT",
                str(windows / "NECTOStudio7/packages/compilers/gcc/arm/gcc-arm-none-eabi"),
            )).resolve(strict=True) / "bin"
            self.cc = ["./arm-none-eabi-gcc.exe"]
        version = subprocess.check_output([*self.cc, "--version"], cwd=self.cwd, text=True,
                                          timeout=30)
        self.version = version.splitlines()[0]
        self.stm32 = self.sdk / "targets/arm/mikroe/stm32"
        self.common = self.stm32.parent / "common/include"
        cmsis = self.cube / "Drivers/CMSIS"
        self.device = cmsis / "Device/ST/STM32F7xx"
        self.includes = [
            ADAPTER, cmsis / "Include", self.device / "Include",
            self.stm32 / "include", self.stm32 / "include/gpio",
            self.common, self.common / "mcu_definitions/STM32/STM32F746ZGTx",
            self.common / "mcu_reg_addresses/STM32/STM32F746ZG",
            self.sdk / "hal/interface", self.sdk / "hal/lib/include", self.sdk / "drv/lib/include",
        ]
        self.pins = dict(re.findall(r"^#define MIKROBUS_1_MIKROBUS_(\w+)\s+GPIO_(\w+)",
                                    (ADAPTER / "board.h").read_text(), re.MULTILINE))
        self.provenance = {
            "target": "stm32f746zg",
            "board": "uni-clicker",
            "socket": 1,
            "pins": self.pins,
            "compiler": self.version,
            "toolchain": self.toolchain,
            "mikrosdk_revision": git_revision(self.sdk),
            "stm32cube_revision": git_revision(self.cube),
        }
        manifest = self.sdk / "manifest.json"
        if manifest.is_file():
            self.provenance["mikrosdk_manifest_sha256"] = sha(manifest)
            version = json.loads(manifest.read_text()).get("sdk-version")
            if version and not version.startswith("${"):
                self.provenance["mikrosdk_version"] = version

    def path(self, path):
        if self.toolchain == "necto":
            return subprocess.check_output(["wslpath", "-m", str(path)], text=True).strip()
        return str(path)

    def config(self, out, include, modules, imports):
        includes = [out, include, *self.includes]
        sources = [
            ADAPTER / "board.c", self.stm32 / "src/gpio/hal_ll_gpio.c",
            self.stm32 / "src/gpio/implementation_1/hal_ll_gpio_port.c",
            self.device / "Source/Templates/gcc/startup_stm32f746xx.s",
            self.device / "Source/Templates/system_stm32f7xx.c",
            ROOT / "firmware/startup_support.c",
        ]
        if modules & GPIO:
            sources.append(self.sdk / "hal/lib/src/lib_hal_gpio/hal_gpio.c")
        defines = []
        for module in sorted(modules):
            if module in PERIPHERALS:
                _, part, implementation, low_level, flags = PERIPHERALS[module]
                include_part = self.stm32 / "include" / part
                includes.append(include_part)
                if implementation:
                    includes.append(include_part / f"hal_ll_{part}_pin_map" / implementation)
                source_dir = self.stm32 / "src" / part / implementation
                if module == "one_wire":
                    includes.append(source_dir)
                    sources.append(ADAPTER / "one_wire_compat.c")
                else:
                    sources.append(source_dir / f"{low_level}.c")
                defines.extend(f"-D{flag}" for flag in flags)
                hal = "adc" if module == "analog_in" else module
                sources.append(self.sdk / "hal/lib/src" / f"lib_hal_{hal}" / f"hal_{hal}.c")
            if module in PERIPHERALS or module in GPIO:
                sources.append(self.sdk / "drv/lib/src" / f"lib_drv_{module}" / f"drv_{module}.c")
        if "uart" in modules:
            core = self.stm32.parent / "core"
            ring = self.sdk / "platform/ring/lib"
            includes.extend([core / "include", ring / "include"])
            sources.extend([
                core / "src/core/implementation_1/hal_ll_core.c",
                core / "src/stm32/m7/hal_ll_core_port.c",
                ring / "src/ring.c",
            ])
            # The vendor DLL/core toolchain uses UARTn names for the same
            # interrupt handlers exposed as USARTn in the CMSIS vector table.
            defines.extend(["-Dstm32", "-D__cortex_m7__"])
            defines.extend(f"-DUART{port}_IRQHandler=USART{port}_IRQHandler"
                           for port in (1, 2, 3, 6))
        if "conversions" in imports:
            conversions = self.sdk / "platform/conversions/lib"
            includes.append(conversions / "include")
            sources.append(conversions / "src/conversions.c")
            defines.extend(["-D__CONVERSIONS_CHIPS_16BIT_32BIT__", "-D__CONVERSIONS_SET__"])
        flags = [*SHAPE_FLAGS, *defines, *(f"-I{self.path(path)}" for path in includes)]
        return flags, sources

    def compile(self, flags, paths, out, log):
        out.mkdir(exist_ok=True)
        objects = []
        for index, path in enumerate(paths):
            obj = out / f"{index}-{path.stem}.o"
            run([*self.cc, *flags, "-include", "delays.h", "-include", "generic_pointer.h",
                 "-c", self.path(path), "-o",
                 self.path(obj)], log, self.cwd)
            objects.append(obj)
        return objects

    def link(self, flags, objects, support, out, log):
        script = self.path(ROOT / "firmware/stm32f746.ld")
        linked = out / "example.elf"
        map_file = self.path(out / "example.map")
        run([*self.cc, *flags, *LINK_FLAGS, f"-T{script}", f"-Wl,-Map,{map_file}",
             *(self.path(file) for file in [*objects, *support]), "-lm", "-o", self.path(linked)],
            log, self.cwd)
        return linked


def write_json(path, value):
    pending = path.with_suffix(".tmp")
    pending.write_text(json.dumps(value, indent=2) + "\n")
    pending.replace(path)


def build_driver(target, click, out, revision, expected_buses=None):
    out.mkdir(parents=True, exist_ok=True)
    log = out / "build.log"
    stages = dict.fromkeys(("intake", "driver_compile", "example_compile", "link", "artifacts"),
                           "not_run")
    result = {
        "schema_version": 1,
        "driver": click.name,
        "sdk_revision": revision,
        **target.provenance,
        "stages": stages,
        "build_log": log.name,
    }
    stage = "intake"
    with (out / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        log.write_text("")
        for old in ("example.elf", "example.map", "example.hex", "build.json"):
            (out / old).unlink(missing_ok=True)
        try:
            if not click.is_dir():
                stages[stage] = "missing_input"
                raise BuildError("SDK driver directory missing from the working tree")
            include, headers, drivers = sdk_files(click)
            result["driver_sha256"] = driver_hash([*headers, *drivers])
            example = click / "example/main.c"
            if example.is_file():
                result["example_sha256"] = sha(example)
            # Library and example both contribute SDK dependencies.
            files = [*headers, *drivers]
            if example.is_file():
                files.append(example)
            imports = dependencies(files)
            modules = {name.removeprefix("drv_") for name in imports if name.startswith("drv_")}
            buses = sorted(PERIPHERALS[module][0] for module in PERIPHERALS.keys() & modules)
            result["interfaces"] = buses
            result["sdk_modules"] = sorted(modules)
            if expected_buses is not None and buses != sorted(expected_buses):
                raise BuildError(f"SDK interface set {buses!r} differs from configured {expected_buses!r}")
            flags, support = target.config(out, include, modules, imports)
            flatten = (target.sdk / "cmake/InstallHeadersFlatten.cmake.in").read_text()
            (out / "flatten_me.h").write_text(flatten.replace(
                "@MACRO_LIST1@@MACRO_LIST2@", "#define FLATTEN_ME_LEVEL FLATTEN_ME_LEVEL_NONE"
            ))
            (out / "core_header.h").write_text("#include <stm32f7xx.h>\n")
            stages[stage] = "passed"

            stage = "driver_compile"
            objects = target.compile(flags, drivers, out / "driver-objects", log)
            stages[stage] = "passed"

            stage = "example_compile"
            if not example.is_file():
                stages[stage] = "missing_input"
                raise BuildError("SDK example/main.c missing")
            positions = {position.decode() for position in POSITIONS.findall(example.read_bytes())}
            if positions - {"1"}:
                stages[stage] = "mapping_missing"
                raise BuildError("SDK example requires a socket beyond the verified socket 1 map")
            objects.extend(target.compile(flags, [example], out / "example-objects", log))
            stages[stage] = "passed"

            stage = "link"
            unsupported = modules - PERIPHERALS.keys() - GPIO
            if unsupported:
                stages[stage] = "unsupported_sdk_module"
                raise BuildError(f"STM32F746 adapter needs SDK support for {', '.join(sorted(unsupported))}")
            linked = target.link(flags, objects, support, out, log)
            stages[stage] = "passed"

            stage = "artifacts"
            run([target.objcopy, "-O", "ihex", str(linked), str(out / "example.hex")], log)
            result["elf"] = linked.name
            result["elf_sha256"] = sha(linked)
            stages[stage] = "passed"
        except (BuildError, OSError, subprocess.SubprocessError) as error:
            if stages[stage] == "not_run":
                stages[stage] = "failed"
            result["detail"] = str(error)
        write_json(out / "build.json", result)
    return result


def corpus_selection(corpus, cases, all_boards, cohort):
    corpus = corpus.resolve(strict=True)
    direct = corpus / "clicks"
    root = direct if direct.is_dir() else corpus
    if all_boards:
        names = {child.name for child in root.iterdir() if child.is_dir()}
        # Include omitted directories when the SDK checkout is sparse.
        prefix = git(root, "rev-parse", "--show-prefix")
        if prefix is not None:
            relative = prefix.decode().rstrip("\r\n/")
            tree = "HEAD:" + relative if relative else "HEAD"
            entries = git(root, "ls-tree", "--full-tree", "-d", "-z", "--name-only", tree)
            if entries:
                names.update(entries.decode().rstrip("\0").split("\0"))
    else:
        names = set(cases or cohort)
    for name in names:
        if not DRIVER.fullmatch(name):
            raise BuildError(f"invalid SDK driver ID {name!r}")
    return root, sorted(names)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=CACHED_SOURCES / "mikrosdk-click-v2")
    parser.add_argument("--sdk", type=Path, default=Path(os.environ.get(
        "NECTO_SDK_ROOT", str(CACHED_SOURCES / "mikrosdk-v2"),
    )))
    parser.add_argument("--cube", type=Path, default=Path(os.environ.get(
        "STM32CUBE_F7", str(CACHED_SOURCES / "STM32CubeF7"),
    )))
    parser.add_argument("--compiler", choices=("gcc", "necto"), default="gcc")
    parser.add_argument("--out", type=Path, required=True)
    select = parser.add_mutually_exclusive_group()
    select.add_argument("--case", action="append", help="One or more SDK driver IDs")
    select.add_argument("--all", action="store_true", help="Process the complete SDK inventory")
    select.add_argument("--pilot", action="store_true", help="Run the pinned 64-driver build sample")
    parser.add_argument("--shard", type=int, default=0)
    parser.add_argument("--shards", type=int, default=1)
    args = parser.parse_args()
    if not 0 <= args.shard < args.shards:
        parser.error("--shard must index one of --shards")
    try:
        cohort = json.loads(COHORT.read_text())
        pilot = json.loads(PILOT.read_text()) if args.pilot else None
        cases = list(pilot["drivers"]) if pilot else args.case
        root, names = corpus_selection(args.corpus, cases, args.all, cohort)
        if pilot and git_revision(root) != pilot["sdk_revision"]:
            raise BuildError("the 64-driver sample requires the SDK revision in its selection manifest")
        if not names:
            raise BuildError("SDK selection contains no drivers")
        target = Target(args)
    except (BuildError, OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"{error}\n")
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    revision = git_revision(root)
    results = {}
    for name in names[args.shard::args.shards]:
        report = build_driver(target, root / name, out / name, revision, cohort.get(name))
        results[name] = report
        print(f"{name}: {report['stages']} {report.get('detail', '')}", flush=True)
    index = "build-index.json" if args.shards == 1 else f"build-index-{args.shard}.json"
    write_json(out / index, {
        "schema_version": 1, "sdk_revision": revision, "shard": args.shard, "shards": args.shards,
        "drivers": results,
    })
    return int(any(report["stages"]["artifacts"] != "passed" for report in results.values()))


if __name__ == "__main__":
    sys.exit(main())
