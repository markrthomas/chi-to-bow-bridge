# Roadmap and next steps

This document tracks **suggested directions** for the CHI-to-BoW bridge repository alongside the technical notes in [design_spec.md](design_spec.md) (Section 7 outlines protocol-level “next steps”). It is regenerated to PDF by `make docs` in `docs/`.

## Current baseline

| Area | Status |
|------|--------|
| RTL | `chi_to_bow_bridge` with simplified CHI REQ/RSP, BoW flit packeting, outstanding-txn table, error counters |
| Cocotb | Unit tests (`test/`) and integration closed loop with `chi_to_bow_integration_top` + `bow_link_partner_bfm` (`integration/`) |
| Reference BFM | `bow_link_partner_bfm`: deterministic single- and multi-beat read/write completions (REQ_DATA / RSP_HDR+RSP_DATA choreography); no reordering or error injection |
| Documentation | `docs/design_spec.md`, `docs/integration.md`, **`docs/PLAN.md`**; PDFs via `docs/Makefile`; root **`make docs`** also builds **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`** (see **[`README.md`](../README.md)** for the authoritative list and commands) |
| UVM TB | `uvm_bench/`: `chi_smoke_test` + **`chi_burst_test`** (VCS + UVM) vs integration top + BFM |
| Verilator TB | `vlate_bench/`: C++ smoke + **burst** parity vs same integration top |
| CI (GitHub Actions) | **`test` job:** `make doctor && make` (Icarus cocotbs + Pandoc docs). **`vlate-bench` job:** Verilator + `make -C vlate_bench run`. **Does not** run VCS/UVM |

## Recently completed

- **README versus tooling** — The root **[`README.md`](../README.md)** now documents `uvm_bench/` and `vlate_bench/`, the full **`make docs`** PDF outputs (spec/integration/plan PDFs under `docs/` plus **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`**), optional prerequisites (VCS / Verilator), a verification-environment summary table, subdirectory commands, and links to this **`PLAN.md`** for backlog context.
- **CI — Verilator bench** — [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) includes a parallel **`vlate-bench`** job (`verilator` + **`make -C vlate_bench run`**). VCS/UVM remains local-only.
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
