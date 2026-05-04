# Roadmap and next steps

This document tracks **suggested directions** for the CHI-to-BoW bridge repository alongside the technical notes in [design_spec.md](design_spec.md) (Section 7 outlines protocol-level "next steps"). It is regenerated to PDF by `make docs` in `docs/`.

## Current baseline

| Area | Status |
|------|--------|
| RTL | `chi_to_bow_bridge` with simplified CHI REQ/RSP, BoW flit packeting, outstanding-txn table, error counters |
| Cocotb | Unit tests (`test/`) and integration closed loop with `chi_to_bow_integration_top` + `bow_link_partner_bfm` (`integration/`) |
| Reference BFM | `bow_link_partner_bfm`: deterministic single- and multi-beat read/write completions (REQ_DATA / RSP_HDR+RSP_DATA choreography); no reordering or error injection |
| Documentation | `docs/design_spec.md`, `docs/integration.md`, **`docs/PLAN.md`**; PDFs via `docs/Makefile`; root **`make docs`** also builds **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`** (see **[`README.md`](../README.md)** for the authoritative list and commands) |
| UVM TB | `uvm_bench/`: `chi_smoke_test`, **`chi_burst_test`**, **`chi_illegal_req_test`** (VCS + UVM) vs integration top + BFM |
| Verilator TB | `vlate_bench/`: C++ smoke + **burst** + illegal-REQ **`err_*`** parity vs same integration top |
| CI (GitHub Actions) | **`test` job:** `make doctor && make` (Icarus cocotbs + Pandoc docs). **`vlate-bench` job:** Verilator **`lint`** (`--lint-only` on RTL + `tb_top.sv`) plus `make run`. **Does not** run VCS/UVM |

## OSS-first verification (no VCS)

When **Synopsys VCS is unavailable**, treat the repository as signed off against **OSS simulators only**. The **`uvm_bench`** tree remains valuable for licensees and for porting tests later; the **scenario matrix below still lists UVM** for parity, but your **effective** sign-off columns are Cocotb + Verilator until a licensed flow returns.

### Default stack

| Lane | Role |
|------|------|
| **Icarus + Cocotb** | Broadest behavior: block `test/` (directed + random stress) and integration `integration/`. This is the **primary functional truth** without VCS. |
| **Verilator** | **Lint** (`make -C vlate_bench lint`) + **C++ integration TB** (`make -C vlate_bench run`): fast closed-loop choreography and RTL compile sanity. Mirrors key integration scenarios coded in **`vlate_bench/tb_main.cpp`**. |
| **`make oss-regress`** | **`scripts/oss-regress.sh`**: **`make doctor`** + **`make`** + **`vlate_bench lint`** + **`run`**. Structural coverage regression: **`make oss-regress-coverage`** (= **`OSS_COVERAGE=1`** or **`--coverage`** on the script invokes **`make -C vlate_bench coverage`**). **`verilator`** (+ **`verilator_coverage`**) on `PATH`. |

### Coverage without VCS (incremental roadmap)

Structural coverage comes from **Verilator** (`--coverage`); functional completeness comes from the **scenario matrix +** Cocotb tests. Suggested progression:

1. **Keep expanding** directed + random Cocotb cases (especially integration **BoW fault** injections). Track scenario IDs in issues or in test docstrings.
2. **Verilator structural coverage**: **`make -C vlate_bench coverage`** (builds **`obj_dir_cov/`**, runs parity **`tb_main`**, writes **`verilator_coverage -write-info`** to **`vlate_coverage.info`** in **`vlate_bench/`**). Shortcut: **`make oss-regress-coverage`**, or **`OSS_COVERAGE=1 ./scripts/oss-regress.sh`**, or **`./scripts/oss-regress.sh --coverage`**.
3. **Icarus** does not merge into Verilator's coverage DB; combine **scenario matrix completeness** + **Verilator `.info`** for OSS sign-off.

```bash
make oss-regress-coverage
# or only:
make -C vlate_bench coverage
```

### UVM/VCS column (parity with OSS - not a divergent thread)

**OSS defines the integration behavioral baseline** (directed scenarios in **`integration/test_integration.py`** and shared constants in **`verification/golden_payloads.py`**). **Verilator (`vlate_bench/tb_main.cpp`)** mirrors that baseline in C++.

**`uvm_bench` must track the same integration scenarios:** whenever the matrix row for an integration scenario gains or changes behavior under **Cocotb** or **Verilator**, **`uvm/chi_tb_pkg.sv`** (sequences, driver timings, **`chi_*_test`** expectations) **and** **`docs/PLAN.md`** UVM cells must be updated **in the same PR** whenever practical; if deferred, link a follow-up issue and set the PLAN matrix UVM cell to **Planned - issue #...** until UVM catches up.

**Block-only Cocotb** (`test/` driving `chi_to_bow_bridge` with injected `bow_rx`) has **no UVM analogue** until a block-level SV TB exists; matrix marks **N/A**. UVM stays **integration-top only** unless the repo adds matching topology.

Licenses aside, **`uvm_bench/README.md`** lists the authoritative **OSS <-> Verilator <-> UVM** mapping; keep it aligned when adding tests.

## Verification taxonomy and matrix

Treat an **environment type** as topology x simulator x stimulus tier:

| Axis | Instances in this repo |
|------|------------------------|
| **Topology** | **Block:** `chi_to_bow_bridge` only. **Integration:** `chi_to_bow_integration_top` (bridge + `bow_link_partner_bfm`). |
| **Simulator / stack** | **Icarus + Cocotb** (`test/`, `integration/`). **Verilator + C++** (`vlate_bench/`). **Synopsys VCS + UVM** (`uvm_bench/`). |
| **Stimulus tier** | **Smoke:** directed happy path (single-beat and/or burst). **Deep directed:** error counters / illegal stimulus. **Stress:** constrained-random Cocotb (block-level today). |

### Scenario matrix

Rows are named scenarios (golden txnids/beats aligned with **`verification/golden_payloads.py`** where applicable - see SV/C++ cross-references in `chi_tb_pkg.sv` and `chi_tb.hpp`). Columns list where the scenario is automated and how to invoke it.

| Scenario | Topology | Block Cocotb `test/` | Integration Cocotb `integration/` | UVM `uvm_bench/` | Verilator `vlate_bench/` |
|----------|----------|---------------------|-------------------------------------|------------------|---------------------------|
| Single-beat read + write smoke (BFM / completions) | Integration | - | Implemented - `make integration-test` -> `test_integration_bfm_completes_smoke` | Implemented - `make run UVM_TEST=chi_smoke_test` | Implemented - built into `tb_main.cpp` (after reset) |
| Burst write + read (`0x71`/`0x72`, 3 / 4 beats) | Integration | - | Implemented - `test_integration_bfm_burst_through_top` | Implemented - `make run UVM_TEST=chi_burst_test` | Implemented - tail of `tb_main.cpp` |
| Illegal REQ opcodes increment `err_illegal_req_hdr` + `err_pulse` (READ_RESP / WRITE_ACK on REQ) | Integration | - | Implemented - `test_integration_illegal_chi_req_opcodes_increment_err_counter` | Implemented - `make run UVM_TEST=chi_illegal_req_test` | Implemented - tail of `tb_main.cpp`: `inject_unknown_txn_rsp_hdr`, then double `drive_illegal_req_phase` |

### Integration BoW inject mux scenarios

| Scenario | Topology | Block Cocotb `test/` | Integration Cocotb `integration/` | Verilator `vlate_bench/` |
|----------|----------|----------------------|-----------------------------------|---------------------------|
| Unknown txnid BoW `RSP_HDR` bumps `err_unknown_txn_rsp_hdr` | Integration | - | Implemented - `test_integration_unknown_txnid_bow_rsp_hdr_via_inj` | Implemented - `inject_unknown_txn_rsp_hdr` |
| Illegal BoW `RSP_HDR` framing (`WRITE_ACK has_data=1`, `READ_RESP has_data=0`) increments `err_illegal_rsp_hdr` and is dropped without completing or mutating the txn | Block | Implemented - `test_illegal_rsp_headers_are_dropped_without_side_effects` | - | - |
| Write / read BoW choreography, bursts, FIFO, broader illegals (`bow_rx` inject) | Block | Implemented - `make test` | - | - |

**Stress / randomized** cases run only under **block** Cocotb (`test/test_chi_to_bow_bridge.py`); integration UVM and Verilator benches remain directed. **Formal / second simulator (Cocotb + Verilator)** for the block suite is intentionally **not** in default CI - see **CI and regression expansion** below.

## RTL milestones (ordered)

When extending the chip model, work through RTL in roughly this order and update the **scenario matrix**, BFMs, and **`verification/golden_payloads.py`** in the same change set:

1. **REQ_DATA uniqueness** - distinct beats per burst write (`chi_req_*` widen or sequencing) updates BFM ingest, Cocotb packet checks, integration driver/sequences, C++ driver, scoreboards.
2. **CHI channel split** - separate REQ/RSP/DAT abstraction updates `chi_integration_if`, **`chi_to_bow_integration_top`**, all three integration TB stacks, docs.
3. **Multi-master / QoS** - new integration **topology** (arbitrated top): new file list row, dedicated matrix row, TB env type.
4. **Sign-off** - FPGA or vendor STA as needed; tighten Verilator waiver policy alongside `lint` baseline.

See also [design_spec.md](design_spec.md) Section 7 ("Known limitations").

## CI and regression expansion

| Gate | Runs in CI? | Notes |
|------|-------------|--------|
| Icarus + Cocotb + docs (`make`) | Yes - `test` job | Principal functional regression. |
| Verilator **`make -C vlate_bench lint`** + **`run`** | Yes - **`vlate-bench`** job | OSS lint-only on bridge + integration + `tb_top`; C++ parity smoke+burst+illegal. |
| VCS + UVM | No (runner) | Parity TB: must stay aligned with Cocotb + **Verilator** integration scenarios per **UVM-OSS parity** below. **`make -C uvm_bench run`** locally when licensed; optional **`make -C uvm_bench coverage`** + **`cov-report`** (**URG**) for VCM structural DB (**`uvm_cov.vdb`**). Functional covergroups: **`chi_integration_cov`** in **`uvm/chi_tb_cov.svh`**. |

**UVM-OSS parity (integration):** Rows in the scenario matrix whose **topology** is **Integration** shall list **consistent** behavior across **Integration Cocotb**, **Verilator `vlate_bench`**, and **UVM** (same txnids, beats, pacing intent, illegal-opcode choreography, and scoreboard rules where applicable). **Primary reference:** **`integration/test_integration.py`**; **second witness:** **`vlate_bench/tb_main.cpp`**; **UVM implementation:** **`uvm_bench/uvm/chi_tb_pkg.sv`** (includes **`chi_tb_cov.svh`** for **`chi_integration_cov`**) plus tests in **`chi_tb_pkg.sv`**. See **[`uvm_bench/README.md`](../uvm_bench/README.md)** ("Stay synchronized with OSS") for the explicit mapping table.

**Cocotb + Verilator (block topology):** plausible duplicate of `test/` for OSS confidence but duplicate compile/runtime cost; defer unless simulator diversity becomes a release requirement - keep **Icarus** as canonical block runner until then.

**Long regressions:** if random Cocotb seed runtime grows, add a pytest/marked target or **`make cocotb-long`** invoked nightly, not blocking default PR gates.

## Recently completed

- **README versus tooling** - The root **[`README.md`](../README.md)** now documents `uvm_bench/` and `vlate_bench/`, the full **`make docs`** PDF outputs (spec/integration/plan PDFs under `docs/` plus **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`**), optional prerequisites (VCS / Verilator), a verification-environment summary table, subdirectory commands, and links to this **`PLAN.md`** for backlog context.
- **CI - Verilator bench** - [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) **`vlate-bench`** runs **`make -C vlate_bench lint`** then **`run`**. VCS/UVM remains local-only.
- **Bursts on integration path** - `bow_link_partner_bfm` absorbs multi-beat writes and emits multi-beat read responses; Cocotb (**`test_integration_bfm_burst_through_top`**), UVM (**`chi_burst_test`**), and **`vlate_bench`** run the same directed 3/4-beat scenario alongside single-beat smoke.
- **Error-path (integration)** - **`test_integration_illegal_chi_req_opcodes_increment_err_counter`** drives illegal CHI request-channel opcodes through **`chi_to_bow_integration_top`**, asserts **`err_illegal_req_hdr`**, and checks **`err_pulse`** (sampled after the clock edge settles on each violation). Unit **`test/`** still covers broader BoW-side illegals with direct **`bow_rx`** access.
- **Golden payloads (Python)** - **`verification/golden_payloads.py`** centralizes CHI opcode / BoW packet-type constants and **`bfm_read_data_u64`** for Cocotb; SV (**`bow_link_partner_bfm`**, **`chi_tb_pkg.sv`**) and C++ (**`chi_tb.hpp`**) carry cross-references to keep layouts aligned.
- **UVM-OSS parity policy** - Integration **`uvm_bench`** must stay aligned with **Integration Cocotb** and **`vlate_bench`** (**`docs/PLAN.md`**, **`uvm_bench/README.md`** mapping table); [`.github/pull_request_template.md`](../.github/pull_request_template.md) reminds authors to update UVM when OSS integration scenarios drift.
- **Verilator structural coverage** - **`make -C vlate_bench coverage`** / **`make oss-regress-coverage`**: **`VerilatedCov::write()`**, **`verilator_coverage -write-info`** -> **`vlate_coverage.info`**. **`scripts/oss-regress.sh`** supports **`OSS_COVERAGE=1`** / **`--coverage`**.
- **UVM functional + optional VCS structural coverage** - **`chi_integration_cov`** (**`uvm_bench/uvm/chi_tb_cov.svh`**) reports REQ/RSP handshake bins in **`sim.log`**; **`make -C uvm_bench coverage`** adds Synopsys **`-cm`** instrumentation (**`uvm_cov.vdb`**), **`make -C uvm_bench cov-report`** runs **URG** when installed.
- **Integration BoW inject mux** - **`chi_to_bow_integration_top`** **`bow_inj_*`** drives bridge **`bow_rx`** when asserted (BFM stalled); Cocotb **`test_integration_unknown_txnid_bow_rsp_hdr_via_inj`** and **`inject_unknown_txn_rsp_hdr`** in **`vlate_bench/tb_main.cpp`** parity block **`bow_rx`** unknown-txn hdr fault.
- **Illegal BoW response-header quarantine (block)** - **`chi_to_bow_bridge`** now drops malformed response headers after incrementing **`err_illegal_rsp_hdr`**: **`WRITE_ACK has_data=1`** no longer creates **`rsp_need_data`**, and **`READ_RESP has_data=0`** no longer emits **`chi_rsp_valid`** or clears **`pending_txn`**. Cocotb **`test_illegal_rsp_headers_are_dropped_without_side_effects`** proves each affected txn can still complete from a later well-formed response.

