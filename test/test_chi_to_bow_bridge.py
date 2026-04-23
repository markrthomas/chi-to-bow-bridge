import cocotb
import random
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CHI_OP_READ = 0b00
CHI_OP_WRITE = 0b01
CHI_OP_READ_RESP = 0b10
CHI_OP_WRITE_ACK = 0b11

PKT_TYPE_REQ_HDR = 0x1
PKT_TYPE_REQ_DATA = 0x2
PKT_TYPE_RSP_HDR = 0x3
PKT_TYPE_RSP_DATA = 0x4


async def wait_for_tx_flit(dut, max_cycles=8):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.bow_tx_valid.value) == 1:
            return int(dut.bow_tx_data.value)
    raise AssertionError("Timed out waiting for bow_tx_valid")


async def drive_req_until_accepted(dut, opcode, addr, data, txnid, beats=1, max_cycles=16):
    dut.chi_req_opcode.value = opcode
    dut.chi_req_addr.value = addr
    dut.chi_req_data.value = data
    dut.chi_req_beats.value = beats
    dut.chi_req_txnid.value = txnid
    dut.chi_req_valid.value = 1
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.chi_req_ready.value) == 1:
            dut.chi_req_valid.value = 0
            return
    dut.chi_req_valid.value = 0
    raise AssertionError("Timed out waiting for chi_req_ready")


async def recv_chi_response(dut, max_cycles=32):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.chi_rsp_valid.value) == 1:
            return (
                int(dut.chi_rsp_opcode.value),
                int(dut.chi_rsp_txnid.value),
                int(dut.chi_rsp_data.value),
            )
    raise AssertionError("Timed out waiting for chi_rsp_valid")


async def wait_until_txnid_pending(dut, txnid, max_cycles=256):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.dbg_pending_txn.value) & (1 << txnid):
            return
    raise AssertionError(f"Timed out waiting for txnid 0x{txnid:02x} to become pending")


async def wait_until_counter_eq(dut, name, expected, max_cycles=32):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(getattr(dut, name).value) == expected:
            return
    raise AssertionError(f"Timed out waiting for {name} == {expected}")


async def send_bow_flit_until_accepted(dut, flit, max_cycles=64, rng=None):
    dut.bow_rx_data.value = flit
    for cycle in range(max_cycles):
        if rng is None:
            dut.bow_rx_valid.value = 1
        else:
            dut.bow_rx_valid.value = 1 if rng.randrange(100) < 60 else 0

        await RisingEdge(dut.clk)
        if int(dut.bow_rx_valid.value) == 1 and int(dut.bow_rx_ready.value) == 1:
            dut.bow_rx_valid.value = 0
            return
    dut.bow_rx_valid.value = 0
    raise AssertionError("Timed out waiting for bow_rx handshake")


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.chi_req_valid.value = 0
    dut.chi_req_opcode.value = 0
    dut.chi_req_addr.value = 0
    dut.chi_req_data.value = 0
    dut.chi_req_beats.value = 1
    dut.chi_req_txnid.value = 0
    dut.chi_rsp_ready.value = 0
    dut.bow_tx_ready.value = 0
    dut.bow_rx_valid.value = 0
    dut.bow_rx_data.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_zero_beats_request_not_enqueued(dut):
    """chi_req_beats=0 does not enqueue; CHI FIFO empty and no BoW TX for that stimulus."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    dut.chi_req_opcode.value = CHI_OP_READ
    dut.chi_req_addr.value = 0x1000
    dut.chi_req_data.value = 0
    dut.chi_req_beats.value = 0
    dut.chi_req_txnid.value = 0x05
    dut.chi_req_valid.value = 1

    for _ in range(8):
        await RisingEdge(dut.clk)
        assert int(dut.dbg_chi_req_fifo_used.value) == 0
        assert int(dut.bow_tx_valid.value) == 0
        assert (int(dut.dbg_pending_txn.value) & (1 << 0x05)) == 0

    dut.chi_req_valid.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def test_write_request_and_ack(dut):
    """Drive CHI WRITE, observe header+data flits, inject ACK header, observe CHI response."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    addr = 0x1234_5678_9ABC_DEF0
    data = 0xDEAD_BEEF_CAFE_BABE
    txnid = 0x3C

    # Drive one CHI write request.
    await drive_req_until_accepted(dut, CHI_OP_WRITE, addr, data, txnid)

    # Request header appears on BoW TX.
    hdr = await wait_for_tx_flit(dut)

    hdr_type = (hdr >> 124) & 0xF
    hdr_opcode = (hdr >> 122) & 0x3
    hdr_txnid = (hdr >> 114) & 0xFF
    hdr_has_data = (hdr >> 113) & 0x1
    hdr_addr = (hdr >> 49) & ((1 << 64) - 1)

    assert hdr_type == PKT_TYPE_REQ_HDR
    assert hdr_opcode == CHI_OP_WRITE
    assert hdr_txnid == txnid
    assert hdr_has_data == 1
    assert hdr_addr == addr
    assert (hdr & 0xFF) == 0  # beats-1 encoded in REQ_HDR reserved low byte (1 beat => 0)

    # Request data flit should follow.
    data_flit = await wait_for_tx_flit(dut)
    data_type = (data_flit >> 124) & 0xF
    data_txnid = (data_flit >> 116) & 0xFF
    data_payload = data_flit & ((1 << 64) - 1)

    assert data_type == PKT_TYPE_REQ_DATA
    assert data_txnid == txnid
    assert data_payload == data

    # Inject a BoW write-ack response.
    resp_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_WRITE_ACK << 122)
        | (txnid << 114)
        | (0 << 113)
    )
    await send_bow_flit_until_accepted(dut, resp_hdr)

    dut.chi_rsp_ready.value = 1
    op, tid, dat = await recv_chi_response(dut)
    assert op == CHI_OP_WRITE_ACK
    assert tid == txnid
    assert dat == 0


