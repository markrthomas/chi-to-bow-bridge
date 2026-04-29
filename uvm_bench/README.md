# UVM testbench environment (`uvm_bench`)

This directory contains a **SystemVerilog UVM** testbench for the **CHI-to-BoW integration** hierarchy, intended to run with **Synopsys VCS** and the **UVM 1.x** library bundled via `-ntb_opts uvm-1.2`.

## What it verifies

The default test (`chi_smoke_test`) mirrors the Cocotb coverage for **single-beat** transactions against the repository’s **integration top** and reference **BoW link partner**:

- **DUT hierarchy:** `chi_to_bow_integration_top` wraps `chi_to_bow_bridge` and `bow_link_partner_bfm` (die-to-die path modeled in-repo).
- **Stimulus:** A directed **write** then **read**, with pacing between them so the link BFM can return to idle (same intent as `chi_smoke_seq` in `uvm/chi_tb_pkg.sv`).
- **Checks:** A scoreboard compares CHI responses to expectations, including **`exp_read_data()`** aligned with `bow_link_partner_bfm`’s deterministic read payload.

Burst or illegal sequences beyond the reference BFM are **not** the focus here; extend agents/sequences as needed.

## Prerequisites

- **Synopsys VCS** (`vcs` on `PATH`).
- UVM supplied by VCS via **`-ntb_opts uvm-1.2`** (no separate `$UVM_HOME` compile typically required).

## Layout

| Path | Role |
|------|------|
| `sim.f` | Compilation file list (RTL + TB); run VCS **from `uvm_bench/`** or adjust paths). |
| `tb/chi_integration_if.sv` | Virtual-interface bundle for CHI REQ/RSP (modports for driver vs monitor). |
| `tb/tb_top.sv` | Top module: ties `chi_to_bow_integration_top` to the interface, `uvm_config_db` for `vif`, `run_test()`. |
| `uvm/chi_tb_pkg.sv` | UVM package: sequence item, driver, response monitor, dual-`analysis_imp` scoreboard, agent, env, smoke sequence, `chi_smoke_test`. |
| `Makefile` | `compile` / `run` / `clean` / **`pdf`** (README → PDF via Pandoc). |

### PDF of this document

From **`uvm_bench/`** (requires [Pandoc](https://pandoc.org/) on `PATH`, same as **`docs/`**):

```bash
make pdf
```

Produces **`README.pdf`**. Remove it with `make clean-pdf` (or `make clean`, which also removes simulation artifacts).

The repository **root** `make docs` also builds this PDF (and **`vlate_bench/README.pdf`**).

## How to run

From **`uvm_bench/`**:

```bash
make run
```

Or set the test name explicitly:

```bash
make run UVM_TEST=chi_smoke_test
```

Custom VCS switches:

```bash
make compile EXTRA_VCSOPTS="+define+MY_DEFINE"
```

### Manual VCS (equivalent sketch)

Commands must be run **from `uvm_bench/`** so `sim.f` relative paths resolve:

```bash
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 +acc+r -f sim.f -o ./simv
./simv +UVM_TESTNAME=chi_smoke_test +UVM_VERBOSITY=UVM_MEDIUM -l sim.log
```

Artifacts: `./simv`, `sim.log` (Makefile `clean` removes common VCS clutter).

## Architecture (conceptual)

1. **`tb_top`** builds clock/reset (interface reset wired to RTL `rst_n`) and publishes `virtual chi_integration_if` via **`uvm_config_db`** (`"vif"` wildcard).
2. **`chi_agent`** contains the CHI driver, sequencer, and response monitor.
3. **`chi_driver`** implements **valid/ready** on `chi_req_*` until the request is accepted, then emits an expectation into the scoreboard (**same ordering as acceptance**, not end-to-end protocol completion).
4. **`chi_rsp_monitor`** samples completed CHI responses when `chi_rsp_valid && chi_rsp_ready` on clock edges.
5. **`chi_scoreboard`** matches observed responses to queued expectations (single-beat write-ack and read response with predictable data).

Simulations keep running briefly after sequences complete so asynchronous responses can finish (see **`#(5us)` drain** in `chi_smoke_test::run_phase`), analogous to UVM objection timing for slow partner behavior.

## Related project docs

- Design and BoW framing: **`docs/design_spec.md`**
- Integration files and Cocotb: **`integration/README.md`** and **`test/`**