## Recommended near-term actions

1. **Deeper integration error-path checks** - Promote more block-level BoW ingress fault scenarios onto **`chi_to_bow_integration_top`** via **`bow_inj_*`** (illegal response-header quarantine, dup/orphan payloads, etc.) and mirror the highest-value rows in **`vlate_bench`**. Today integration/Verilator cover unknown-txn **`RSP_HDR`** injection; optional randomized Cocotb can follow after directed parity is in place.

2. **Optional: machine-readable export** - Generate a minimal header/constants file from **`golden_payloads.py`** (script) if drift becomes painful; manual comments remain the baseline.

## Medium-term directions

| Theme | Aim |
|-------|-----|
| CHI fidelity | Split request/response/data channels and closer opcode/datapath mapping (per design spec assumptions) |
| Write data path | Distinct beats per REQ_DATA beyond repeated `chi_req_data` |
| QoS / fairness | Arbiter/backpressure modeling if bridging multiple sources |
| Synthesis readiness | Lint (Verilator/`verilator --lint-only`, vendor ASIC), clocks/resets constraints, FPGA trial if desired |

## Longer horizon

- Industry or partner BoW/CHI compliance suites (where applicable) as the abstracted CHI model matures.
- Performance modeling (throughput vs FIFO depth, credit-based link partner).
- Power-aware or physical-link assumptions if the die-to-die path becomes cycle-accurate.

## How to use this file

- **Planning**: Treat sections above as a backlog; convert items into issues/PRs with acceptance criteria.
- **PDF**: From `docs/`, `make pdf` builds `PLAN.pdf` together with the other spec PDFs.
- **Updates**: Revise this file when major verification or RTL milestones land; keep the "Current baseline" table honest about what CI and local flows actually run.
