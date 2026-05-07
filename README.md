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

# from repo root: unit tests, integration, spec PDFs, UVM + Verilator bench PDFs, roadmap PDF
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
- `scripts/` - Helper scripts (see **`make oss-regress`**)
- **`uvm_bench/`** - Synopsys VCS / UVM integration TB (**[`UVM_ONBOARDING.md`](uvm_bench/UVM_ONBOARDING.md)** for DV/UVM engineers new to the repo)
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
- Build PDFs (Markdown in `docs/` plus **UVM**: **`README.md`**, **`UVM_QUICKREF.md`**, **`UVM_ONBOARDING.md`**, **Verilator**: `README.md`):
  - `make docs`
  - This runs `make -C docs` (three spec/plan PDFs below), then **`make -C uvm_bench pdf`** (**`README.pdf`**, **`UVM_QUICKREF.pdf`**, **`UVM_ONBOARDING.pdf`**) and **`make -C vlate_bench pdf`** (**`README.pdf`**).
  - Shortcut for UVM PDFs only: **`make uvm-pdf`**.
- Generate waveforms (`.fst` and, when available, `.vcd`):
  - `make waves`
- Open waveforms in GTKWave:
  - `make gtkwave`
- Check local toolchain/setup:
  - `make doctor`
- **OSS-only full regression** (doctor + **`make`** + Verilator **`lint`** + **`vlate_bench run`** — needs `verilator` on `PATH`):
  - `make oss-regress`
- **OSS regression + Verilator structural coverage** (also runs **`make -C vlate_bench coverage`**, emits **`vlate_coverage.info`; needs **`verilator_coverage`**):
  - `make oss-regress-coverage`
- Clean generated artifacts:
  - `make clean`

Continuous integration (GitHub Actions) runs two jobs combined locally by **`make oss-regress`** (when Verilator is installed):

1. **`test`** — `make doctor && make`: cocotb unit/integration sims plus **`make docs`** (spec/integration/**`docs/PLAN.pdf`**, **`uvm_bench/README.pdf`**, **`uvm_bench/UVM_QUICKREF.pdf`**, **`uvm_bench/UVM_ONBOARDING.pdf`**, and **`vlate_bench/README.pdf`**).
2. **`vlate-bench`** — installs OSS **Verilator**, runs **`make -C vlate_bench lint`** (RTL-only) then **`make -C vlate_bench run`** so lint + parity C++ TB stay green.

OSS-first verification (no VCS) is spelled out in **`docs/PLAN.md`**.

Synopsys **VCS**/UVM is **not** run in CI; use **`make -C uvm_bench run`** when you have a license. Details: **`docs/PLAN.md`**.

## Verification environments (optional simulators)

Quick reference:

| Directory | Simulator | Typical command |
|-----------|-----------|-----------------|
| `test/`, `integration/` | Icarus Verilog | `make -C test`, `make -C integration` (also used by CI) |
| `uvm_bench/` | Synopsys VCS + UVM | `make -C uvm_bench run`; optional `make -C uvm_bench coverage` / `cov-report` |
| `vlate_bench/` | Verilator | `make -C vlate_bench lint`, `make -C vlate_bench run`, `make -C vlate_bench coverage` |

Each environment directory has its own **`README.md`** (**`make -C uvm_bench pdf`** also emits **`UVM_QUICKREF.pdf`** and **`UVM_ONBOARDING.pdf`**). See those files for flags, file lists, and troubleshooting.

## Direct Subdirectory Commands

- Test only:
  - `make -C test`
- Integration sim only:
  - `make -C integration`
- Build spec/plan PDFs only (not bench README / quickref PDFs):
  - `make -C docs pdf`
- UVM environment (VCS installed):
  - `make -C uvm_bench run`
  - **`make -C uvm_bench pdf`** — **`README.pdf`**, **`UVM_QUICKREF.pdf`**, **`UVM_ONBOARDING.pdf`** (or **`make pdf-readme`**, **`make pdf-quickref`**, **`make pdf-onboarding`** individually)
  - From repo root: **`make uvm-pdf`**
- Verilator environment:
  - `make -C vlate_bench lint`
  - `make -C vlate_bench run`
  - `make -C vlate_bench coverage` — structural coverage (needs `verilator_coverage`)
  - `make -C vlate_bench pdf` — **`vlate_bench/README.pdf`**

## Outputs

- Cocotb regression output under `test/` and `integration/` (for example `results.xml`, `sim_build/`)
- Waveforms under `test/sim_build/`:
  - `chi_to_bow_bridge.fst` (always when running `make waves`)
  - `chi_to_bow_bridge.vcd` (if `fst2vcd` is installed)
- PDFs produced by **`make docs`**:
  - **Specs & roadmap**: `docs/design_spec.pdf`, `docs/integration.pdf`, **`docs/PLAN.pdf`** (Markdown sources in **`docs/`**)
  - **UVM guides**: **`uvm_bench/README.pdf`**, **`uvm_bench/UVM_QUICKREF.pdf`**, **`uvm_bench/UVM_ONBOARDING.pdf`** (from **`README.md`**, **`UVM_QUICKREF.md`**, **`UVM_ONBOARDING.md`**)
  - **Verilator guide**: **`vlate_bench/README.pdf`** (from **`README.md`**)

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
