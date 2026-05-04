// Testbenchtop: clocks, resets, binds chi_integration_if to chi_to_bow_integration_top.
//
// Simulate with Synopsys VCS (+UVM) from uvm_bench:
//   make run   OR  vcs -f sim.f -o simv && ./simv +UVM_TESTNAME=chi_smoke_test

`timescale 1ns / 1ps

module tb_top;
  import uvm_pkg::*;
  import chi_tb_pkg::*;

  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  chi_integration_if chi_if (.clk(clk));

  assign chi_if.rst_n = rst_n;

  initial begin
    rst_n = 1'b0;
    @(posedge clk);
    repeat (12) @(posedge clk);
    rst_n = 1'b1;
  end

  wire [31:0] err_unknown_txn_rsp_hdr;
  wire [31:0] err_unknown_txn_rsp_data;
  wire [31:0] err_dup_rsp_hdr;
  wire [31:0] err_orphan_rsp_data;
  wire [31:0] err_illegal_req_hdr;
  wire [31:0] err_illegal_rsp_hdr;
  wire        err_pulse;
  wire [7:0]  dbg_chi_req_fifo_used;
  wire [7:0]  dbg_bow_rx_fifo_used;
  wire [255:0] dbg_pending_txn;
  wire [255:0] dbg_rsp_need_data;

  logic bow_inj_en;
  logic bow_inj_valid;
  logic bow_inj_ready;
  logic [63:0] bow_inj_data_hi;
  logic [63:0] bow_inj_data_lo;

  assign chi_if.err_illegal_req_hdr      = err_illegal_req_hdr;
  assign chi_if.err_pulse                = err_pulse;
  assign chi_if.err_unknown_txn_rsp_hdr  = err_unknown_txn_rsp_hdr;
  assign chi_if.err_unknown_txn_rsp_data = err_unknown_txn_rsp_data;
  assign chi_if.err_dup_rsp_hdr          = err_dup_rsp_hdr;
  assign chi_if.err_orphan_rsp_data      = err_orphan_rsp_data;
  assign chi_if.err_illegal_rsp_hdr      = err_illegal_rsp_hdr;

  assign bow_inj_en       = chi_if.bow_inj_en;
  assign bow_inj_valid    = chi_if.bow_inj_valid;
  assign chi_if.bow_inj_ready   = bow_inj_ready;
  assign bow_inj_data_hi  = chi_if.bow_inj_data_hi;
  assign bow_inj_data_lo  = chi_if.bow_inj_data_lo;

  chi_to_bow_integration_top #(
      .ADDR_WIDTH (64),
      .DATA_WIDTH (64),
      .FIFO_DEPTH (4)
  ) dut (
      .clk (clk),
      .rst_n (rst_n),
      .chi_req_valid (chi_if.chi_req_valid),
      .chi_req_ready (chi_if.chi_req_ready),
      .chi_req_opcode (chi_if.chi_req_opcode),
      .chi_req_addr (chi_if.chi_req_addr),
      .chi_req_data (chi_if.chi_req_data),
      .chi_req_beats (chi_if.chi_req_beats),
      .chi_req_txnid (chi_if.chi_req_txnid),
      .chi_rsp_valid (chi_if.chi_rsp_valid),
      .chi_rsp_ready (chi_if.chi_rsp_ready),
      .chi_rsp_opcode (chi_if.chi_rsp_opcode),
      .chi_rsp_data (chi_if.chi_rsp_data),
      .chi_rsp_txnid (chi_if.chi_rsp_txnid),
      .err_unknown_txn_rsp_hdr (err_unknown_txn_rsp_hdr),
      .err_unknown_txn_rsp_data (err_unknown_txn_rsp_data),
      .err_dup_rsp_hdr (err_dup_rsp_hdr),
      .err_orphan_rsp_data (err_orphan_rsp_data),
      .err_illegal_req_hdr (err_illegal_req_hdr),
      .err_illegal_rsp_hdr (err_illegal_rsp_hdr),
      .err_pulse (err_pulse),
      .dbg_chi_req_fifo_used (dbg_chi_req_fifo_used),
      .dbg_bow_rx_fifo_used (dbg_bow_rx_fifo_used),
      .dbg_pending_txn (dbg_pending_txn),
      .dbg_rsp_need_data (dbg_rsp_need_data),
      .bow_inj_en (bow_inj_en),
      .bow_inj_valid (bow_inj_valid),
      .bow_inj_ready (bow_inj_ready),
      .bow_inj_data_hi (bow_inj_data_hi),
      .bow_inj_data_lo (bow_inj_data_lo)
  );

  initial begin
    uvm_config_db#(virtual chi_integration_if)::set(null, chi_tb_pkg::CHI_DB_SCOPE_ALL,
                                                    chi_tb_pkg::CHI_DB_KEY_VIF, chi_if);
    run_test();
  end
endmodule : tb_top
