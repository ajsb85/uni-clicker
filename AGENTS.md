# Working on the UNI Clicker lab

- Run `make <toolchain>` and `build/cli/debug/uni-cli analyze <toolchain>` after a firmware change. Keep ELF and BIN paired from the same build.
- Run `tools/simulate.sh <toolchain>` for byte-level UART coverage without a probe. Keep build products under `build/` and local logs, caches, and hardware backups under `.cache/`.
- Run the hardware workflow in sequence. Flash with CubeProgrammer, start OpenOCD, run `uni-cli verify`, then close OpenOCD before programming the next image.
- Record the tool versions and observations in `docs/verification.md`. A successful simulated UART transcript and a physical SWD result measure different parts of the workflow.
- During a debugger failure, compare the ELF vectors with target flash first. Then check the reset PC and MSP, the source entry breakpoint, the fault registers, and the peripheral and SRAM state.
