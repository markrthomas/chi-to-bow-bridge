# UVM testbench environment (`uvm_bench`)

This directory contains a **SystemVerilog UVM** testbench for the **CHI-to-BoW integration** hierarchy, intended to run with **Synopsys VCS** and the **UVM 1.x** library bundled via `-ntb_opts uvm-1.2`.

Policy: **`uvm_bench` is not independent of the OSS thread.** It stays **behaviorally aligned** with **Integration Cocotb** and **Verilator `vlate_bench`** per **[`docs/PLAN.md`](../docs/PLAN.md)** (scenario matrix + UVM–OSS parity). When integration scenarios move, update **`uvm/chi_tb_pkg.sv`** **and this mapping table** in the **same PR** when possible.

## Stay synchronized with OSS (mandatory mapping)

| Integration Cocotb (`integration/test_integration.py`) | Verilator (`vlate_bench/tb_main.cpp`) | UVM (+UVM_TESTNAME / `chi_tb_pkg.sv`) |
| --- | --- | --- |
| `test_integration_bfm_completes_smoke` — read `@0x1000` **`0x2A`**, write `@0x2000` **`0x2B`**, write data **`0xDEADBEEF00000099`** | First `drive_until_accept` **RD**, idle, **`WR`** block | **`chi_smoke_test`** ← **`chi_smoke_seq`** (read-first, **`#500ns`** between) |
| `test_integration_bfm_burst_through_top` — write **`0x71`** ×3 beats, read **`0x72`** ×4 beats | Burst **`drive_until_accept`** WR then RD | **`chi_burst_test`** ← **`chi_burst_smoke_seq::burst_traffic()`** (**`#1us`** pacing) |
| `test_integration_illegal_chi_req_opcodes_increment_err_counter` — **`CHI_OP_READ_RESP` (2'b10)** and **`CHI_OP_WRITE_ACK` (2'b11)** on REQ, txn **`0x01`** / **`0x02`** | **`drive_illegal_req_phase`** (after **`inject_unknown_txn_rsp_hdr`**) | **`chi_illegal_req_test`** <- **`drive_illegal_req_phase`** |
| **`test_integration_unknown_txnid_bow_rsp_hdr_via_inj`** — malformed BoW **`RSP_HDR`** with txn **`0xFE`** on **`bow_inj_*`** | **`inject_unknown_txn_rsp_hdr`** | *not automated in SV yet* (**`tb_top`** ties **`bow_inj_*`** off) |

Constants / read payload layouts: **`verification/golden_payloads.py`** <-> **`chi_tb.hpp`** <-> **`exp_read_data()`** in **`chi_tb_pkg.sv`**.

### PR workflow (when touching integration verification)

1. Change **`integration/test_integration.py`** and/or **`vlate_bench/tb_main.cpp`** as needed **or** intentionally leave them untouched.
2. If the **integration scenario matrix** ([`docs/PLAN.md`](../docs/PLAN.md)) changes, update **`uvm/chi_tb_pkg.sv`** (sequences, delays, **`drive_illegal_req_phase`**) and **this table** above.
3. Run **`make oss-regress`** (or **`make integration-test`** + **`make -C vlate_bench lint && make -C vlate_bench run`**). Run **`make -C uvm_bench run`** for each **`UVM_TEST`** you touched ([`Makefile`](Makefile)). After changing **`chi_tb_cov.svh`** bins/crosses or VCS **`VCS_COV_COMPILE`** knobs, run **`make -C uvm_bench coverage`** (if licensed) and inspect **`sim.log`** **`COV`** lines plus optional **`make cov-report`**.

## What it verifies

**`chi_smoke_test`** mirrors **`test_integration_bfm_completes_smoke`**; **`chi_burst_test`** mirrors **`test_integration_bfm_burst_through_top`**; **`chi_illegal_req_test`** mirrors **`test_integration_illegal_chi_req_opcodes_increment_err_counter`** (after **`inject_unknown`** in Verilator sequencing). Cocotb **`test_integration_unknown_txnid_bow_rsp_hdr_via_inj`** + Verilator **`inject_unknown_txn_rsp_hdr`** use **`bow_inj_*`** (*UVM **`tb_top`** ties those mux pins off until an SV analogue lands*).

Common structure:

- **DUT hierarchy:** `chi_to_bow_integration_top` wraps `chi_to_bow_bridge` and `bow_link_partner_bfm`.
- **Stimulus:** Directed sequences with pacing so the BFM returns to idle (`chi_smoke_seq` / `chi_burst_smoke_seq` in `uvm/chi_tb_pkg.sv`).
- **Checks:** Scoreboard compares CHI responses for legal ops, including **`exp_read_data()`** for read completions (same deterministic read payload as the BFM).

Beyond the OSS-mapped smoke+burst+illegal-REQ+unknown-txn-inject matrix above, extending sequences for **extra UVM-only** stimulus is discouraged unless **`docs/PLAN.md`** gains a matching row describing expected parity (or intentionally labels UVM-only scope).

## Prerequisites

- **Synopsys VCS** (`vcs` on `PATH`).
- UVM supplied by VCS via **`-ntb_opts uvm-1.2`** (no separate `$UVM_HOME` compile typically required).

## Layout

