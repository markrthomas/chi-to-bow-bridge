"""
Shared golden literals for Cocotb and documentation.
Mirror manually in SV (chi_tb_pkg.sv exp_read_data, bow_link_partner_bfm.v) and C++ (chi_tb.hpp).
"""

# CHI request channel opcodes (2-bit).
CHI_OP_READ = 0b00
CHI_OP_WRITE = 0b01
CHI_OP_READ_RESP = 0b10
CHI_OP_WRITE_ACK = 0b11

# BoW flit packet types (upper nibble of 128-bit flit).
PKT_TYPE_REQ_HDR = 0x1
PKT_TYPE_REQ_DATA = 0x2
PKT_TYPE_RSP_HDR = 0x3
PKT_TYPE_RSP_DATA = 0x4


def bfm_read_data_u64(txnid: int) -> int:
    """Deterministic read data from bow_link_partner_bfm when DATA_WIDTH==64."""
    tid = txnid & 0xFF
    return (0xA5A5A5A5 << 32) | (tid << 16) | tid
