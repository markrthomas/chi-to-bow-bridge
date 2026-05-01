# Roadmap and next steps

This document tracks **suggested directions** for the CHI-to-BoW bridge repository alongside the technical notes in [design_spec.md](design_spec.md) (Section 7 outlines protocol-level “next steps”). It is regenerated to PDF by `make docs` in `docs/`.

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

## Verification taxonomy and matrix

Treat an **environment type** as topology × simulator × stimulus tier:

| Axis | Instances in this repo |
|------|------------------------|
| **Topology** | **Block:** `chi_to_bow_bridge` only. **Integration:** `chi_to_bow_integration_top` (bridge + `bow_link_partner_bfm`). |
| **Simulator / stack** | **Icarus + Cocotb** (`test/`, `integration/`). **Verilator + C++** (`vlate_bench/`). **Synopsys VCS + UVM** (`uvm_bench/`). |
| **Stimulus tier** | **Smoke:** directed happy path (single-beat and/or burst). **Deep directed:** error counters / illegal stimulus. **Stress:** constrained-random Cocotb (block-level today). |

### Scenario matrix

Rows are named scenarios (golden txnids/beats aligned with **`verification/golden_payloads.py`** where applicable — see SV/C++ cross-references in `chi_tb_pkg.sv` and `chi_tb.hpp`). Columns list where the scenario is automated and how to invoke it.

| Scenario | Topology | Block Cocotb `test/` | Integration Cocotb `integration/` | UVM `uvm_bench/` | Verilator `vlate_bench/` |
|----------|----------|---------------------|-------------------------------------|------------------|---------------------------|
| Single-beat read + write smoke (BFM / completions) | Integration | — | Implemented — `make integration-test` → `test_integration_bfm_completes_smoke` | Implemented — `make run UVM_TEST=chi_smoke_test` | Implemented — built into `tb_main.cpp` (after reset) |
| Burst write + read (`0x71`/`0x72`, 3 / 4 beats) | Integration | — | Implemented — `test_integration_bfm_burst_through_top` | Implemented — `make run UVM_TEST=chi_burst_test` | Implemented — tail of `tb_main.cpp` |
| Illegal REQ opcodes increment `err_illegal_req_hdr` + `err_pulse` (READ_RESP / WRITE_ACK on REQ) | Integration | — | Implemented — `test_integration_illegal_chi_req_opcodes_increment_err_counter` | Implemented — `make run UVM_TEST=chi_illegal_req_test` | Implemented — end of `tb_main.cpp` (no scoreboard expect) |
| Write / read BoW choreography, bursts, FIFO, illegals (`bow_rx` inject) | Block | Implemented — `make test` | — | — (not applicable) | — |

**Stress / randomized** cases run only under **block** Cocotb (`test/test_chi_to_bow_bridge.py`); integration UVM and Verilator benches remain directed. **Formal / second simulator (Cocotb + Verilator)** for the block suite is intentionally **not** in default CI — see § CI and regression expansion below.

## RTL milestones (ordered)

When extending the chip model, work through RTL in roughly this order and update the **scenario matrix**, BFMs, and **`verification/golden_payloads.py`** in the same change set:

1. **REQ_DATA uniqueness** — distinct beats per burst write (`chi_req_*` widen or sequencing) updates BFM ingest, Cocotb packet checks, integration driver/sequences, C++ driver, scoreboards.
2. **CHI channel split** — separate REQ/RSP/DAT abstraction updates `chi_integration_if`, **`chi_to_bow_integration_top`**, all three integration TB stacks, docs.
3. **Multi-master / QoS** — new integration **topology** (arbitrated top): new file list row, dedicated matrix row, TB env type.
4. **Sign-off** — FPGA or vendor STA as needed; tighten Verilator waiver policy alongside `lint` baseline.

See also [design_spec.md](design_spec.md) §7 (“Known limitations”).

## CI and regression expansion

| Gate | Runs in CI? | Notes |
|------|-------------|--------|
| Icarus + Cocotb + docs (`make`) | Yes — `test` job | Principal functional regression. |
| Verilator **`make -C vlate_bench lint`** + **`run`** | Yes — **`vlate-bench`** job | OSS lint-only on bridge + integration + `tb_top`; C++ parity smoke+burst+illegal. |
| VCS + UVM | No | Requires license (local **`make -C uvm_bench run**`). |

**Cocotb + Verilator (block topology):** plausible duplicate of `test/` for OSS confidence but duplicate compile/runtime cost; defer unless simulator diversity becomes a release requirement — keep **Icarus** as canonical block runner until then.

**Long regressions:** if random Cocotb seed runtime grows, add a pytest/marked target or **`make cocotb-long`** invoked nightly, not blocking default PR gates.

## Recently completed

- **README versus tooling** — The root **[`README.md`](../README.md)** now documents `uvm_bench/` and `vlate_bench/`, the full **`make docs`** PDF outputs (spec/integration/plan PDFs under `docs/` plus **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`**), optional prerequisites (VCS / Verilator), a verification-environment summary table, subdirectory commands, and links to this **`PLAN.md`** for backlog context.
- **CI — Verilator bench** — [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) **`vlate-bench`** runs **`make -C vlate_bench lint`** then **`run`**. VCS/UVM remains local-only.
- **Bursts on integration path** — `bow_link_partner_bfm` absorbs multi-beat writes and emits multi-beat read responses; Cocotb (**`test_integration_bfm_burst_through_top`**), UVM (**`chi_burst_test`**), and **`vlate_bench`** run the same directed 3/4-beat scenario alongside single-beat smoke.
- **Error-path (integration)** — **`test_integration_illegal_chi_req_opcodes_increment_err_counter`** drives illegal CHI request-channel opcodes through **`chi_to_bow_integration_top`**, asserts **`err_illegal_req_hdr`**, and checks **`err_pulse`** (sampled after the clock edge settles on each violation). Unit **`test/`** still covers broader BoW-side illegals with direct **`bow_rx`** access.
- **Golden payloads (Python)** — **`verification/golden_payloads.py`** centralizes CHI opcode / BoW packet-type constants and **`bfm_read_data_u64`** for Cocotb; SV (**`bow_link_partner_bfm`**, **`chi_tb_pkg.sv`**) and C++ (**`chi_tb.hpp`**) carry cross-references to keep layouts aligned.

## Recommended near-term actions

1. **Deeper error-path checks** — Broader BoW ingress fault injection on the integration top ( **`bow_rx`** not exposed today) via SV bind or additional top-level tie-offs; optional randomized Cocotb beyond directed cases.

2. **Optional: machine-readable export** — Generate a minimal header/constants file from **`golden_payloads.py`** (script) if drift becomes painful; manual comments remain the baseline.

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
- **Updates**: Revise this file when major verification or RTL milestones land; keep the “Current baseline” table honest about what CI and local flows actually run.
