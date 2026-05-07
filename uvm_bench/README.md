# UVM testbench environment (`uvm_bench`)

This directory contains a **SystemVerilog UVM** testbench for the **CHI-to-BoW integration** hierarchy, intended to run with **Synopsys VCS** and the **UVM 1.x** library bundled via `-ntb_opts uvm-1.2`.

Policy: **`uvm_bench` is not independent of the OSS thread.** It stays **behaviorally aligned** with **Integration Cocotb** and **Verilator `vlate_bench`** per **[`docs/PLAN.md`](../docs/PLAN.md)** (scenario matrix + UVM–OSS parity). When integration scenarios move, update **`uvm/chi_tb_pkg.sv`** **and this mapping table** in the **same PR** when possible.

**Quick lookup:** commands, tests, paths, and **`config_db`** keys are summarized in **[`UVM_QUICKREF.md`](UVM_QUICKREF.md)** (also built as **`UVM_QUICKREF.pdf`** — see **Markdown → PDF** below).

## Stay synchronized with OSS (mandatory mapping)

| Integration Cocotb (`integration/test_integration.py`) | Verilator (`vlate_bench/tb_main.cpp`) | UVM (+UVM_TESTNAME / `chi_tb_pkg.sv`) |
| --- | --- | --- |
| `test_integration_bfm_completes_smoke` — read `@0x1000` **`0x2A`**, write `@0x2000` **`0x2B`**, write data **`0xDEADBEEF00000099`** | First `drive_until_accept` **RD**, idle, **`WR`** block | **`chi_smoke_test`** ← **`chi_smoke_seq`** (read-first, **`#500ns`** between) |
| `test_integration_bfm_burst_through_top` — write **`0x71`** ×3 beats, read **`0x72`** ×4 beats | Burst **`drive_until_accept`** WR then RD | **`chi_burst_test`** ← **`chi_burst_smoke_seq::burst_traffic()`** (**`#1us`** pacing) |
| `test_integration_illegal_chi_req_opcodes_increment_err_counter` — **`CHI_OP_READ_RESP` (2'b10)** and **`CHI_OP_WRITE_ACK` (2'b11)** on REQ, txn **`0x01`** / **`0x02`** | **`drive_illegal_req_phase`** (after **`inject_unknown_txn_rsp_hdr`**) | **`chi_illegal_req_test`** <- **`drive_illegal_req_phase`** |
| **`test_integration_unknown_txnid_bow_rsp_hdr_via_inj`** — malformed BoW **`RSP_HDR`** with txn **`0xFE`** on **`bow_inj_*`** | **`inject_unknown_txn_rsp_hdr`** | **`chi_unknown_txn_inj_test`** (`inject_unknown_txn_rsp_hdr`); stitched smoke+burst+inject+illegal: **`chi_full_integration_test`** |

Constants / read payload layouts: **`verification/golden_payloads.py`** <-> **`chi_tb.hpp`** <-> **`exp_read_data()`** in **`chi_tb_pkg.sv`**.

### PR workflow (when touching integration verification)

1. Change **`integration/test_integration.py`** and/or **`vlate_bench/tb_main.cpp`** as needed **or** intentionally leave them untouched.
2. If the **integration scenario matrix** ([`docs/PLAN.md`](../docs/PLAN.md)) changes, update **`uvm/chi_tb_pkg.sv`** (sequences, delays, **`drive_illegal_req_phase`**) and **this table** above.
3. Run **`make oss-regress`** (or **`make integration-test`** + **`make -C vlate_bench lint && make -C vlate_bench run`**). Run **`make -C uvm_bench run`** for each **`UVM_TEST`** you touched — at minimum **`chi_smoke_test`**, **`chi_burst_test`**, **`chi_illegal_req_test`**, **`chi_unknown_txn_inj_test`**, **`chi_full_integration_test`** when inject or stitched flow changes ([`Makefile`](Makefile)). After changing **`chi_tb_cov.svh`** bins/crosses or VCS **`VCS_COV_COMPILE`** knobs, run **`make -C uvm_bench coverage`** (if licensed) and inspect **`sim.log`** **`COV`** lines plus optional **`make cov-report`**.

## What it verifies