@cocotb.test()
async def test_read_request_and_data_response(dut):
    """Drive CHI READ, then inject response header+data and check CHI read response."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    addr = 0x0BAD_F00D_1234_0008
    txnid = 0x77

    await drive_req_until_accepted(dut, CHI_OP_READ, addr, 0, txnid)

    hdr = await wait_for_tx_flit(dut)
    assert ((hdr >> 124) & 0xF) == PKT_TYPE_REQ_HDR
    assert ((hdr >> 122) & 0x3) == CHI_OP_READ
    assert ((hdr >> 114) & 0xFF) == txnid
    assert ((hdr >> 113) & 0x1) == 0
    assert (hdr & 0xFF) == 0

    read_data = 0x0123_4567_89AB_CDEF
    resp_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (txnid << 114)
        | (1 << 113)
    )
    await send_bow_flit_until_accepted(dut, resp_hdr)

    resp_data_flit = (PKT_TYPE_RSP_DATA << 124) | (txnid << 116) | read_data
    await send_bow_flit_until_accepted(dut, resp_data_flit)

    dut.chi_rsp_ready.value = 1
    op, tid, dat = await recv_chi_response(dut)
    assert op == CHI_OP_READ_RESP
    assert tid == txnid
    assert dat == read_data


@cocotb.test()
async def test_burst_write_request_and_ack(dut):
    """CHI WRITE with beats>1 emits multiple BoW REQ_DATA flits, then completes on ACK."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    addr = 0x1111_2222_3333_4444
    data = 0xCAFE_BABE_DEAD_BEEF
    txnid = 0x41
    beats = 3

    await drive_req_until_accepted(dut, CHI_OP_WRITE, addr, data, txnid, beats=beats)

    hdr = await wait_for_tx_flit(dut)
    assert ((hdr >> 124) & 0xF) == PKT_TYPE_REQ_HDR
    assert ((hdr >> 122) & 0x3) == CHI_OP_WRITE
    assert ((hdr >> 114) & 0xFF) == txnid
    assert ((hdr >> 113) & 0x1) == 1
    assert ((hdr >> 49) & ((1 << 64) - 1)) == addr
    assert (hdr & 0xFF) == (beats - 1)

    for _ in range(beats):
        df = await wait_for_tx_flit(dut)
        assert ((df >> 124) & 0xF) == PKT_TYPE_REQ_DATA
        assert ((df >> 116) & 0xFF) == txnid
        assert (df & ((1 << 64) - 1)) == data

    resp_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_WRITE_ACK << 122)
        | (txnid << 114)
        | (0 << 113)
        | ((beats - 1) & 0xFF)
    )
    await send_bow_flit_until_accepted(dut, resp_hdr)

    dut.chi_rsp_ready.value = 1
    op, tid, dat = await recv_chi_response(dut)
    assert op == CHI_OP_WRITE_ACK
    assert tid == txnid
    assert dat == 0


