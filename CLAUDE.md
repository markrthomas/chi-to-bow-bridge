# CLAUDE.md

Orientation auto-loaded into each Claude session in this repo.

## UVM on open-source Verilator (`uvm_bench/vlt`)

License-free way to run this repo's UVM env under **Verilator 5.050** (no
VCS/Xcelium/Questa), added 2026-08-28. **Passing** in CI
(`.github/workflows/verilator-uvm.yml`; builds Verilator from source + installs
**z3** for `randomize()` + `ccache`; lint + `--binary` `smoke` smoke).

Local (lint RAM-safe; `--binary` wants big-RAM/CI):
```sh
V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
( unset VERILATOR_ROOT; make -C uvm_bench/vlt lint   VERILATOR=$V UVM_HOME=$U )
( unset VERILATOR_ROOT; make -C uvm_bench/vlt smoke VERILATOR=$V UVM_HOME=$U )
```
Details: `uvm_bench/vlt/README.md`.
