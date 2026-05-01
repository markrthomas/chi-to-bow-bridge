# Verilator testbench environment (`vlate_bench`)

This directory mirrors the **intent** of `uvm_bench` using **Verilator**: the DUT hierarchy is modeled in Verilog as **`tb_top`**, and stimulus, monitoring, and checking are implemented in **C++** (`tb_main.cpp`, `chi_tb.hpp`). Verilator does **not** execute UVM; the UVM roles are recreated as ordinary C++ functions and a small scoreboard class.

## What it verifies

The same **integration** directed suite as UVM + Cocotb **`integration/test_integration.py`**:

- **DUT hierarchy:** `chi_to_bow_integration_top` ( `chi_to_bow_bridge` + `bow_link_partner_bfm` ).
- **Stimulus:** **Single-beat** read (`0x1000`, `txnid` **0x2A**) then write (`0x2000`, `txnid` **0x2B**, data `0xDEADBEEF00000099`) with ~500 ns idle between; then **burst** write (3 beats, `txnid` 0x71) and read (4 beats, `txnid` 0x72); then **illegal CHI REQ** cases (response opcodes **0x2** / **0x3** on the request channel, txnids **0x01** / **0x02**) asserting **`err_pulse`** and **`err_illegal_req_hdr`**, matching **`chi_illegal_req_test`** / Cocotb (**no** scoreboard expectation for illegal rows).
- **Checks:** `chi_tb::scoreboard` for legal traffic (same rules as `uvm_bench/uvm/chi_tb_pkg.sv`, including **`exp_read_data(txnid)`** for read completions).

## OSS lint-only

**`make lint`** runs **`verilator --lint-only -Wall -Wno-fatal`** on `sim.f` (bridge + integration + `tb_top.sv`) so CI can gate RTL without compiling the C++ shim.

## Prerequisites

- **Verilator** (e.g. 5.x) on `PATH`.
- A C++17-capable toolchain (Verilator’s generated `Makefile` invokes the system compiler).

## Layout

| Path | Role |
|------|------|
| `sim.f` | Verilog file list (paths relative to **`vlate_bench/`**). |
| `tb_top.sv` | Top module: all CHI and clock/reset pins are **ports** so C++ can drive/sample them; instantiates `chi_to_bow_integration_top`. |
| `tb_main.cpp` | **`drive_until_accept`**, **`drive_illegal_req_phase`**, **`sampling_posedge_rsp`**, reset, read/write smoke, burst choreography, **`err_illegal_*`** checks, **`run_clock_only`**. Address/data literals use **`static_cast<std::uint64_t>(0x...)`** (avoid `ULL` on hex tokens for portability). |
| `chi_tb.hpp` | Types (`chi_exp_item`, `chi_obs_item`), **`exp_read_data()`**, and **`scoreboard`** (expectation queue vs observed responses). |
| `Makefile` | Verilator **`lint`** (RTL-only), **`run`** / **`clean`** / **`pdf`** (README → PDF via Pandoc). |

### PDF of this document

From **`vlate_bench/`** (requires [Pandoc](https://pandoc.org/) on `PATH`, same as **`docs/`**):

```bash
make pdf
```

Produces **`README.pdf`**. Remove it with `make clean-pdf` (or `make clean`, which also removes `obj_dir` and logs).

The repository **root** `make docs` also builds this PDF (and **`uvm_bench/README.pdf`**).

## How to run

From **`vlate_bench/`**:

```bash
make run
```

Fresh build and run (default target builds `obj_dir/Vtb_top` then executes it):

```bash
make clean && make run
```

Or run the binary directly after a successful Verilator build:

```bash
./obj_dir/Vtb_top
```

Commands should be run **from `vlate_bench/`** so `sim.f` paths (`../src/...`, etc.) resolve.

```bash
make clean   # removes obj_dir and common logs/traces
```

### Manual Verilator invocation

```bash
verilator -Wall -Wno-fatal \
  --cc --exe --build -j 0 \
  --top-module tb_top \
  --timescale 1ns/1ps \
  -Mdir obj_dir \
  -o Vtb_top tb_main.cpp -f sim.f
./obj_dir/Vtb_top
```

## Mapping to `uvm_bench`

| UVM concept | Verilator analogue |
|-------------|---------------------|
| `chi_integration_if` | `Vtb_top` port members (`clk`, `rst_n`, `chi_req_*`, `chi_rsp_*`, …) |
| `chi_driver::drive_until_accept` | `drive_until_accept()` |
| `chi_rsp_monitor` | `sampling_posedge_rsp()` each time the clock rises |
| `chi_scoreboard` | `chi_tb::scoreboard` |
| `chi_smoke_seq` + `chi_burst_smoke_seq` | Read-then-write smoke, then burst phases in `main()` with clock-only pacing between |
| `chi_illegal_req_test` | `drive_illegal_req_phase()` (no scoreboard `write_exp`) |
| `chi_smoke_test` / `chi_burst_test` drain | `run_clock_only(..., 2500)` after illegal checks (covers smoke, burst responses, drains) |

Clocking is **two half-cycles per period** (toggle `clk` 0 → 1 → 0) with **10 ns** period, matching the UVM `tb_top` style (`always #5 clk = ~clk`).

## Verilator notes

- The repository RTL is **unchanged**; Verilator may emit **warnings** (e.g. width expansion in `bow_link_partner_bfm`, procedural/init style in `chi_to_bow_bridge`). The Makefile uses **`-Wno-fatal`** so builds continue; tighten or waive locally as your policy requires.
- Tracing (VCD/FST) is **not** enabled in the default `Makefile`; add `--trace` and link the appropriate Verilator trace support if you need waveforms.

## Related project docs

- Design and BoW framing: **`docs/design_spec.md`**
- Cocotb tests: **`test/`**; UVM twin: **`uvm_bench/README.md`**
