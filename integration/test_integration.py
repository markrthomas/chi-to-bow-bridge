"""
System integration smoke test: DUT = chi_to_bow_integration_top
(BFM completes single-beat read/write; error counters must stay zero).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge
from verification.golden_payloads import (
    CHI_OP_READ,
    CHI_OP_WRITE,
    CHI_OP_READ_RESP,
    CHI_OP_WRITE_ACK,
    PKT_TYPE_RSP_HDR,
    PKT_TYPE_RSP_DATA,
    bfm_read_data_u64 as bfm_read_data64,
)

READ_RESP = CHI_OP_READ_RESP
WRITE_ACK = CHI_OP_WRITE_ACK


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.chi_req_valid.value = 0
    dut.chi_req_opcode.value = 0
    dut.chi_req_addr.value = 0
    dut.chi_req_data.value = 0
    dut.chi_req_beats.value = 1
    dut.chi_req_txnid.value = 0
    dut.chi_rsp_ready.value = 0
    dut.bow_inj_en.value = 0
    dut.bow_inj_valid.value = 0
    dut.bow_inj_data_hi.value = 0
    dut.bow_inj_data_lo.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk)


def assert_no_errors(dut, msg=""):
    names = [
        "err_unknown_txn_rsp_hdr",
        "err_unknown_txn_rsp_data",
        "err_dup_rsp_hdr",
        "err_orphan_rsp_data",
        "err_illegal_req_hdr",
        "err_illegal_rsp_hdr",
    ]
    for n in names:
        v = int(getattr(dut, n).value)
        assert v == 0, f"{n}={v} {msg}"


def assert_fault_isolated_unknown_rsp_hdr_only(dut, exp_unknown_hdr, msg=""):
    """Counters should be quiet except ``err_unknown_txn_rsp_hdr == exp_unknown_hdr``."""
    expect = [
        ("err_unknown_txn_rsp_hdr", exp_unknown_hdr),
        ("err_unknown_txn_rsp_data", 0),
        ("err_dup_rsp_hdr", 0),
        ("err_orphan_rsp_data", 0),
        ("err_illegal_req_hdr", 0),
        ("err_illegal_rsp_hdr", 0),
    ]
    for n, v in expect:
        ov = int(getattr(dut, n).value)
        assert ov == v, f"{n}={ov} wanted {v} {msg}"


async def drive_req_accepted(
    dut, opcode, addr, data, txnid, beats=1, max_cycles=64
):
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


async def recv_chi(dut, max_cycles=64):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.chi_rsp_valid.value) == 1:
            return (
                int(dut.chi_rsp_opcode.value),
                int(dut.chi_rsp_txnid.value),
                int(dut.chi_rsp_data.value),
            )
    raise AssertionError("chi_rsp timeout")


async def wait_until_counter_eq(dut, name, expected, max_cycles=48):
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(getattr(dut, name).value) == expected:
            return
    raise AssertionError(
        f"Timed out waiting for {name} == {expected} (last "
        + str(int(getattr(dut, name).value))
        + ")"
    )


async def send_bow_inj_flit(dut, flit128: int, max_cycles=64):
    hi = (flit128 >> 64) & ((1 << 64) - 1)
    lo = flit128 & ((1 << 64) - 1)
    dut.bow_inj_en.value = 1
    dut.bow_inj_data_hi.value = hi
    dut.bow_inj_data_lo.value = lo
    dut.bow_inj_valid.value = 1
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.bow_inj_valid.value) == 1 and int(dut.bow_inj_ready.value) == 1:
            dut.bow_inj_valid.value = 0
            await RisingEdge(dut.clk)
            dut.bow_inj_en.value = 0
            return
    dut.bow_inj_valid.value = 0
    dut.bow_inj_en.value = 0
    raise AssertionError("Timed out waiting for BoW RX inject handshake")


async def send_bow_inj_flit_no_deassert(dut, flit128: int, max_cycles=64):
    hi = (flit128 >> 64) & ((1 << 64) - 1)
    lo = flit128 & ((1 << 64) - 1)
    dut.bow_inj_en.value = 1
    dut.bow_inj_data_hi.value = hi
    dut.bow_inj_data_lo.value = lo
    dut.bow_inj_valid.value = 1
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.bow_inj_valid.value) == 1 and int(dut.bow_inj_ready.value) == 1:
            dut.bow_inj_valid.value = 0
            return
    dut.bow_inj_valid.value = 0
    raise AssertionError("Timed out waiting for BoW RX inject handshake")


@cocotb.test()
async def test_integration_bfm_completes_smoke(dut):
    """Single-beat read and write through bridge + in-repo BoW BFM; err_* remain zero."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.chi_rsp_ready.value = 1
    assert_no_errors(dut, "after reset")

    r_txn = 0x2A
    w_txn = 0x2B
    w_data = 0xDEADBEEF_0000_0000 | 0x99

    await drive_req_accepted(
        dut, CHI_OP_READ, 0x1000, 0, r_txn, beats=1
    )
    op, tid, rdat = await recv_chi(dut, max_cycles=128)
    assert op == READ_RESP
    assert tid == r_txn
    assert rdat == bfm_read_data64(r_txn)
    assert_no_errors(dut, "after read")

    await drive_req_accepted(
        dut, CHI_OP_WRITE, 0x2000, w_data, w_txn, beats=1
    )
    op, tid, wdat = await recv_chi(dut, max_cycles=128)
    assert op == WRITE_ACK
    assert tid == w_txn
    assert wdat == 0
    assert_no_errors(dut, "after write")


