# Parcore
This repo contains a parquet reader accelerator which is deployed on FPGAs using th Coyote v2 shell.

## Stack
- Shell: Coyote v2 (git submodule at `libstf/coyote/`)
- Target: Alveo U55C, `-DFDEV_NAME=u55c`
- Tools: Vivado + Vitis HLS 2024.2. Always `source /mnt/labstore/Xilinx/Vivado/2024.2/settings64.sh` first.
- Host: C++17, CMake >= 3.5
- User logic language: SystemVerilog

## Layout
- `hardware/src/` — our vFPGA user logic (`vfpga_top.svh` is the entry point)
- `hardware/CMakeLists.txt` — hardware build config (services, #vFPGAs, apps)
- `software/src/` — host application using the Coyote C++ API (`cThread`)
- `sim/` — testbenches / Coyote simulation target
- `libstf/` — library for common hardware modules.
- `libstf/coyote/` — upstream shell. **Do not edit.** See "Boundaries".

## Build
Hardware builds (slow: <~N> hours; see Boundaries before running):
```
mkdir -p build_hw && cd build_hw
cmake ../hardware -DFDEV_NAME=u55c
make project      # create Vivado project
make bitgen       # synthesis + implementation + bitstream
```
Software (fast; OK to run freely):
```
mkdir -p build_sw && cd build_sw
cmake ../sw && make
```
The server does not have any FPGAs so running the build design needs to happen out-of-band.
This will be done manually by the user.

## Verification (preferred over hardware builds)
- Simulation: Coyote unit tests. Python `unittest` cases drive the vFPGA in an xsim project
  that `make sim` creates; each test is one simulation run (~15–75 s). Run from the repo root
  (ParCore tests, `hardware/unit-tests/`) or from `libstf/` (libSTF tests,
  `libstf/hardware/unit-tests/`); the commands are the same in both:
```
source /mnt/labstore/Xilinx/Vivado/2024.2/settings64.sh
./scripts/setup_simulation.sh      # (re)creates hardware/build-sim: cmake .. && make sim
set -a && source .env && set +a    # PYTHONPATH: build-sim/coyote_test, Coyote sim, unit-tests
python3 -m unittest discover -v -s ./hardware/unit-tests -p "*_test.py" -k <TestClass or test>
```
  - Rerun `setup_simulation.sh` after adding or renaming HDL files; edits to existing files are
    picked up by the next test run.
  - `setup_simulation.sh` calls `/usr/bin/cmake`, which this server does not have. Build the
    project by hand with any CMake >= 3.5 instead:
    `mkdir -p hardware/build-sim && cd hardware/build-sim && cmake .. && make sim`.
  - A test class selects its wiring with `alternative_vfpga_top_file` (relative to the unit-test
    folder, e.g. `vfpga_tops/typed_dict_test.sv`); otherwise `hardware/src/vfpga_top.svh` is used.
  - Output of the last run: `sim.out` and `diff/` in the unit-test folder.
  - All tests share `build-sim/sim`: never run two test processes on one build at once.
  - A unit-test folder outside the repo works too: `cmake .. -DUNIT_TEST_DIR=<dir>` and put that
    folder (instead of `hardware/unit-tests`) on `PYTHONPATH`.
  - `/run-hw-tests [filter]` wraps the ParCore command with `timeout 2m`, which is too short for
    more than a handful of tests.
Software (fast; OK to run freely):
```
mkdir -p build_sim && cd build_sim
cmake ../sw -DENABLE && make
```
- HLS C-sim: `<command>`.
- Lint: `<verilator --lint-only ... | slang ...>`.
- A change is not "done" until simulation passes.

## Coding conventions
- Stream interfaces are 512-bit AXI4-Stream; respect `tvalid/tready` handshakes.
  Never drop data when `tready` is low.
- Reset: <active-low `aresetn`, synchronous>. Clock: <name / frequency target>.
- FIFO depths and pipeline stages get a short comment only when the value
  isn't obvious (e.g. "depth covers 64-cycle HBM read latency").
- CSRs: keep the register map in `<file>` in sync with `setCSR/getCSR` offsets
  in `sw/`. Change both together or neither.
- HLS: pragmas explicit (`INTERFACE`, `PIPELINE II=`); no dynamic allocation.
- Host code: <style, e.g. clang-format config at repo root>.

## Comments
- Comments describe what the code does and why, never how it came to be.
- No history or process comments: no "changed X to Y", "fixed bug",
  "now uses...", "updated per request", "previously...", or "NEW:".
  That belongs in the commit message.
- Don't comment what the code already says (`// increment counter`).
- Don't add comments to code you didn't otherwise change.
- Explain changes in chat or the commit message, not in the source.

## Gotchas
- The build flow reuses design checkpoints. After HW changes that don't show
  up in the bitstream, delete `build_hw/checkpoints/shell` and
  `build_hw/checkpoints/config_*` and rebuild.
- Changing services in `hw/CMakeLists.txt` (RDMA, TCP, memory) requires a
  full shell rebuild, not just an app rebuild.
- Host buffers must come from Coyote allocation (`getMem`, hugepages) for DMA.
- Timing failures: check `build_hw/.../reports/` before changing logic.
- <Add project-specific traps here as you discover them.>

## Boundaries
- Never start `make bitgen`/synthesis/implementation without asking me first.
- Never run `insmod`, `rmmod`, card programming, or other `sudo` commands
  without asking. These can hang the host.
- Don't modify anything under `coyote/`. If the shell seems wrong, explain the
  issue and propose a patch instead.
- Don't change interface widths, clock domains, or the CSR map without flagging it.
- Don't "fix" timing by removing pipeline stages or registers.

## More context (read when relevant)
- Architecture notes: @docs/architecture.md
- Register map: @docs/registers.md
- Coyote examples for reference: `coyote/examples/`