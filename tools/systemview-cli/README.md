# SystemView CLI

This Rust tool reads SEGGER SystemView recordings and produces JSON for scripts and agents. It runs without Qt, a display server, or the SEGGER desktop executable. Run the commands below from the UNI Clicker repository root.

```sh
cargo build --locked --manifest-path tools/systemview-cli/Cargo.toml --target-dir build/systemview-cli
cli=build/systemview-cli/debug/systemview-cli

"$cli" summary SystemView/Sample/Sample_Overflow.SVDat

"$cli" decode SystemView/Sample/FS_DeviceActivity.SVDat \
  --descriptions SystemView/Description --event FS_Init --limit 5

"$cli" decode SystemView/Sample/Sample_Multicore.SVDat \
  --core 1 --event print --limit 10
```

`decode` accepts a path or `-` for stdin and emits one JSON object per event. The `--event` filter accepts an event kind such as `overflow`, `task_start_exec`, or `print`, or an API symbol when the description files are available. `--limit` counts matching rows. `summary` emits one object containing the recording header, core metadata, event counts, and the number of dropped packets reported by the target.

Events include the source byte offset, per-core index, wire event ID, raw timestamp delta, and elapsed ticks since the first event on that core. `time_ns` uses the reported timestamp frequency once an initialization packet is available. Multicore output follows each stored core stream in order, with independent elapsed times. `systime_us` and `systime_cycles` expose the target clock readings for correlation.

Task and resource IDs retain their wire values. Initialization exposes the RAM base and ID shift used by firmware to encode them. API calls include raw payload bytes and, when available, the symbol and signature from the matching `SYSVIEW_*.txt` file. Terminal events include the text or format string and its raw arguments. `print_elf` exposes the recorded string address, options, and any remaining argument bytes. The CLI currently has no ELF or message-file lookup. Data samples include raw and typed values, and data registration events carry units and scaling metadata.

## Capture on the UNI Clicker

```sh
source tools/bench-env.sh
make cli
build/cli/debug/uni-cli systemview
build/cli/debug/uni-cli systemview --hardware
```