**`chi_smoke_test`** mirrors **`test_integration_bfm_completes_smoke`**; **`chi_burst_test`** mirrors **`test_integration_bfm_burst_through_top`**; **`chi_illegal_req_test`** mirrors **`test_integration_illegal_chi_req_opcodes_increment_err_counter`** (illegal REQ opcodes only — no **`bow_inj`**). **`chi_unknown_txn_inj_test`** mirrors **`test_integration_unknown_txnid_bow_rsp_hdr_via_inj`**. **`chi_full_integration_test`** stitches smoke → burst → inject → illegal REQ in the same order as **`vlate_bench/tb_main.cpp`**. Cocotb **`bow_inj_*`** + Verilator **`inject_unknown_txn_rsp_hdr`** use the same 128-bit flit constants as **`chi_tb_pkg`** (**`BOW_INJ_UNKNOWN_HDR_*`**).

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
| `sim.f` | Compilation file list (RTL + **`verification/chi_integration_protocol_chk.sv`** bind module + TB); run VCS **from `uvm_bench/`** or adjust paths). |
| `tb/chi_integration_if.sv` | Virtual-interface bundle for CHI REQ/RSP, **`bow_inj_*`**, and mirrored **`err_*`** counters (driver vs monitor modports). |
| `tb/tb_top.sv` | Top module: ties `chi_to_bow_integration_top` to the interface, `uvm_config_db` for `vif`, `run_test()`. |
| `uvm/chi_tb_pkg.sv` | UVM package: driver (**`inject_unknown_txn_rsp_hdr`** + **`drive_illegal_req_phase`**), monitor, scoreboard, **`chi_tb_cfg`** (includes **`stitched_final_ns`** for **`chi_full_integration_test`**), sequences, **`chi_unknown_txn_inj_test`**, **`chi_full_integration_test`**, plus smaller tests documented above. |
| `uvm/chi_tb_cov.svh` | **`chi_integration_cov`**: functional covergroups on CHI REQ/RSP valid/ready handshakes (opcodes, golden txnids, beats, crosses). Included from **`chi_tb_pkg.sv`**; **`chi_env`** always builds **`cov`**. |
| `Makefile` | `compile` / `run` / **`compile-cov`** / **`run-cov`** / **`coverage`** / **`cov-report`** / `clean` / **`pdf`** / **`pdf-readme`** / **`pdf-quickref`**. |

### Integration protocol asserts

**`verification/chi_integration_protocol_chk.sv`** is compiled via **`sim.f`** and **binds** into **`chi_to_bow_integration_top`**. It checks CHI REQ/RSP and **`bow_inj_*`** valid/ready “hold until handshake” behavior (procedural asserts compatible with Verilator when the same file is used in **`vlate_bench`**). The Verilator C++ mirror is **`vlate_bench/chi_proto.hpp`** (**`HoldChecker`**).

### Markdown → PDF (UVM documentation)