@cocotb.test()
async def test_integration_bfm_burst_through_top(dut):
    """Multi-beat write and read through integration top + burst-capable BFM; err_* remain zero."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.chi_rsp_ready.value = 1
    assert_no_errors(dut, "after reset")

    w_txn = 0x71
    r_txn = 0x72
    w_beats = 3
    r_beats = 4
    w_addr = 0x3000_4000_5000_6000
    w_data = 0xBAD0_C0DE_1111_2222

    await drive_req_accepted(
        dut, CHI_OP_WRITE, w_addr, w_data, w_txn, beats=w_beats
    )
    op, tid, wdat = await recv_chi(dut, max_cycles=256)
    assert op == WRITE_ACK
    assert tid == w_txn
    assert wdat == 0
    assert_no_errors(dut, "after burst write")

    await drive_req_accepted(
        dut, CHI_OP_READ, 0x5000, 0, r_txn, beats=r_beats
    )
    op, tid, rdat = await recv_chi(dut, max_cycles=256)
    assert op == READ_RESP
    assert tid == r_txn
    assert rdat == bfm_read_data64(r_txn)
    assert_no_errors(dut, "after burst read")


@cocotb.test()
async def test_integration_illegal_chi_req_opcodes_increment_err_counter(dut):
    """RESP opcodes on the CHI request channel increment err_illegal_req_hdr through integration_top."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.chi_rsp_ready.value = 1

    def rd32(sig):
        return int(getattr(dut, sig).value)

    base = rd32("err_illegal_req_hdr")

    dut.chi_req_opcode.value = CHI_OP_READ_RESP
    dut.chi_req_addr.value = 0
    dut.chi_req_data.value = 0
    dut.chi_req_beats.value = 1
    dut.chi_req_txnid.value = 0x01
    dut.chi_req_valid.value = 1
    await RisingEdge(dut.clk)
    # Sample after the posedge has committed err_pulse (holds through the high phase).
    await FallingEdge(dut.clk)
    assert (
        int(dut.err_pulse.value) == 1
    ), "err_pulse expected with illegal REQ opcode (READ_RESP on REQ channel)"
    dut.chi_req_valid.value = 0
    await RisingEdge(dut.clk)
    assert rd32("err_illegal_req_hdr") == base + 1

    base = rd32("err_illegal_req_hdr")
    dut.chi_req_opcode.value = CHI_OP_WRITE_ACK
    dut.chi_req_txnid.value = 0x02
    dut.chi_req_valid.value = 1
    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    assert (
        int(dut.err_pulse.value) == 1
    ), "err_pulse expected with illegal REQ opcode (WRITE_ACK on REQ channel)"
    dut.chi_req_valid.value = 0
    await RisingEdge(dut.clk)
    assert rd32("err_illegal_req_hdr") == base + 1