@cocotb.test()
async def test_burst_read_request_and_data_response(dut):
    """CHI READ with beats>1 expects multiple BoW RSP_DATA flits before completing."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    addr = 0x5555_6666_7777_8888
    txnid = 0x42
    beats = 4

    await drive_req_until_accepted(dut, CHI_OP_READ, addr, 0, txnid, beats=beats)

    hdr = await wait_for_tx_flit(dut)
    assert ((hdr >> 124) & 0xF) == PKT_TYPE_REQ_HDR
    assert ((hdr >> 122) & 0x3) == CHI_OP_READ
    assert ((hdr >> 114) & 0xFF) == txnid
    assert ((hdr >> 113) & 0x1) == 0
    assert (hdr & 0xFF) == (beats - 1)

    datas = [0x1111_1111_1111_1111, 0x2222_2222_2222_2222, 0x3333_3333_3333_3333, 0x4444_4444_4444_4444]

    resp_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (txnid << 114)
        | (1 << 113)
        | ((beats - 1) & 0xFF)
    )
    await send_bow_flit_until_accepted(dut, resp_hdr)

    for d in datas:
        await send_bow_flit_until_accepted(dut, (PKT_TYPE_RSP_DATA << 124) | (txnid << 116) | d)

    dut.chi_rsp_ready.value = 1
    op, tid, dat = await recv_chi_response(dut, max_cycles=128)
    assert op == CHI_OP_READ_RESP
    assert tid == txnid
    assert dat == datas[-1]


@cocotb.test()
async def test_out_of_order_read_responses_by_txnid(dut):
    """Issue two reads and complete them out of order using txnid-based matching."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    # Request A (txnid 0x11)
    await drive_req_until_accepted(dut, CHI_OP_READ, 0x1000, 0, 0x11)
    await wait_until_txnid_pending(dut, 0x11)

    # Request B (txnid 0x22)
    await drive_req_until_accepted(dut, CHI_OP_READ, 0x2000, 0, 0x22)
    await wait_until_txnid_pending(dut, 0x22)

    # Return response for B first (out of order).
    b_data = 0xAAAA_BBBB_CCCC_DDDD
    b_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (0x22 << 114)
        | (1 << 113)
    )
    b_dat = (PKT_TYPE_RSP_DATA << 124) | (0x22 << 116) | b_data

    await send_bow_flit_until_accepted(dut, b_hdr)
    await send_bow_flit_until_accepted(dut, b_dat)

    dut.chi_rsp_ready.value = 1
    _, tid, dat = await recv_chi_response(dut)
    assert tid == 0x22
    assert dat == b_data

    # Then return response for A.
    a_data = 0x1111_2222_3333_4444
    a_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (0x11 << 114)
        | (1 << 113)
    )
    a_dat = (PKT_TYPE_RSP_DATA << 124) | (0x11 << 116) | a_data

    await send_bow_flit_until_accepted(dut, a_hdr)
    await send_bow_flit_until_accepted(dut, a_dat)

    dut.chi_rsp_ready.value = 1
    _, tid, dat = await recv_chi_response(dut)
    assert tid == 0x11
    assert dat == a_data


