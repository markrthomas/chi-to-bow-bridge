// Virtual-interface hookup for UVM stimulus/monitoring against chi_to_bow_integration_top.
// Clock is an input port; reset and CHI REQ/RSP are driven or sampled by the TB.
`ifndef CHI_INTEGRATION_IF_SV
`define CHI_INTEGRATION_IF_SV

`timescale 1ns / 1ps

interface chi_integration_if (input logic clk);
  logic        rst_n;
  logic [31:0] err_illegal_req_hdr;
  logic [31:0] err_unknown_txn_rsp_hdr;
  logic [31:0] err_unknown_txn_rsp_data;
  logic [31:0] err_dup_rsp_hdr;
  logic [31:0] err_orphan_rsp_data;
  logic [31:0] err_illegal_rsp_hdr;
  logic        err_pulse;
  logic        chi_req_valid;
  logic        chi_req_ready;
  logic [1:0]  chi_req_opcode;
  logic [63:0] chi_req_addr;
  logic [63:0] chi_req_data;
  logic [7:0]  chi_req_beats;
  logic [7:0]  chi_req_txnid;
  logic        chi_rsp_valid;
  logic        chi_rsp_ready;
  logic [1:0]  chi_rsp_opcode;
  logic [63:0] chi_rsp_data;
  logic [7:0]  chi_rsp_txnid;

  // BoW RX inject mux (parity: integration/test_integration bow_inj_* tests).
  logic        bow_inj_en;
  logic        bow_inj_valid;
  logic        bow_inj_ready;
  logic [63:0] bow_inj_data_hi;
  logic [63:0] bow_inj_data_lo;

  modport drv_mp (
      input chi_req_ready, chi_rsp_valid, chi_rsp_opcode, chi_rsp_data, chi_rsp_txnid,
            bow_inj_ready,
      output chi_req_valid, chi_req_opcode, chi_req_addr, chi_req_data, chi_req_beats,
             chi_req_txnid, chi_rsp_ready,
             bow_inj_en, bow_inj_valid, bow_inj_data_hi, bow_inj_data_lo
  );

  modport mon_mp (
      input clk, rst_n, chi_req_valid, chi_req_ready, chi_req_opcode, chi_req_addr,
            chi_req_data, chi_req_beats, chi_req_txnid,
            chi_rsp_valid, chi_rsp_ready, chi_rsp_opcode, chi_rsp_data, chi_rsp_txnid,
            bow_inj_en, bow_inj_valid, bow_inj_ready, bow_inj_data_hi, bow_inj_data_lo,
            err_illegal_req_hdr, err_unknown_txn_rsp_hdr, err_unknown_txn_rsp_data,
            err_dup_rsp_hdr, err_orphan_rsp_data, err_illegal_rsp_hdr, err_pulse
  );

  modport mon_rsp_mp (
      input clk, rst_n, chi_rsp_valid, chi_rsp_ready, chi_rsp_opcode, chi_rsp_data, chi_rsp_txnid
  );
endinterface : chi_integration_if

`endif // CHI_INTEGRATION_IF_SV
