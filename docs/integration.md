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

**Port list** is the same as the bridge (CHI, clock, reset, and error / debug) except the BoW bus is
**internal** to the top (not exposed). Integrators can copy this top as a template or use the bridge
**without** the BFM and connect real BoW to `bow_tx` / `bow_rx`.

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

Both fail if any of `err_illegal_req_hdr`, `err_illegal_rsp_hdr`, `err_unknown_txn_rsp_hdr`,
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