@cocotb.test()
async def test_randomized_backpressure_scoreboard(dut):
    """Stress ready/valid stalls and verify txnid-matched completions with a scoreboard."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    rng = random.Random(0xC0C07B)
    dut.chi_rsp_ready.value = 1
    dut.bow_tx_ready.value = 1
    dut.bow_rx_valid.value = 0
    dut.bow_rx_data.value = 0

    # Mix read and write requests with unique txnids.
    requests = [
        {"op": CHI_OP_READ, "txnid": 0x10, "addr": 0x1000, "data": 0},
        {"op": CHI_OP_WRITE, "txnid": 0x11, "addr": 0x1010, "data": 0x1111_2222_3333_4444},
        {"op": CHI_OP_READ, "txnid": 0x12, "addr": 0x1020, "data": 0},
        {"op": CHI_OP_WRITE, "txnid": 0x13, "addr": 0x1030, "data": 0xAAAA_BBBB_CCCC_DDDD},
    ]

    expected_rsp = {}
    for req in requests:
        await drive_req_until_accepted(
            dut, req["op"], req["addr"], req["data"], req["txnid"], max_cycles=64
        )
        if req["op"] == CHI_OP_READ:
            expected_rsp[req["txnid"]] = (CHI_OP_READ_RESP, 0x9000_0000_0000_0000 | req["txnid"])
        else:
            expected_rsp[req["txnid"]] = (CHI_OP_WRITE_ACK, 0)
        await RisingEdge(dut.clk)

    # Restore TX ready so pending request flits can drain.
    dut.bow_tx_ready.value = 1

    for req in requests:
        await wait_until_txnid_pending(dut, req["txnid"])

    # Respond in randomized order and with randomized gaps/backpressure.
    txnids = [req["txnid"] for req in requests]
    rng.shuffle(txnids)
    observed = {}

    for txnid in txnids:
        opcode, data = expected_rsp[txnid]
        has_data = 1 if opcode == CHI_OP_READ_RESP else 0

        # Random gap before each response.
        for _ in range(rng.randrange(0, 4)):
            dut.chi_rsp_ready.value = 1 if rng.randrange(100) < 75 else 0
            await RisingEdge(dut.clk)

        hdr = (PKT_TYPE_RSP_HDR << 124) | (opcode << 122) | (txnid << 114) | (has_data << 113)
        await send_bow_flit_until_accepted(dut, hdr, rng=rng)

        if has_data:
            # Random delay before data flit.
            for _ in range(rng.randrange(0, 3)):
                dut.chi_rsp_ready.value = 1 if rng.randrange(100) < 75 else 0
                await RisingEdge(dut.clk)
            dat = (PKT_TYPE_RSP_DATA << 124) | (txnid << 116) | data
            await send_bow_flit_until_accepted(dut, dat, rng=rng)

        # Collect completion for this injected response transaction.
        dut.chi_rsp_ready.value = 1
        op, tid, dat = await recv_chi_response(dut, max_cycles=128)
        observed[tid] = (op, dat)

    # Check all txn completions are present and correct.
    for tid, (exp_op, exp_dat) in expected_rsp.items():
        assert tid in observed, f"Missing completion for txnid 0x{tid:02x}"
        got_op, got_dat = observed[tid]
        assert got_op == exp_op, f"Bad opcode for txnid 0x{tid:02x}"
        assert got_dat == exp_dat, f"Bad data for txnid 0x{tid:02x}"


@cocotb.test()
async def test_interleaved_mixed_read_write_responses(dut):
    """Interleave mixed requests and randomized out-of-order responses."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    rng = random.Random(0xB01D5EED)
    dut.chi_rsp_ready.value = 1
    dut.bow_tx_ready.value = 1
    dut.bow_rx_valid.value = 0
    dut.bow_rx_data.value = 0

    # Build a mixed read/write request stream with unique txnids.
    requests = []
    for i in range(10):
        txnid = 0x20 + i
        is_read = (i % 3) != 0
        requests.append(
            {
                "op": CHI_OP_READ if is_read else CHI_OP_WRITE,
                "txnid": txnid,
                "addr": 0x4000 + (i * 0x10),
                "data": 0xA5A5_0000_0000_0000 | txnid,
            }
        )

    expected_rsp = {}
    for req in requests:
        await drive_req_until_accepted(
            dut, req["op"], req["addr"], req["data"], req["txnid"], max_cycles=128
        )
        if req["op"] == CHI_OP_READ:
            expected_rsp[req["txnid"]] = (
                CHI_OP_READ_RESP,
                0xD000_0000_0000_0000 | req["txnid"],
            )
        else:
            expected_rsp[req["txnid"]] = (CHI_OP_WRITE_ACK, 0)

        # Inject occasional CHI-side and BoW-side stalls while requests stream in.
        for _ in range(rng.randrange(0, 3)):
            dut.chi_rsp_ready.value = 1 if rng.randrange(100) < 85 else 0
            dut.bow_tx_ready.value = 1 if rng.randrange(100) < 80 else 0
            await RisingEdge(dut.clk)

    dut.chi_rsp_ready.value = 1
    dut.bow_tx_ready.value = 1

    # Ensure all issued requests are visible as outstanding before responses start.
    for req in requests:
        await wait_until_txnid_pending(dut, req["txnid"], max_cycles=512)

    txnids = [req["txnid"] for req in requests]
    rng.shuffle(txnids)
    observed = {}

    for txnid in txnids:
        opcode, data = expected_rsp[txnid]
        has_data = 1 if opcode == CHI_OP_READ_RESP else 0

        # Random idle/stall cycles before each response header.
        for _ in range(rng.randrange(0, 5)):
            dut.chi_rsp_ready.value = 1 if rng.randrange(100) < 75 else 0
            await RisingEdge(dut.clk)

        hdr = (PKT_TYPE_RSP_HDR << 124) | (opcode << 122) | (txnid << 114) | (has_data << 113)
        await send_bow_flit_until_accepted(dut, hdr, rng=rng)

        if has_data:
            for _ in range(rng.randrange(0, 4)):
                dut.chi_rsp_ready.value = 1 if rng.randrange(100) < 70 else 0
                await RisingEdge(dut.clk)
            dat = (PKT_TYPE_RSP_DATA << 124) | (txnid << 116) | data
            await send_bow_flit_until_accepted(dut, dat, rng=rng)

        dut.chi_rsp_ready.value = 1
        got_op, got_tid, got_dat = await recv_chi_response(dut, max_cycles=256)
        observed[got_tid] = (got_op, got_dat)

    for tid, (exp_op, exp_dat) in expected_rsp.items():
        assert tid in observed, f"Missing completion for txnid 0x{tid:02x}"
        got_op, got_dat = observed[tid]
        assert got_op == exp_op, f"Bad opcode for txnid 0x{tid:02x}"
        assert got_dat == exp_dat, f"Bad data for txnid 0x{tid:02x}"


