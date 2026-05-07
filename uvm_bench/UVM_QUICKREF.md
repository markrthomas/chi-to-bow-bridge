# UVM bench quick reference (`uvm_bench`)

One-page companion to **[`README.md`](README.md)** and **[`UVM_ONBOARDING.md`](UVM_ONBOARDING.md)** (diagrams + tables for DV engineers new to the repo). This sheet lists **commands**, **tests**, **paths**, and **`config_db`** names you touch most often.

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| **Synopsys VCS** | `vcs` on `PATH`; run all Makefile flows **from `uvm_bench/`** so **`sim.f`** paths resolve. |
| **UVM** | Supplied by VCS via **`-ntb_opts uvm-1.2`** (see **[`Makefile`](Makefile)** **`VCS_BASE`**). |
| **Pandoc** (PDF only) | **`make pdf`** / per-source **`pdf-readme`** / **`pdf-quickref`** / **`pdf-onboarding`** — same stack as **`docs/`** (often needs TeX for PDF backend). |

Parity policy: align with **Integration Cocotb** and **`vlate_bench`** per **`docs/PLAN.md`**.

---

## Makefile targets

| Target | Purpose |
|--------|---------|
| **`compile`** | `vcs … -f sim.f -o ./simv` |
| **`run`** | `compile` then **`./simv +UVM_TESTNAME=$(UVM_TEST) …`** — default **`UVM_TEST=chi_smoke_test`** |
| **`compile-cov`** / **`run-cov`** / **`coverage`** | VCS **`-cm`** structural instrumentation → **`uvm_cov.vdb`** (gitignored). |
| **`cov-report`** | **URG** textual report from **`$(COV_DIR)`** — requires **`urg`** on **`PATH`**. |
| **`pdf`** | All Markdown PDFs (**`README.pdf`**, **`UVM_QUICKREF.pdf`**, **`UVM_ONBOARDING.pdf`**). |
| **`pdf-readme`** | **`README.md` → `README.pdf`** only. |
| **`pdf-quickref`** | **`UVM_QUICKREF.md` → `UVM_QUICKREF.pdf`** only. |
| **`pdf-onboarding`** | **`UVM_ONBOARDING.md` → `UVM_ONBOARDING.pdf`** only. |
| **`clean-pdf`** | Remove generated **`*.pdf`** in this directory. |
| **`clean`** | **`clean-pdf`** plus **`simv`**, **`sim.log`**, coverage dirs, etc. |

Variables: **`UVM_TEST`**, **`EXTRA_VCSOPTS`**, **`VCS`**, **`SIMV`**, **`COV_DIR`**, **`PANDOC`**, **`PANDOC_PDF_OPTS`** (optional extra Pandoc flags).

---

## Tests (`+UVM_TESTNAME`)

| Test | Role |
|------|------|
| **`chi_smoke_test`** | Single-beat read/write smoke — parity integration Cocotb smoke. |
| **`chi_burst_test`** | Multi-beat write/read — parity integration burst scenario. |
| **`chi_illegal_req_test`** | Illegal REQ-channel opcodes → **`err_illegal_req_hdr`** / **`err_pulse`**. |
| **`chi_unknown_txn_inj_test`** | Unknown-txn **`RSP_HDR`** on **`bow_inj_*`**. |
| **`chi_full_integration_test`** | Stitched smoke → burst → inject → illegal (matches **`vlate_bench/tb_main.cpp`** ordering). |

Example:

```bash
make run UVM_TEST=chi_burst_test
```

---

## Source layout (high level)

| Path | Role |
|------|------|
| **`sim.f`** | RTL + **`verification/chi_integration_protocol_chk.sv`** (bind protocol asserts) + TB. |
| **`tb/tb_top.sv`** | Top, **`uvm_config_db`**, **`run_test()`**. |
| **`tb/chi_integration_if.sv`** | CHI REQ/RSP, **`bow_inj_*`**, **`err_*`** — driver/monitor modports. |
| **`uvm/chi_tb_pkg.sv`** | Agents, sequences, tests, **`inject_unknown_txn_rsp_hdr`**, **`drive_illegal_req_phase`**, **`chi_tb_cfg`**. |
| **`uvm/chi_tb_cov.svh`** | **`chi_integration_cov`** — included from **`chi_tb_pkg.sv`**. |

---

## `uvm_config_db` keys (`chi_tb_pkg`)

| Symbol | Typical use |
|--------|-------------|
| **`CHI_DB_SCOPE_ALL`** | **`"*"`** — wildcard scope for **`tb_top`** **`set(null, …)`**. |
| **`CHI_DB_KEY_VIF`** | **`"vif"`** — **`virtual chi_integration_if`**. |
| **`CHI_DB_KEY_TBCFG`** | **`"chi_tb_cfg"`** — pacing / drain knobs (**`chi_tb_cfg`**). |

Custom **`chi_tb_cfg`**: **`set(this, "", CHI_DB_KEY_TBCFG, cfg)`** in **`build_phase`** before **`super.build_phase`** in **`chi_base_test`** subclasses.

---

## Protocol checking

**`verification/chi_integration_protocol_chk.sv`** is listed in **`sim.f`** and **binds** into **`chi_to_bow_integration_top`**: REQ/RSP/`bow_inj` valid-hold rules (see **`vlate_bench/chi_proto.hpp`** for the Verilator-side twin).

---

## Golden constants

Cross-check **`verification/golden_payloads.py`**, **`chi_tb_pkg.sv`** (**`exp_read_data()`**, **`BOW_INJ_UNKNOWN_HDR_*`**), and **`vlate_bench/chi_tb.hpp`** when changing opcodes, txnids, or BoW flit layouts.

---

## Related docs

- **`README.md`** — full UVM bench documentation.
- **`UVM_ONBOARDING.md`** — TB/DUT figures, **`config_db`** flow, parity lane table, “where to edit”.
- **`docs/PLAN.md`** — scenario matrix and OSS / UVM parity policy.
- **`docs/design_spec.md`** — CHI/BoW abstraction.

PDFs: from repo root **`make docs`**, or **`make -C uvm_bench pdf`**.
