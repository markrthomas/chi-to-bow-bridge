# Roadmap and next steps

This document tracks **suggested directions** for the CHI-to-BoW bridge repository alongside the technical notes in [design_spec.md](design_spec.md) (Section 7 outlines protocol-level “next steps”). It is regenerated to PDF by `make docs` in `docs/`.

## Current baseline

| Area | Status |
|------|--------|
| RTL | `chi_to_bow_bridge` with simplified CHI REQ/RSP, BoW flit packeting, outstanding-txn table, error counters |
| Cocotb | Unit tests (`test/`) and integration closed loop with `chi_to_bow_integration_top` + `bow_link_partner_bfm` (`integration/`) |
| Reference BFM | Single-beat-centric; burst paths need explicit extension to match full RTL capabilities |
| Documentation | `docs/design_spec.md`, `docs/integration.md`, **`docs/PLAN.md`**; PDFs via `docs/Makefile`; root **`make docs`** also builds **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`** (see **[`README.md`](../README.md)** for the authoritative list and commands) |
| UVM TB | `uvm_bench/`: VCS + UVM smoke path (single-beat smoke, scoreboard vs BFM read data) |
| Verilator TB | `vlate_bench/`: C++ parity smoke vs same integration top |
| CI (GitHub Actions) | `make doctor && make`: Icarus Cocotbs + Pandoc docs; **does not** run VCS/UVM |

## Recently completed

- **README versus tooling** — The root **[`README.md`](../README.md)** now documents `uvm_bench/` and `vlate_bench/`, the full **`make docs`** PDF outputs (spec/integration/plan PDFs under `docs/` plus **`uvm_bench/README.pdf`** and **`vlate_bench/README.pdf`**), optional prerequisites (VCS / Verilator), a verification-environment summary table, subdirectory commands, and links to this **`PLAN.md`** for backlog context.

## Recommended near-term actions

1. **Optional CI expansion** — Add a parallel job that installs OSS Verilator and runs `make -C vlate_bench run` (no license). Keeps parity smoke from regressing on every push. Omit Synopsys VCS from CI unless a runner policy allows it.
2. **Extend verification around bursts** — RTL supports multi-beat read/write (`chi_req_beats`, `beats-1` in headers). Extend `bow_link_partner_bfm` (or replace with a parametric responder) plus Cocotb + UVM/Verilator scoreboards so all three environments exercise the **same** multi-beat scenarios.
3. **Error-path coverage** — Add directed Cocotb (or randomized) tests aligned with §6/§7 illegal-traffic bullets; assert counters and `err_pulse` with stable reference values.
4. **Formalize “golden” payloads** — Centralize expected BoW flit layouts and BFM read data in one include or small package mirrored in C++/Python helpers to prevent drift among Cocotb, UVM, and Verilator.

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
