#!/usr/bin/env python3
"""Join ClickForge, SDK build, and BoardForge results without mixing firmware."""

import argparse
from collections import Counter
import json
from pathlib import Path


def load(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise ValueError(f"{path}: {error}") from error


def combine(corpus, build_indexes, simulation_reports):
    for document in (corpus, *build_indexes, *simulation_reports):
        if document.get("schema_version") != 1:
            raise ValueError("unsupported evidence schema version")
    drivers = {
        name: {
            "driver_sha256": item.get("driver_sha256"),
            "intake": item["status"],
            "parsed": "parsed" in item,
            "model": "ready" if item.get("scenario") and item["status"] == "ready"
                     else "unsupported"
                     if item["status"] == "unsupported" else "unavailable",
            "builds": {},
        }
        for name, item in corpus["drivers"].items()
    }
    for index in build_indexes:
        if index["sdk_revision"] != corpus["sdk_revision"]:
            raise ValueError("build index and ClickForge inventory have different SDK revisions")
        for name, build in index["drivers"].items():
            if name not in drivers:
                raise ValueError(f"build {name} is outside the ClickForge inventory")
            entry = drivers[name]
            if build.get("driver_sha256") != entry["driver_sha256"]:
                raise ValueError(f"build {name} does not match the audited SDK driver hash")
            toolchain = build["toolchain"]
            if toolchain in entry["builds"]:
                raise ValueError(f"duplicate build for {name}/{toolchain}")
            entry["builds"][toolchain] = {
                "stages": build["stages"],
                "compiler": build["compiler"],
                "example_sha256": build.get("example_sha256"),
                "elf_sha256": build.get("elf_sha256"),
                "simulation": "not_run" if entry["model"] == "ready" else entry["model"],
                "physical": "not_run",
            }
    standalone = []
    for sim in simulation_reports:
        name = sim["driver"]
        if name is None:
            standalone.append({"device": sim["device"], "elf_sha256": sim["sha256"]["firmware"],
                               "cases": sim["cases"]})
            continue
        if name not in drivers:
            raise ValueError(f"simulation {name} is outside the ClickForge inventory")
        entry = drivers[name]
        if not entry["driver_sha256"] or sim["driver_sha256"] != entry["driver_sha256"]:
            raise ValueError(f"simulation {name} does not match the audited SDK driver hash")
        matches = [build for build in entry["builds"].values()
                   if build["elf_sha256"] == sim["sha256"]["firmware"]
                   and build["stages"]["artifacts"] == "passed"]
        if len(matches) != 1:
            raise ValueError(f"simulation {name} does not identify exactly one successful ELF build")
        (build,) = matches
        if build["simulation"] != "not_run":
            raise ValueError(f"duplicate or unsupported simulation for {name}")
        cases = {case["id"]: case["status"] for case in sim["cases"]}
        if len(cases) != len(sim["cases"]):
            raise ValueError(f"duplicate case in the simulation of {name}")
        build["physical"] = cases.pop("physical_comparison", "not_run")
        if build["physical"] != "not_run" and not sim["sha256"].get("bench_report"):
            raise ValueError(f"physical comparison for {name} has no bench capture hash")
        if not cases or not set(cases.values()) <= {"passed", "failed", "error", "timeout"}:
            raise ValueError(f"simulation {name} has invalid or missing firmware cases")
        build["simulation"] = next(status for status in ("error", "failed", "timeout", "passed")
                                   if status in cases.values())
        build["simulation_cases"] = cases

    builds = [build for entry in drivers.values() for build in entry["builds"].values()]
    return {
        "schema_version": 1,
        "sdk_revision": corpus["sdk_revision"],
        "counts": {
            "drivers": len(drivers),
            "parsed": sum(item["parsed"] for item in drivers.values()),
            "model_ready": sum(item["model"] == "ready" for item in drivers.values()),
            "driver_compile": dict(Counter(build["stages"]["driver_compile"] for build in builds)),
            "example_compile": dict(Counter(build["stages"]["example_compile"] for build in builds)),
            "link": dict(Counter(build["stages"]["link"] for build in builds)),
            "simulation": dict(Counter(build["simulation"] for build in builds)),
            "physical": dict(Counter(build["physical"] for build in builds)),
        },
        "drivers": drivers,
        "standalone": standalone,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus-report", type=Path, required=True)
    parser.add_argument("--build-index", type=Path, action="append", required=True)
    parser.add_argument("--simulation", type=Path, action="append", default=[])
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = combine(load(args.corpus_report), list(map(load, args.build_index)),
                         list(map(load, args.simulation)))
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + "\n")
    except (KeyError, TypeError, ValueError, OSError) as error:
        parser.exit(1, f"Cannot join SDK coverage: {error}\n")
    print(json.dumps(report["counts"], indent=2))


if __name__ == "__main__":
    main()
