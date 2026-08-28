# UVM on open-source Verilator (`uvm_bench/vlt`)

Runs the CHI-to-BoW integration UVM bench under open-source **Verilator 5.050**
with the bundled Accellera UVM 2020.3.1 library — a license-free path (the bench
otherwise targets VCS).

## Prerequisites
- **Verilator >= 5.050, UVM-capable** (OSS CAD Suite's is not). Local ref:
  `~/verilator/bin/verilator`. **`unset VERILATOR_ROOT`** after sourcing the OSS
  CAD Suite env. **`UVM_HOME`** = `~/verilator/test_regress/t/uvm`.
- **An SMT solver on PATH (z3 or cvc5)** — Verilator solves randomize()
  constraints with it; without it constrained randomize() returns 0. (CI installs
  z3.)

## Usage
```sh
V=~/verilator/bin/verilator ; U=~/verilator/test_regress/t/uvm
( unset VERILATOR_ROOT; make -C uvm_bench/vlt lint  VERILATOR=$V UVM_HOME=$U )  # RAM-safe
( unset VERILATOR_ROOT; make -C uvm_bench/vlt smoke VERILATOR=$V UVM_HOME=$U )  # build + run chi_smoke_test
```
Top `tb_top`; test via `+UVM_TESTNAME` (default `chi_smoke_test`, override
`UVM_TEST=<name>`). The `--binary` build belongs in CI, not a RAM-constrained host.

## `uvm_macros.svh`
Required tracked empty include-shim. Do not delete.
