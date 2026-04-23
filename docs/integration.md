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

- Models **only single-beat** read and write (request `beats-1` / response burst field must be 0 in
  the path this BFM handles).
- Does **not** model reordering, errors, or protocol violations on the link.
- Replace with your die-to-die or PHY partner model (or BFM) for system validation.

## Running the integration sim

From the repository root:

```bash
make integration-test
```

This runs the Cocotb test in `integration/test_integration.py` against
`chi_to_bow_integration_top`. The test:

1. Drives a single-beat read and a single-beat write on the CHI request interface.
2. Asserts the expected CHI read data (matches the deterministic pattern in
   `bow_link_partner_bfm.v`) and write-ack behavior.
3. Fails if any of `err_illegal_req_hdr`, `err_illegal_rsp_hdr`, `err_unknown_txn_rsp_hdr`,
   `err_unknown_txn_rsp_data`, `err_dup_rsp_hdr`, or `err_orphan_rsp_data` is non-zero (wrap-safe at
  32 bits—see main design spec).

## Replacing the BFM in silicon/FPGA

- Map `bow_tx_*` to your serializer / link IP transmit path.
- Map `bow_rx_*` to your deserializer / receive path.
- Keep the same 128b flit layout and handshake semantics as the unit-level tests (see
  `docs/design_spec.md`).

## Versioning

When the flit layout or `chi_req_beats` rules change, **tag a release** and update this addendum so
a partner team can key their RTL/verification to a specific revision.