@cocotb.test()
async def test_integration_unknown_txnid_bow_rsp_hdr_via_inj(dut):
    """Unknown-txnid BoW RSP_HDR on ``bow_inj_*`` increments ``err_unknown_txn_rsp_hdr``.

    Mirrors the block Cocotb case in ``test_chi_to_bow_bridge``
    ``test_illegal_sequences_increment_error_counters`` (unknown txn rsp hdr).
    """
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.chi_rsp_ready.value = 1

    def rd32(sig):
        return int(getattr(dut, sig).value)

    base_unknown_hdr = rd32("err_unknown_txn_rsp_hdr")

    bad_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_WRITE_ACK << 122)
        | (0xFE << 114)
        | (0 << 113)
    )
    await send_bow_inj_flit(dut, bad_hdr)
    await wait_until_counter_eq(dut, "err_unknown_txn_rsp_hdr", base_unknown_hdr + 1)
    assert_fault_isolated_unknown_rsp_hdr_only(dut, base_unknown_hdr + 1)


def assert_fault_isolated_dup_rsp_hdr_only(dut, exp_dup, msg=""):
    expect = [
        ("err_unknown_txn_rsp_hdr", 0),
        ("err_unknown_txn_rsp_data", 0),
        ("err_dup_rsp_hdr", exp_dup),
        ("err_orphan_rsp_data", 0),
        ("err_illegal_req_hdr", 0),
        ("err_illegal_rsp_hdr", 0),
    ]
    for n, v in expect:
        ov = int(getattr(dut, n).value)
        assert ov == v, f"{n}={ov} wanted {v} {msg}"


@cocotb.test()
async def test_integration_duplicate_rsp_hdr_via_inj(dut):
    """Duplicate read-response headers for the same txnid increment err_dup_rsp_hdr."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.chi_rsp_ready.value = 1

    def rd32(sig):
        return int(getattr(dut, sig).value)

    base_dup = rd32("err_dup_rsp_hdr")
    txnid = 0x55

    # 1) Issue CHI read request for txnid 0x55 with injection active to stall BFM
    dut.bow_inj_en.value = 1
    await drive_req_accepted(dut, CHI_OP_READ, 0x5000, 0, txnid, beats=1)

    # Wait until pending
    for _ in range(64):
        await RisingEdge(dut.clk)
        if rd32("dbg_pending_txn") & (1 << txnid):
            break
    else:
        raise AssertionError("txn never became pending")

    hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (txnid << 114)
        | (1 << 113)
    )

    # First injection
    await send_bow_inj_flit_no_deassert(dut, hdr)
    # Second (duplicate) injection
    await send_bow_inj_flit_no_deassert(dut, hdr)

    # Settle down and turn off injection
    await RisingEdge(dut.clk)
    dut.bow_inj_en.value = 0

    await wait_until_counter_eq(dut, "err_dup_rsp_hdr", base_dup + 1)
    assert_fault_isolated_dup_rsp_hdr_only(dut, base_dup + 1)


@cocotb.test()
async def test_integration_orphan_rsp_data_via_inj(dut):
    """Orphan response data flits on bow_inj_* increment err_orphan_rsp_data."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    dut.chi_rsp_ready.value = 1

    def rd32(sig):
        return int(getattr(dut, sig).value)

    base_orphan = rd32("err_orphan_rsp_data")
    txnid = 0x33

    orphan_flit = (PKT_TYPE_RSP_DATA << 124) | (txnid << 116) | 0x1234
    await send_bow_inj_flit(dut, orphan_flit)

    await wait_until_counter_eq(dut, "err_orphan_rsp_data", base_orphan + 1)
    
    expect = [
        ("err_unknown_txn_rsp_hdr", 0),
        ("err_unknown_txn_rsp_data", 0),
        ("err_dup_rsp_hdr", 0),
        ("err_orphan_rsp_data", base_orphan + 1),
        ("err_illegal_req_hdr", 0),
        ("err_illegal_rsp_hdr", 0),
    ]
    for n, v in expect:
        ov = int(getattr(dut, n).value)
        assert ov == v, f"{n}={ov} wanted {v}"


