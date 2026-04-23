# CHI to BoW Bridge (Starter)

This repository contains a starter Verilog bridge that packetizes simplified CHI
requests into BoW flits and reconstructs simplified CHI responses, plus a
Cocotb testbench and design documentation.

## Quick Start

From a fresh Ubuntu-like machine, run:

```bash
sudo apt update
sudo apt install -y iverilog pandoc gtkwave python3 python3-pip make
python3 -m pip install --user cocotb pytest

# from repo root: unit tests, integration (bridge+BFM), and PDF docs
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
- `docs/` - Design specification, integration addendum, and docs Makefile

## Prerequisites

- `iverilog` and `vvp` available at `/usr/bin` (or adjust in `test/Makefile`)
- Python 3 with Cocotb installed:
  - `python3 -m pip install --user cocotb pytest`
- `pandoc` for PDF document generation

## Common Commands

From the repository root:

- Run tests:
  - `make test`
- Run system integration sim (bridge + in-repo BFM, asserts `err_*` clean):
  - `make integration-test`
- Build docs PDF:
  - `make docs`
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

Continuous integration (GitHub Actions) runs the same as a full local check: `make doctor` then `make` (cocotb unit and integration sims, `design_spec.pdf` and `integration.pdf`).

## Direct Subdirectory Commands

- Test only:
  - `make -C test`
- Integration sim only:
  - `make -C integration`
- Build docs only:
  - `make -C docs`

## Outputs

- Cocotb regression output under `test/` and `integration/` (for example `results.xml`, `sim_build/`)
- Waveforms under `test/sim_build/`:
  - `chi_to_bow_bridge.fst` (always when running `make waves`)
  - `chi_to_bow_bridge.vcd` (if `fst2vcd` is installed)
- PDF design spec and integration addendum: `docs/design_spec.pdf`, `docs/integration.pdf` (from `make docs`)

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
