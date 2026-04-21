import cocotb
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


async def drive_req_until_accepted(dut, opcode, addr, data, txnid, max_cycles=16):
    dut.chi_req_opcode.value = opcode
    dut.chi_req_addr.value = addr
    dut.chi_req_data.value = data
    dut.chi_req_txnid.value = txnid
    dut.chi_req_valid.value = 1
    for _ in range(max_cycles):
        await RisingEdge(dut.clk)
        if int(dut.chi_req_ready.value) == 1:
            dut.chi_req_valid.value = 0
            return
    dut.chi_req_valid.value = 0
    raise AssertionError("Timed out waiting for chi_req_ready")


async def reset_dut(dut):
    dut.rst_n.value = 0
    dut.chi_req_valid.value = 0
    dut.chi_req_opcode.value = 0
    dut.chi_req_addr.value = 0
    dut.chi_req_data.value = 0
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
    dut.bow_rx_data.value = resp_hdr
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    await RisingEdge(dut.clk)
    assert dut.chi_rsp_valid.value == 1
    assert int(dut.chi_rsp_opcode.value) == CHI_OP_WRITE_ACK
    assert int(dut.chi_rsp_txnid.value) == txnid
    assert int(dut.chi_rsp_data.value) == 0


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

    read_data = 0x0123_4567_89AB_CDEF
    resp_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (txnid << 114)
        | (1 << 113)
    )
    dut.bow_rx_data.value = resp_hdr
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    resp_data_flit = (PKT_TYPE_RSP_DATA << 124) | (txnid << 116) | read_data
    dut.bow_rx_data.value = resp_data_flit
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    await RisingEdge(dut.clk)
    assert dut.chi_rsp_valid.value == 1
    assert int(dut.chi_rsp_opcode.value) == CHI_OP_READ_RESP
    assert int(dut.chi_rsp_txnid.value) == txnid
    assert int(dut.chi_rsp_data.value) == read_data


@cocotb.test()
async def test_out_of_order_read_responses_by_txnid(dut):
    """Issue two reads and complete them out of order using txnid-based matching."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    # Request A (txnid 0x11)
    await drive_req_until_accepted(dut, CHI_OP_READ, 0x1000, 0, 0x11)

    # Request B (txnid 0x22)
    await drive_req_until_accepted(dut, CHI_OP_READ, 0x2000, 0, 0x22)

    # Let TX side emit headers; this test focuses on RX matching by txnid.
    for _ in range(4):
        await RisingEdge(dut.clk)

    # Return response for B first (out of order).
    b_data = 0xAAAA_BBBB_CCCC_DDDD
    b_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (0x22 << 114)
        | (1 << 113)
    )
    b_dat = (PKT_TYPE_RSP_DATA << 124) | (0x22 << 116) | b_data

    dut.bow_rx_data.value = b_hdr
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_data.value = b_dat
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    await RisingEdge(dut.clk)
    assert int(dut.chi_rsp_valid.value) == 1
    assert int(dut.chi_rsp_txnid.value) == 0x22
    assert int(dut.chi_rsp_data.value) == b_data

    # Then return response for A.
    a_data = 0x1111_2222_3333_4444
    a_hdr = (
        (PKT_TYPE_RSP_HDR << 124)
        | (CHI_OP_READ_RESP << 122)
        | (0x11 << 114)
        | (1 << 113)
    )
    a_dat = (PKT_TYPE_RSP_DATA << 124) | (0x11 << 116) | a_data

    dut.bow_rx_data.value = a_hdr
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_data.value = a_dat
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    await RisingEdge(dut.clk)
    assert int(dut.chi_rsp_valid.value) == 1
    assert int(dut.chi_rsp_txnid.value) == 0x11
    assert int(dut.chi_rsp_data.value) == a_data
