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
