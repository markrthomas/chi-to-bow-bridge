# Integration guide

This document is the integration addendum for `chi_to_bow_bridge`: how to connect it in a larger SoC
or FPGA image, and how to use the in-repo **reference** link partner.

## Clocking and reset

- **Single clock domain**: The bridge, CHI, and BoW ports are all synchronous to `clk` (same edge;
  the RTL uses positive edge).
- **Reset**: `rst_n` is active-low, asynchronous in this module (asynchronous assertion/deassertion is
  typical for fab bring-up; confirm against your top-level tree).
- If CHI and BoW come from different clock domains, insert **CDC** (async FIFOs or a validated
  synchronizer network) at your top level—this repository does not include cross-domain hardware.

## Parameters

| Name          | Default | Notes                                                |
|---------------|---------|------------------------------------------------------|
| `ADDR_WIDTH`  | 64      | CHI request address field width                      |
| `DATA_WIDTH`  | 64      | CHI and BoW data-beat width (low bits in 128b flits) |
| `FIFO_DEPTH`  | 4       | CHI and BoW ingress FIFOs (per direction)            |

For a given tape-out or bitstream, **freeze** these (and document) so downstream timing constraints
and verification match.

## Verification environments

Which simulators exercise which scenarios (taxonomy + matrix) lives in **`docs/PLAN.md`**. Use that file together with **`integration/README.md`** when extending integration tests so **Cocotb**, **Verilator**, and **UVM** stay aligned.

## File lists for EDA

Run tools from the **repository root** (paths in the `.f` files are relative to the root).

- **Bridge RTL only (no partner):** [`src/files.f`](../src/files.f) — use for synthesis of the
  leaf block or when the partner lives outside the repo.
- **Bridge + in-repo BFM (simulation / demo top):** [`integration/files.f`](../integration/files.f) —
  includes `chi_to_bow_integration_top` and `bow_link_partner_bfm` for a closed loop.

Example compile (Icarus):

```bash
iverilog -g2012 -f src/files.f
# or, integration-style sim top:
iverilog -g2012 -f integration/files.f
```

(Replace with your tool’s `read_verilog` / `analyze` as appropriate.)

## `chi_to_bow_integration_top`

`integration/chi_to_bow_integration_top.v` instantiates:

1. `chi_to_bow_bridge` — the deliverable IP.
2. `bow_link_partner_bfm` — a **small behavioral model** of the far-side link that closes the BoW
   loop in simulation.

**Port list:** CHI REQ/RSP, clocks, reset, **`err_*`**, and **`dbg_*`** mirror **`chi_to_bow_bridge`**. The **`bow_tx`/`bow_rx` link between **`chi_to_bow_bridge`** and **`bow_link_partner_bfm`** is internal (**not breakout pins**) so Cocotb can close-loop deterministically without binding.

Five optional injector pins (**`bow_inj_en`**, **`bow_inj_valid`**, **`bow_inj_ready`**, **`bow_inj_data_hi`**, **`bow_inj_data_lo`**) multiplex a TB-driven **128-bit** flit (two **64-bit** halves) onto the bridge **`bow_rx` input when **`bow_inj_en`** is asserted; the partner BFM **`s_rx` port is stalled while injecting. With **`bow_inj_en`** held low (default normal path), keep **`bow_inj_valid`** low and ignore the data halves.

Tape-out hierarchies without fault injection should tie **`bow_inj_en`** low permanently (or regenerate a thinner top exporting raw **`bow_tx`/`bow_rx`** without inject hooks).


### Reference BFM scope

- Implements **deterministic completions** for full-size CHI bursts on the REQ channel (multi-beat
  writes absorb every `REQ_DATA` flit; multi-beat reads reply with matching `beats-1` on `RSP_HDR`
  and the corresponding number of `RSP_DATA` beats). Payloads follow the deterministic `DATA_WIDTH`
  layout in **`bow_link_partner_bfm`** (same canonical read pattern exercised by Cocotb, UVM, and Verilator benches).
- Does **not** model reordering, errors, or protocol violations beyond happy-path completion per transaction.
- Replace with your die-to-die / PHY partner (or fuller BFM) for system-scale validation.


## Running the integration sim

From the repository root:

```bash
make integration-test
```

This runs the Cocotb tests in `integration/test_integration.py` against `chi_to_bow_integration_top`.

1. **`test_integration_bfm_completes_smoke`** — single-beat read and write on CHI REQ; asserts read data (`bow_link_partner_bfm`) and write-ack.
2. **`test_integration_bfm_burst_through_top`** — multi-beat write/read through the integration top matching the burst-capable reference BFM.
3. **`test_integration_illegal_chi_req_opcodes_increment_err_counter`** - driven illegal CHI request-channel opcodes; **`err_pulse`** / **`err_illegal_req_hdr`**.
4. **`test_integration_unknown_txnid_bow_rsp_hdr_via_inj`** - unknown-txnid **`RSP_HDR`** on **`bow_inj_*`** asserts **`err_unknown_txn_rsp_hdr`** (see block-level illegal BoW sequence parity in **`test/test_chi_to_bow_bridge.py`**).

Smoke **(1)** and burst **(2)** fail if any of `err_illegal_req_hdr`, `err_illegal_rsp_hdr`, `err_unknown_txn_rsp_hdr`,
`err_unknown_txn_rsp_data`, `err_dup_rsp_hdr`, or `err_orphan_rsp_data` is non-zero (wrap-safe at
32 bits; see design spec).

## Replacing the BFM in silicon/FPGA

- Map `bow_tx_*` to your serializer / link IP transmit path.
- Map `bow_rx_*` to your deserializer / receive path.
- Keep the same 128b flit layout and handshake semantics as the unit-level tests (see
  `docs/design_spec.md`).

## Versioning

When the flit layout or `chi_req_beats` rules change, **tag a release** and update this addendum so
a partner team can key their RTL/verification to a specific revision.
