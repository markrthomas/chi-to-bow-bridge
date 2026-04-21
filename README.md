# CHI to BoW Bridge (Starter)

This repository contains a starter Verilog bridge that packetizes simplified CHI
requests into BoW flits and reconstructs simplified CHI responses, plus a
Cocotb testbench and design documentation.

## Quick Start

From a fresh Ubuntu-like machine, run:

```bash
sudo apt update
sudo apt install -y iverilog pandoc python3 python3-pip make
python3 -m pip install --user cocotb

# from repo root
make test
make docs
```

## Directory Layout

- `src/` - RTL design source
- `test/` - Cocotb testbench and simulation Makefile
- `docs/` - Design specification and docs Makefile

## Prerequisites

- `iverilog` and `vvp` available at `/usr/bin` (or adjust in `test/Makefile`)
- Python 3 with Cocotb installed:
  - `python3 -m pip install --user cocotb`
- `pandoc` for PDF document generation

## Common Commands

From the repository root:

- Run tests:
  - `make test`
- Build docs PDF:
  - `make docs`
- Check local toolchain/setup:
  - `make doctor`
- Run everything:
  - `make`
- Clean generated artifacts:
  - `make clean`

## Direct Subdirectory Commands

- Test only:
  - `make -C test`
- Build docs only:
  - `make -C docs`

## Outputs

- Cocotb regression output under `test/` (for example `results.xml`, `sim_build/`)
- PDF design spec at `docs/design_spec.pdf`

## Notes

- Current bridge model supports one outstanding transaction.
- BoW payload mapping in this starter encodes lower 50 data bits in a single
  fixed 128-bit flit.

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