The first command runs the recorder firmware in Renode and saves the trace and RTT terminal bytes. The hardware run also flashes the demo with OpenOCD, captures channel 1 live over ST-LINK, and verifies the channel 0 terminal greeting from SRAM. Each run writes a directory under `.cache/verification/systemview.*` with the raw bytes, decoded events, summary, and provenance. [Bench setup and restore command](../../AGENT.MD#systemview-and-rtt)

## Capture from another instrumented target

```sh
mkdir -p .cache/systemview

# SystemView's firmware IP recorder
"$cli" capture 192.0.2.10:19111 --seconds 5 > .cache/systemview/trace.bin

# OpenOCD's TCP bridge for the SystemView RTT channel
"$cli" capture 127.0.0.1:9090 --transport rtt --seconds 5 > .cache/systemview/trace.bin

"$cli" decode .cache/systemview/trace.bin --descriptions SystemView/Description
```

Use the address of your instrumented target. For OpenOCD, start RTT with the control-block address or search range from the firmware ELF. Use `rtt channels` to identify the SystemView channel and expose that channel with `rtt server start 9090 CHANNEL` without a greeting. `--transport uart-bridge` expects a transparent bidirectional TCP bridge to a UART using the SEGGER recorder handshake. The CLI sends start, collects raw bytes for the requested interval, sends stop, and drains the socket for up to another 500 ms. [SEGGER user guide](https://doc.segger.com/UM08027_SystemView.html) · [OpenOCD RTT commands](https://openocd.org/doc/html/General-Commands.html#Real-Time-Transfer-_0028RTT_0029)

The existing UNI Clicker Tonbandgeraet captures use their own format. Live SystemView recording requires SystemView instrumentation in the firmware. A raw RAM snapshot must begin on a packet boundary or at a sync marker and use the correct ring-buffer order.

## Artifact analysis

| Resource | Findings |
| --- | --- |
| `SystemView_Linux_V410b_x86_64.deb` | amd64 package version `4.102`, with desktop release V4.10b. It contains the stripped x86-64 ELF, Qt 4.8.7, launcher and MIME assets, license texts, docs, descriptions, and samples. The ELF uses an `$ORIGIN` library search path. Extracting the package avoided executing its installation scripts. |
| `SystemView_Windows_V410b_x64.exe` | 32-bit NSIS installer containing a 64-bit viewer, Qt libraries, installer assets, licensing files, and the same manuals, descriptions, and recordings. |
| `SystemView.exe`, `QtCore4.dll`, `QtGui4.dll`, `Uninstall.exe` | The viewer and Qt libraries match the Windows installer payload byte for byte. The viewer imports Qt, Windows device APIs, and the Visual C++ runtime. The separate uninstaller is NSIS and contains setup assets. The bundled third-party notices identify Qt under LGPL 2.1. |
| `UM08027_SystemView.html`, `UM08027_SystemView.pdf`, `Doc/` | The two manuals in PDF are identical 253-page copies of UM08027 V4.10. The HTML guide provides searchable recorder, command-line, and description-file documentation. The release notes identify the V4.10b license configuration fix. V4.10 introduced ELF-backed print strings and project-level message files. |
| `Description/` | All 14 text catalogs match the installers after line-ending normalization. They cover FreeRTOS, Micrium OS, ThreadX, Zephyr, embOS and embOS Ultra, uC/OS-II and III, emFile, emSSL, and embOS/IP. `emFile_1` duplicates `emFile`. `embOSIP_32000` duplicates the unversioned catalog, while `embOSIP_30800` differs. The CLI uses the numeric API rows for names and signatures. |
| `Sample/` | All eight recordings are byte-identical across the supplied copies. They exercise several format generations, single and multicore traces, module APIs, terminal output, overflows, and sampled data. |

Binary inspection covered the package contents, ELF/PE imports, symbol availability, and viewer strings for recording and export. The Linux viewer has dynamic imports but its internal symbols are stripped. Its documented `-load` and `-export` options automate the Qt application. A launch under Xvfb reached a license dialog before CSV export. The bundled desktop licenses restrict decompilation. The recorder source and sample analysis supplied the needed interoperability information, so binary analysis ended at inspection. [SEGGER user guide](https://doc.segger.com/UM08027_SystemView.html)

### Format and provenance

- Sample `.SVDat` files have a semicolon-delimited text header followed by native packets. The decoder accepts LF and CRLF. Multicore `Offset CoreN` entries locate separate streams relative to the end of the header.
- The packet stream uses unsigned base-128 integers and a delta timestamp at the end of each packet. IDs 0–23 use an implied payload layout. IDs 24 and above carry a payload length. Counted strings use one length byte or a `0xff` escape with a two-byte big-endian length. Sync markers contain ten zero bytes. The oldest sample starts directly with a trace-start packet.
- The public firmware sources define three relevant wire paths. The IP sample exchanges 32-byte greetings and length-prefixes host commands. The serial recorder exchanges four-byte `SV` greetings. An RTT bridge forwards the command and packet bytes directly. [SystemView target source at `92ca7a8`](https://github.com/SEGGERMicro/SystemView/tree/92ca7a810c5765ba64911919acd511c61b6b083f) · [RTT source at `9106eaa`](https://github.com/SEGGERMicro/RTT/tree/9106eaa39babe53e00994d7828c1afb29390cdc1)

## Verification

| Bundled recording | Packets decoded |
| --- | ---: |
| FS_DeviceActivity | 208 |
| FS_Performance | 81,140 |
| OS_IP_WebServer | 43,466 |
| OS_Start_LEDBlink | 11,208 |
| Sample_DataPlot | 151,219 |
| Sample_Multicore | 22,220 / 4,982 / 158,135 by core |
| Sample_Overflow | 701 |
| uCOS_Start | 11,520 |

The eight sample summaries cover 484,799 event packets. The overflow sample contains four overflow packets reporting 71 drops. A local TCP harness built with SEGGER's public firmware encoder and RTT library exercised all three capture modes. Each produced the same 148 bytes and 14 events, including trace start and stop, an ISR, a task switch, a print, and an API call and return. Decoding of those events was checked against the values emitted by the harness.

The package extractions, test harness, captures, and sample summaries are under `.cache/systemview/`. The UNI Clicker demo passed with three markers in Renode and eight in a two-second ST-LINK capture. Both recordings measured 250 ms between markers and zero dropped events. [Bench results](../../docs/verification.md#segger-systemview-and-rtt)
