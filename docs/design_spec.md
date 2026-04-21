# CHI to BoW Bridge Design Specification

## 1. Overview

This document specifies a starter CHI-to-BoW bridge RTL implementation used for
basic functional bring-up and integration testing.

The bridge accepts a simplified CHI request stream, packetizes transactions into
BoW header/data flits, and reconstructs simplified CHI responses from BoW RX
traffic.

## 2. Scope and Assumptions

- Protocol model is intentionally simplified for rapid prototyping.
- Only one outstanding transaction is supported.
- BoW packetization uses v2 multi-flit framing.
- Full `DATA_WIDTH` payload is carried in data flits.
- CHI channels are abstracted to one request and one response interface.

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

- Bridge captures CHI request fields.
- Emits a request header flit on TX.
- For writes, emits a follow-on request data flit carrying full payload.
- Sets internal `req_pending` until matching response is received.

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
  - BoW TX path available (`bow_tx_ready`)
- BoW RX ready is gated by CHI response path availability.

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

## 7. Known Limitations and Next Steps

- Expand model toward separate CHI REQ/RSP/DAT channels.
- Add directed and randomized stress testing for backpressure and ordering.