@cocotb.test()
async def test_integration_illegal_rsp_hdr_via_inj(dut):
    """Malformed BoW RSP_HDR flits are dropped, counted, but don't complete transactions."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    def rd32(sig):
        return int(getattr(dut, sig).value)

    def bit_is_set(sig, idx):
        return (int(sig.value) & (1 << idx)) != 0

    base_illegal = rd32("err_illegal_rsp_hdr")
    dut.chi_rsp_ready.value = 0

    # WRITE_ACK with has_data=1
    w_txn = 0x61
    dut.bow_inj_en.value = 1
    await drive_req_accepted(dut, CHI_OP_WRITE, 0x6100, 0xFEEDFACE, w_txn, beats=1)

    for _ in range(64):
        await RisingEdge(dut.clk)
        if rd32("dbg_pending_txn") & (1 << w_txn):
            break
    else:
        raise AssertionError("txn never became pending")

    illegal_wack = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_WRITE_ACK << 122)
        | (w_txn << 114)
        | (1 << 113)
    )
    await send_bow_inj_flit_no_deassert(dut, illegal_wack)
    await wait_until_counter_eq(dut, "err_illegal_rsp_hdr", base_illegal + 1)
    
    assert bit_is_set(dut.dbg_pending_txn, w_txn)
    assert not bit_is_set(dut.dbg_rsp_need_data, w_txn)
    assert int(dut.chi_rsp_valid.value) == 0

    # Complete with valid WRITE_ACK (has_data=0)
    dut.chi_rsp_ready.value = 1
    valid_wack = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_WRITE_ACK << 122)
        | (w_txn << 114)
        | (0 << 113)
    )
    await send_bow_inj_flit_no_deassert(dut, valid_wack)
    
    await RisingEdge(dut.clk)
    dut.bow_inj_en.value = 0
    
    op, tid, dat = await recv_chi(dut)
    assert (op, tid, dat) == (WRITE_ACK, w_txn, 0)

    # READ_RESP with has_data=0
    dut.chi_rsp_ready.value = 0
    r_txn = 0x62
    dut.bow_inj_en.value = 1
    await drive_req_accepted(dut, CHI_OP_READ, 0x6200, 0, r_txn, beats=1)

    for _ in range(64):
        await RisingEdge(dut.clk)
        if rd32("dbg_pending_txn") & (1 << r_txn):
            break
    else:
        raise AssertionError("txn never became pending")

    illegal_read_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (r_txn << 114)
        | (0 << 113)
    )
    await send_bow_inj_flit_no_deassert(dut, illegal_read_hdr)
    await wait_until_counter_eq(dut, "err_illegal_rsp_hdr", base_illegal + 2)
    assert bit_is_set(dut.dbg_pending_txn, r_txn)
    assert not bit_is_set(dut.dbg_rsp_need_data, r_txn)
    assert int(dut.chi_rsp_valid.value) == 0

    # Complete via BFM by disabling bow_inj_en and setting chi_rsp_ready = 1
    dut.chi_rsp_ready.value = 1
    await RisingEdge(dut.clk)
    dut.bow_inj_en.value = 0

    op, tid, dat = await recv_chi(dut)
    assert (op, tid, dat) == (READ_RESP, r_txn, bfm_read_data64(r_txn))