| Path | Role |
|------|------|
| `sim.f` | Compilation file list (RTL + TB); run VCS **from `uvm_bench/`** or adjust paths). |
| `tb/chi_integration_if.sv` | Virtual-interface bundle for CHI REQ/RSP (modports for driver vs monitor). |
| `tb/tb_top.sv` | Top module: ties `chi_to_bow_integration_top` to the interface, `uvm_config_db` for `vif`, `run_test()`. |
| `uvm/chi_tb_pkg.sv` | UVM package: driver, monitor, scoreboard, **`chi_tb_cfg`** pacing object, **`chi_sequence_base`** helpers (`drive_read` / `drive_write` / `pause_ns` + `uvm_declare_p_sequencer`); **`chi_base_test`** publishes cfg to the sequencer and grabs `vif`; sequences (**`chi_smoke_seq`**, **`chi_burst_smoke_seq::burst_traffic()`**) and **`chi_illegal_req_test`**. |
| `uvm/chi_tb_cov.svh` | **`chi_integration_cov`**: functional covergroups on CHI REQ/RSP valid/ready handshakes (opcodes, golden txnids, beats, crosses). Included from **`chi_tb_pkg.sv`**; **`chi_env`** always builds **`cov`**. |
| `Makefile` | `compile` / `run` / **`compile-cov`** / **`run-cov`** / **`coverage`** / **`cov-report`** / `clean` / **`pdf`** (README → PDF via Pandoc). |

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

Multi-beat parity (same scenario as integration burst Cocotb test):

```bash
make run UVM_TEST=chi_burst_test
```

Directed illegal-REQ check (parity with integration Cocotb / `vlate_bench`):

```bash
make run UVM_TEST=chi_illegal_req_test
```

### Coverage

- **Functional (SV covergroups):** **`chi_integration_cov`** samples the virtual **`chi_integration_if`** every clock; **`report_phase`** prints **`[COV]`** percentages from **`cg_req_handshake`** / **`cg_rsp_handshake`** (`sim.log`). Extend bins when **`docs/PLAN.md`** integration scenarios add txnids or beats.
- **Structural (Synopsys VCS `-cm`):** rebuild with instrumentation and leave a **`uvm_cov.vdb`** database (gitignored):

```bash
make coverage UVM_TEST=chi_smoke_test
# repeat for chi_burst_test / chi_illegal_req_test, then merge/report with URG:
make cov-report
```

Tune **`VCS_COV_COMPILE`** / **`COV_DIR`** in the [`Makefile`](Makefile) if your site uses different VCM flags.

Custom VCS switches:

```bash
make compile EXTRA_VCSOPTS="+define+MY_DEFINE"
```

### Manual VCS (equivalent sketch)

Commands must be run **from `uvm_bench/`** so `sim.f` relative paths resolve:

```bash
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 +acc+r -f sim.f -o ./simv
./simv +UVM_TESTNAME=chi_smoke_test +UVM_VERBOSITY=UVM_MEDIUM -l sim.log
# or: +UVM_TESTNAME=chi_burst_test ; +UVM_TESTNAME=chi_illegal_req_test
```

Artifacts: `./simv`, `sim.log` (Makefile `clean` removes common VCS clutter).

## Architecture (conceptual)

1. **`tb_top`** builds clock/reset (interface reset wired to RTL `rst_n`) and publishes `virtual chi_integration_if` via **`uvm_config_db`** with **`set(null, CHI_DB_SCOPE_ALL, CHI_DB_KEY_VIF, …)`** (wildcard scope `"*"`). Components resolve it with the usual **`get(this, "", CHI_DB_KEY_VIF, …)`** walk upward—use **`CHI_DB_KEY_VIF`** so extensions share one field name.
2. **`chi_agent`** contains the CHI driver, sequencer, and response monitor. **`chi_env`** also instantiates **`chi_integration_cov`**, which samples REQ/RSP handshakes on **`vif`** for functional coverage.
3. **`chi_driver`** implements **valid/ready** on `chi_req_*` until the request is accepted, then emits an expectation into the scoreboard (**same ordering as acceptance**, not end-to-end protocol completion).
4. **`chi_rsp_monitor`** samples completed CHI responses when `chi_rsp_valid && chi_rsp_ready` on clock edges.
5. **`chi_scoreboard`** matches observed responses to queued expectations (write-ack and read response with predictable data; multi-beat reads complete on the last data beat exposed on CHI, as in RTL).
6. **`chi_illegal_req_test`** uses **`chi_base_test::expect_illegal_req_inc`** (wrapper around **`drive_illegal_req_phase`**, no scoreboard expectation): **`vif.err_illegal_req_hdr`** / **`vif.err_pulse`** are tied from the DUT pins in **`tb_top`**.

### Easier-UVM ergonomics (within `chi_tb_pkg`)

- **`chi_tb_cfg`** — one pacing/drain object (`smoke_gap_rd_wr_ns`, `smoke_drain_ns`, `burst_mid_ns`, `burst_drain_ns`, `illegal_tail_ns`, `illegal_settle_clks`). **`chi_base_test`** creates default knobs, publishes them to **`env.agent.seqr`** under **`CHI_DB_KEY_TBCFG`**, and tests use **`cfg.*`** for objections / drains.
- **`chi_sequence_base`** — virtual sequence base with **`uvm_declare_p_sequencer(chi_sequencer)`** plus **`drive_read`**, **`drive_write`**, and **`pause_ns`**. Concrete sequences (**`chi_smoke_seq`**, **`chi_burst_smoke_seq`**) stay short and read like directed stimulus recipes.
- **Custom tests** — optional: build a **`chi_tb_cfg`** in your test’s **`build_phase`**, **`uvm_config_db#(chi_tb_cfg)::set(this, "", CHI_DB_KEY_TBCFG, cfg)`**, then call **`super.build_phase(phase)`** so **`chi_base_test`** picks it up instead of the defaults.

Default timing bundle matches the prior literals: smoke gap **`500ns`**, smoke drain **`5us`**, burst gap **`1us`**, burst drain **`8us`**, illegal tail **`500ns`**, **`10`** settle clocks before illegal stimulus.

## Related project docs

- Design and BoW framing: **`docs/design_spec.md`**
- Integration files and Cocotb: **`integration/README.md`** and **`test/`**
