# CHI to BoW Bridge Design Specification

## 1. Overview

This document specifies a starter CHI-to-BoW bridge RTL implementation used for
basic functional bring-up and integration testing.

The bridge accepts a simplified CHI request stream, packetizes transactions into
BoW header/data flits, and reconstructs simplified CHI responses from BoW RX
traffic.

## 2. Scope and Assumptions

- Protocol model is intentionally simplified for rapid prototyping.
- Multiple outstanding transactions are supported, keyed by `txnid`.
- BoW packetization uses v2 multi-flit framing.
- Full `DATA_WIDTH` payload is carried in data flits.
- CHI channels are abstracted to one request and one response interface.
- Small ingress FIFOs decouple CHI request acceptance and BoW RX capture from
  downstream processing.

## 3. Module Interface

Module: `chi_to_bow_bridge`

- Clock/reset:
  - `clk`
  - `rst_n` (active low)
- Simplified CHI request ingress:
  - `chi_req_valid`, `chi_req_ready`
  - `chi_req_opcode` (`00` read, `01` write)
  - `chi_req_addr[63:0]`
  - `chi_req_data[63:0]`
  - `chi_req_txnid[7:0]`
- Simplified CHI response egress:
  - `chi_rsp_valid`, `chi_rsp_ready`
  - `chi_rsp_opcode` (`10` read response, `11` write ack)
  - `chi_rsp_data[63:0]`
  - `chi_rsp_txnid[7:0]`
- BoW transmit:
  - `bow_tx_valid`, `bow_tx_ready`
  - `bow_tx_data[127:0]`
- BoW receive:
  - `bow_rx_valid`, `bow_rx_ready`
  - `bow_rx_data[127:0]`

### 3.1 Error and debug observability

The bridge exposes saturating error counters and a single-cycle `err_pulse`
indicator (asserted in the same cycle as a counted error event) for
testbench visibility:

- `err_illegal_req_hdr`
- `err_illegal_rsp_hdr`
- `err_unknown_txn_rsp_hdr`
- `err_unknown_txn_rsp_data`
- `err_dup_rsp_hdr`
- `err_orphan_rsp_data`

Debug aids:

- `dbg_chi_req_fifo_used`
- `dbg_bow_rx_fifo_used`

## 4. BoW Packet Format

### 4.1 Flit Types

- `0x1` request header
- `0x2` request data
- `0x3` response header
- `0x4` response data

### 4.2 Header Flit Format (`REQ_HDR` / `RSP_HDR`)

- `[127:124]` packet type
- `[123:122]` opcode
- `[121:114]` transaction ID
- `[113]` has_data flag
- `[112:49]` address (used for request headers)
- `[48:0]` reserved

### 4.3 Data Flit Format (`REQ_DATA` / `RSP_DATA`)

- `[127:124]` packet type
- `[123:116]` transaction ID
- `[115:0]` data payload
  - payload uses `DATA_WIDTH` lower bits

## 5. Functional Behavior

### 5.1 CHI Request to BoW TX

When `chi_req_valid && chi_req_ready`:

- Bridge enqueues CHI request fields into an ingress FIFO.
- The TX formatter drains the FIFO and emits a request header flit on BoW TX.
- For writes, emits a follow-on request data flit carrying full payload.
- Marks the `txnid` as outstanding when the request header is emitted on BoW
  TX.

### 5.2 BoW RX to CHI Response

When `bow_rx_valid && bow_rx_ready` and packet type is response:

- For header-only responses (for example write-ack), bridge emits CHI response
  immediately.
- For data responses (for example read response), bridge waits for response data
  flit and emits full-width CHI response data.
- Asserts `chi_rsp_valid`.
- Clears `req_pending`.

### 5.3 Backpressure

- CHI request acceptance depends on:
  - free transaction table slot for incoming `txnid`
  - space in the CHI request ingress FIFO
- BoW RX ready indicates space in the BoW RX ingress FIFO.
- BoW TX emits flits only when `bow_tx_ready` is asserted (valid/ready
  handshake).

## 6. Verification Plan (Implemented)

The Cocotb testbench validates:

1. Write path:
   - CHI write request creates expected BoW request header and data flits.
   - Injected BoW write-ack header creates expected CHI response.
2. Read path:
   - CHI read request creates expected BoW request header flit.
   - Injected BoW read response header plus data flit creates expected CHI read
     response.
3. Out-of-order read completion:
   - Multiple outstanding reads with distinct `txnid` values can complete in any
     order, and responses are matched by `txnid`.
4. Randomized stress:
   - Randomized BoW TX and CHI response backpressure with scoreboard checking.
5. Illegal traffic:
   - Directed tests increment the appropriate error counters for malformed
     stimulus.

## 7. Known Limitations and Next Steps

- Expand model toward separate CHI REQ/RSP/DAT channels.
- Add richer randomized sequences (burst sizes, interleaved writes/reads).
