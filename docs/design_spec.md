# CHI to BoW Bridge Design Specification

## 1. Overview

This document specifies a starter CHI-to-BoW bridge RTL implementation used for
basic functional bring-up and integration testing.

The bridge accepts a simplified CHI request stream, packetizes transactions into
a fixed-width BoW flit, and reconstructs simplified CHI responses from BoW RX
traffic.

## 2. Scope and Assumptions

- Protocol model is intentionally simplified for rapid prototyping.
- Only one outstanding transaction is supported.
- BoW packetization uses a single 128-bit flit.
- Data payload is currently limited to 50 bits in the packet payload.
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

Single 128-bit flit encoding:

- `[127:124]` packet type
  - `0x1` request
  - `0x2` response
- `[123:122]` opcode
- `[121:114]` transaction ID
- `[113:50]` address
- `[49:0]` data payload (lower bits only)

## 5. Functional Behavior

### 5.1 CHI Request to BoW TX

When `chi_req_valid && chi_req_ready`:

- Bridge captures CHI request fields.
- Emits one BoW request flit on TX.
- Sets internal `req_pending` until matching response is received.

### 5.2 BoW RX to CHI Response

When `bow_rx_valid && bow_rx_ready` and packet type is response:

- Bridge maps opcode, txnid, and data into CHI response outputs.
- Asserts `chi_rsp_valid`.
- Clears `req_pending`.

### 5.3 Backpressure

- CHI request acceptance depends on:
  - no outstanding request
  - BoW TX path available (`bow_tx_ready`)
- BoW RX ready is gated by CHI response path availability.

## 6. Verification Plan (Implemented)

The Cocotb testbench validates:

1. Write path:
   - CHI write request creates expected BoW request flit fields.
   - Injected BoW write-ack creates expected CHI response.
2. Read path:
   - CHI read request creates expected BoW request flit fields.
   - Injected BoW read response creates expected CHI read response.

## 7. Known Limitations and Next Steps

- Extend payload handling to full data width using multi-flit transport.
- Add transaction table for multiple outstanding requests.
- Expand model toward separate CHI REQ/RSP/DAT channels.
- Add directed and randomized stress testing for backpressure and ordering.