All PDFs use [Pandoc](https://pandoc.org/) (`PANDOC` on `PATH`, override with **`make PANDOC=…`**). The CI image installs TeX so Pandoc can emit PDF; locally, install **`pandoc`** plus a LaTeX engine if **`make pdf`** fails.

From **`uvm_bench/`**:

| Command | Output |
|---------|--------|
| **`make pdf`** or **`make pdf-all`** | **`README.pdf`** and **`UVM_QUICKREF.pdf`** |
| **`make pdf-readme`** | **`README.md` → `README.pdf`** only |
| **`make pdf-quickref`** | **`UVM_QUICKREF.md` → `UVM_QUICKREF.pdf`** only |

Optional Pandoc flags for every PDF in one shot:

```bash
make pdf PANDOC_PDF_OPTS='--toc -V geometry:margin=1in'
```

Remove PDFs with **`make clean-pdf`** (or **`make clean`**, which also removes simulation artifacts).

From the repository **root**, **`make docs`** runs **`make -C docs pdf`** then **`make -C uvm_bench pdf`** then **`make -C vlate_bench pdf`**, so both UVM PDFs are produced together with **`docs/*.pdf`** and **`vlate_bench/README.pdf`**.

For convenience the root Makefile also exposes **`make uvm-pdf`** (same as **`make -C uvm_bench pdf`**).

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

BoW inject + unknown-txn **`RSP_HDR`** (integration **`bow_inj_*`** path):

```bash
make run UVM_TEST=chi_unknown_txn_inj_test
```

Full stitched flow (matches **`vlate_bench`** **`tb_main.cpp`** ordering):

```bash
make run UVM_TEST=chi_full_integration_test
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
#     +UVM_TESTNAME=chi_unknown_txn_inj_test ; +UVM_TESTNAME=chi_full_integration_test
```

Artifacts: `./simv`, `sim.log` (Makefile `clean` removes common VCS clutter).

## Architecture (conceptual)

1. **`tb_top`** builds clock/reset (interface reset wired to RTL `rst_n`), **`bow_inj_*`** and **`err_*`** observability into **`chi_integration_if`**, and publishes `virtual chi_integration_if` via **`uvm_config_db`** with **`set(null, CHI_DB_SCOPE_ALL, CHI_DB_KEY_VIF, …)`** (wildcard scope `"*"`). Components resolve it with the usual **`get(this, "", CHI_DB_KEY_VIF, …)`** walk upward—use **`CHI_DB_KEY_VIF`** so extensions share one field name.
2. **`chi_agent`** contains the CHI driver, sequencer, and response monitor. **`chi_env`** also instantiates **`chi_integration_cov`**, which samples REQ/RSP handshakes on **`vif`** for functional coverage.
3. **`chi_driver`** implements **valid/ready** on `chi_req_*` until the request is accepted, then emits an expectation into the scoreboard (**same ordering as acceptance**, not end-to-end protocol completion). Directed **`inject_unknown_txn_rsp_hdr`** asserts **`bow_inj_*`** handshake + **`err_unknown_txn_rsp_hdr`** isolation (parity with Cocotb / **`vlate_bench`**).
4. **`chi_rsp_monitor`** samples completed CHI responses when `chi_rsp_valid && chi_rsp_ready` on clock edges.
5. **`chi_scoreboard`** matches observed responses to queued expectations (write-ack and read response with predictable data; multi-beat reads complete on the last data beat exposed on CHI, as in RTL).
6. **`chi_illegal_req_test`** uses **`chi_base_test::expect_illegal_req_inc`** (wrapper around **`drive_illegal_req_phase`**, no scoreboard expectation): **`vif.err_illegal_req_hdr`** / **`vif.err_pulse`** are tied from the DUT pins in **`tb_top`**.

### Easier-UVM ergonomics (within `chi_tb_pkg`)

- **`chi_tb_cfg`** — one pacing/drain object (`smoke_gap_rd_wr_ns`, `smoke_drain_ns`, `burst_mid_ns`, `burst_drain_ns`, `illegal_tail_ns`, `illegal_settle_clks`). **`chi_base_test`** creates default knobs, publishes them to **`env.agent.seqr`** under **`CHI_DB_KEY_TBCFG`**, and tests use **`cfg.*`** for objections / drains.
- **`chi_sequence_base`** — virtual sequence base with **`uvm_declare_p_sequencer(chi_sequencer)`** plus **`drive_read`**, **`drive_write`**, and **`pause_ns`**. Concrete sequences (**`chi_smoke_seq`**, **`chi_burst_smoke_seq`**) stay short and read like directed stimulus recipes.
- **Custom tests** — optional: build a **`chi_tb_cfg`** in your test’s **`build_phase`**, **`uvm_config_db#(chi_tb_cfg)::set(this, "", CHI_DB_KEY_TBCFG, cfg)`**, then call **`super.build_phase(phase)`** so **`chi_base_test`** picks it up instead of the defaults.

Default timing bundle matches the prior literals: smoke gap **`500ns`**, smoke drain **`5us`**, burst gap **`1us`**, burst drain **`8us`**, illegal tail **`500ns`**, **`10`** settle clocks before illegal stimulus, stitched final idle **`25us`** (**`stitched_final_ns`**) after illegal checks in **`chi_full_integration_test`** (**`vlate_bench`** tail scale).

## Related project docs

- Design and BoW framing: **`docs/design_spec.md`**
- Integration files and Cocotb: **`integration/README.md`** and **`test/`**
