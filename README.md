# CHI to BoW Bridge (Starter)

This repository contains a starter Verilog bridge that packetizes simplified CHI
requests into BoW flits and reconstructs simplified CHI responses, plus a
**Cocotb** testbench, design documentation, and **optional** integration testbenches:
**UVM + Synopsys VCS** (`uvm_bench/`) and **Verilator + C++** (`vlate_bench/`).

For a concise backlog and suggested priorities, see **[`docs/PLAN.md`](docs/PLAN.md)** (also built as **`docs/PLAN.pdf`** when you run **`make docs`**).

## Quick Start

From a fresh Ubuntu-like machine, run:

```bash
sudo apt update
sudo apt install -y iverilog pandoc gtkwave python3 python3-pip make
python3 -m pip install --user cocotb pytest

# from repo root: unit tests, integration (bridge+BFM), spec PDFs, bench README PDFs, roadmap PDF
make
# or step-by-step:
#   make test
#   make integration-test
#   make docs
make waves
```

## Directory Layout

- `src/` - RTL design source
- `test/` - Cocotb testbench and simulation Makefile
- `integration/` - Closed-loop top (`chi_to_bow_integration_top`) + reference BoW link BFM
- `doc/` - Standardized documentation directory
- `docs/` - Design specification, integration addendum, **roadmap (PLAN)**, and docs Makefile (`design_spec.pdf`, `integration.pdf`, `PLAN.pdf`)
- `uvm_bench/` - Synopsys VCS / UVM integration smoke TB (optional license)
- `vlate_bench/` - Verilator + C++ parity smoke TB

## Prerequisites

- `iverilog` and `vvp` available at `/usr/bin` (or adjust in `test/Makefile`)
- Python 3 with Cocotb installed:
  - `python3 -m pip install --user cocotb pytest`
- `pandoc` for Markdown → PDF conversion (design spec, roadmap, README PDFs)
- **Optional — `vlate_bench/`**: [Verilator](https://www.veripool.org/verilator/) (`verilator`) and a C++17 toolchain (`make run` builds `obj_dir/Vtb_top`)
- **Optional — `uvm_bench/`**: [Synopsys VCS](https://synopsys.com) with bundled UVM via `-ntb_opts uvm-1.2` (`make run` builds `./simv`)

## Common Commands

From the repository root:

- Run tests:
  - `make test`
- Run system integration sim (bridge + in-repo BFM, asserts `err_*` clean):
  - `make integration-test`
- Build PDFs (Markdown in `docs/` and both bench READMEs):
  - `make docs`
  - This runs `make -C docs` (three spec/plan PDFs below), then **`make -C uvm_bench pdf`** and **`make -C vlate_bench pdf`** (environment README PDFs).
- Generate waveforms (`.fst` and, when available, `.vcd`):
  - `make waves`
- Open waveforms in GTKWave:
  - `make gtkwave`
- Check local toolchain/setup:
  - `make doctor`
- Run full default build (unit + integration + docs):
  - `make`
- Clean generated artifacts:
  - `make clean`

Continuous integration (GitHub Actions) runs `make doctor` then `make` — the default **`make`** target does **not** invoke optional VCS/UVM or Verilator smoke sims (see `docs/PLAN.md`). It runs cocotb unit and integration sims plus **`make docs`** (spec, integration addendum, **`docs/PLAN.pdf`**, and **`uvm_bench/README.pdf`** / **`vlate_bench/README.pdf`** from Pandoc).

## Verification environments (optional simulators)

Quick reference:

| Directory | Simulator | Typical command |
|-----------|-----------|-----------------|
| `test/`, `integration/` | Icarus Verilog | `make -C test`, `make -C integration` (also used by CI) |
| `uvm_bench/` | Synopsys VCS + UVM | `make -C uvm_bench run` |
| `vlate_bench/` | Verilator | `make -C vlate_bench run` |

Each environment directory has its own **`README.md`** (and **`make pdf`** → **`README.pdf`**). See those files for flags, file lists, and troubleshooting.

## Direct Subdirectory Commands

- Test only:
  - `make -C test`
- Integration sim only:
  - `make -C integration`
- Build spec/plan PDFs only (not bench README PDFs):
  - `make -C docs pdf`
- UVM environment (VCS installed):
  - `make -C uvm_bench run`
  - `make -C uvm_bench pdf` — **`uvm_bench/README.pdf`**
- Verilator environment:
  - `make -C vlate_bench run`
  - `make -C vlate_bench pdf` — **`vlate_bench/README.pdf`**

## Outputs

- Cocotb regression output under `test/` and `integration/` (for example `results.xml`, `sim_build/`)
- Waveforms under `test/sim_build/`:
  - `chi_to_bow_bridge.fst` (always when running `make waves`)
  - `chi_to_bow_bridge.vcd` (if `fst2vcd` is installed)
- PDFs produced by **`make docs`**:
  - **Specs & roadmap**: `docs/design_spec.pdf`, `docs/integration.pdf`, **`docs/PLAN.pdf`** (Markdown sources in **`docs/`**)
  - **Environment guides**: **`uvm_bench/README.pdf`**, **`vlate_bench/README.pdf`** (from each bench’s `README.md` via Pandoc; same run as above)

## Notes

- Bridge supports multiple outstanding transactions, tracked by `chi_req_txnid`.
- A request with `chi_req_beats=0` is not enqueued (no transfer into the CHI request FIFO) even if
  `chi_req_ready` is high; use non-zero burst counts for real traffic.
- Burst sizing is controlled by `chi_req_beats` (non-zero). BoW `REQ_HDR` / `RSP_HDR` (when carrying
  read data) encode **`beats-1`** in the header flit low byte.
- BoW framing uses request/response header flits plus optional data flits.
- Data flits carry full `DATA_WIDTH` payload (64 bits in the default config).
- On the simplified CHI response channel, multi-beat reads retire on the **final** response-data beat, so the bridge preserves txnid ordering/association without exposing a separate beat counter on the CHI side.
- RX-side protocol guardrails increment error counters for illegal, unknown,
  duplicate, and orphan response patterns.

## Troubleshooting

- `cocotb-config: command not found`
  - Ensure user-local binaries are in `PATH`:
    - `export PATH="$HOME/.local/bin:$PATH"`
  - Then verify:
    - `which cocotb-config`

- Python startup errors from simulator (for example missing `encodings`)
  - This is usually an environment conflict from `VIRTUAL_ENV`/`PYTHONHOME`.
  - This project already unsets those during simulation in `test/Makefile`.
  - If needed, run manually with a clean environment:
    - `env -u VIRTUAL_ENV -u PYTHONHOME make -C test`

- Simulator version mismatch (for example vvp runtime older than compiled image)
  - Clean stale outputs and rebuild:
    - `make clean`
    - `make test`
  - Confirm active binaries:
    - `which iverilog`
    - `which vvp`

- `pandoc` missing for docs
  - Install and rebuild:
    - `sudo apt install -y pandoc`
    - `make docs`
