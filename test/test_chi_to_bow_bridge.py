import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


CHI_OP_READ = 0b00
CHI_OP_WRITE = 0b01
CHI_OP_READ_RESP = 0b10
CHI_OP_WRITE_ACK = 0b11

PKT_TYPE_REQ = 0x1
PKT_TYPE_RESP = 0x2


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
    """Drive CHI WRITE, observe BoW packet, inject BoW ACK, observe CHI response."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    addr = 0x1234_5678_9ABC_DEF0
    data = 0xDEAD_BEEF_CAFE_BABE
    txnid = 0x3C

    # Drive one CHI write request.
    dut.chi_req_opcode.value = CHI_OP_WRITE
    dut.chi_req_addr.value = addr
    dut.chi_req_data.value = data
    dut.chi_req_txnid.value = txnid
    dut.chi_req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.chi_req_valid.value = 0

    # Packet appears on BoW TX.
    await RisingEdge(dut.clk)
    assert dut.bow_tx_valid.value == 1, "Expected bow_tx_valid asserted"
    pkt = int(dut.bow_tx_data.value)

    pkt_type = (pkt >> 124) & 0xF
    pkt_opcode = (pkt >> 122) & 0x3
    pkt_txnid = (pkt >> 114) & 0xFF
    pkt_addr = (pkt >> 50) & ((1 << 64) - 1)
    pkt_data_lsb50 = pkt & ((1 << 50) - 1)

    assert pkt_type == PKT_TYPE_REQ
    assert pkt_opcode == CHI_OP_WRITE
    assert pkt_txnid == txnid
    assert pkt_addr == addr
    assert pkt_data_lsb50 == (data & ((1 << 50) - 1))

    # Inject a BoW write-ack response.
    resp_data = 0x15555
    resp_pkt = (
        (PKT_TYPE_RESP << 124)
        | (CHI_OP_WRITE_ACK << 122)
        | (txnid << 114)
        | (resp_data & ((1 << 50) - 1))
    )
    dut.bow_rx_data.value = resp_pkt
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    await RisingEdge(dut.clk)
    assert dut.chi_rsp_valid.value == 1
    assert int(dut.chi_rsp_opcode.value) == CHI_OP_WRITE_ACK
    assert int(dut.chi_rsp_txnid.value) == txnid
    assert int(dut.chi_rsp_data.value) == resp_data


@cocotb.test()
async def test_read_request_and_data_response(dut):
    """Drive CHI READ, then inject BoW read response and check CHI read response."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)

    dut.bow_tx_ready.value = 1
    dut.chi_rsp_ready.value = 1

    addr = 0x0BAD_F00D_1234_0008
    txnid = 0x77

    dut.chi_req_opcode.value = CHI_OP_READ
    dut.chi_req_addr.value = addr
    dut.chi_req_data.value = 0
    dut.chi_req_txnid.value = txnid
    dut.chi_req_valid.value = 1
    await RisingEdge(dut.clk)
    dut.chi_req_valid.value = 0

    await RisingEdge(dut.clk)
    assert dut.bow_tx_valid.value == 1
    pkt = int(dut.bow_tx_data.value)
    assert ((pkt >> 124) & 0xF) == PKT_TYPE_REQ
    assert ((pkt >> 122) & 0x3) == CHI_OP_READ
    assert ((pkt >> 114) & 0xFF) == txnid

    read_data = 0x2A5A5
    resp_pkt = (
        (PKT_TYPE_RESP << 124)
        | (CHI_OP_READ_RESP << 122)
        | (txnid << 114)
        | (read_data & ((1 << 50) - 1))
    )
    dut.bow_rx_data.value = resp_pkt
    dut.bow_rx_valid.value = 1
    await RisingEdge(dut.clk)
    dut.bow_rx_valid.value = 0

    await RisingEdge(dut.clk)
    assert dut.chi_rsp_valid.value == 1
    assert int(dut.chi_rsp_opcode.value) == CHI_OP_READ_RESP
    assert int(dut.chi_rsp_txnid.value) == txnid
    assert int(dut.chi_rsp_data.value) == read_data