@cocotb.test()
async def test_illegal_sequences_increment_error_counters(dut):
    """Directed negative tests for illegal CHI/BoW sequences."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    def rd32(sig):
        return int(getattr(dut, sig).value)

    # 1) Illegal CHI opcode on request channel.
    base_illegal_req = rd32("err_illegal_req_hdr")
    dut.chi_req_opcode.value = CHI_OP_READ_RESP
    dut.chi_req_addr.value = 0
    dut.chi_req_data.value = 0
    dut.chi_req_txnid.value = 0x01
    dut.chi_req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.chi_req_valid.value = 0
    await RisingEdge(dut.clk)
    assert rd32("err_illegal_req_hdr") == base_illegal_req + 1

    # 2) Unknown txnid response header.
    base_unknown_hdr = rd32("err_unknown_txn_rsp_hdr")
    bad_hdr = (PKT_TYPE_RSP_HDR << 124) | (CHI_OP_WRITE_ACK << 122) | (0xFE << 114) | (0 << 113)
    await send_bow_flit_until_accepted(dut, bad_hdr)
    # RX is a 2-stage pipeline (capture on pop, process on the following cycle).
    await wait_until_counter_eq(dut, "err_unknown_txn_rsp_hdr", base_unknown_hdr + 1, max_cycles=32)

    # 3) Duplicate read-response headers for same txnid.
    await drive_req_until_accepted(dut, CHI_OP_READ, 0x5000, 0, 0x55)
    await wait_until_txnid_pending(dut, 0x55)
    hdr = (PKT_TYPE_RSP_HDR << 124) | (CHI_OP_READ_RESP << 122) | (0x55 << 114) | (1 << 113)
    await send_bow_flit_until_accepted(dut, hdr)
    base_dup = rd32("err_dup_rsp_hdr")
    await send_bow_flit_until_accepted(dut, hdr)
    await wait_until_counter_eq(dut, "err_dup_rsp_hdr", base_dup + 1, max_cycles=32)

    # 4) Orphan response data flit.
    base_orphan = rd32("err_orphan_rsp_data")
    orphan = (PKT_TYPE_RSP_DATA << 124) | (0x33 << 116) | 0x1234
    await send_bow_flit_until_accepted(dut, orphan)
    await wait_until_counter_eq(dut, "err_orphan_rsp_data", base_orphan + 1, max_cycles=32)
