// Shared protocol checks for chi_to_bow_integration_top CHI REQ/RSP + bow_inj valid/ready paths.
// Bound into every chi_to_bow_integration_top instance (uvm_bench via sim.f, vlate_bench via sim.f).
//
// Semantics match vlate_bench/chi_proto.hpp HoldChecker (explicit waiting registers + asserts).

`ifndef CHI_INTEGRATION_PROTOCOL_CHK_SV
`define CHI_INTEGRATION_PROTOCOL_CHK_SV

`timescale 1ns / 1ps

module chi_integration_protocol_chk (
    input wire clk,
    input wire rst_n,
    input wire chi_req_valid,
    input wire chi_req_ready,
    input wire chi_rsp_valid,
    input wire chi_rsp_ready,
    input wire bow_inj_en,
    input wire bow_inj_valid,
    input wire bow_inj_ready
);

  // --- CHI REQ (TB→DUT): valid must stay high until chi_req_ready ----------------------------
  logic req_waiting_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      req_waiting_q <= 1'b0;
    else begin
      if (chi_req_valid && chi_req_ready)
        req_waiting_q <= 1'b0;
      else if (chi_req_valid && !chi_req_ready)
        req_waiting_q <= 1'b1;
      else if (!chi_req_valid && req_waiting_q)
        req_waiting_q <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n && req_waiting_q && !chi_req_valid)
      assert (0)
      else $error("PROTO_SVA: CHI REQ valid dropped before chi_req_ready");
  end

  // --- CHI RSP (DUT→TB): valid must stay high until chi_rsp_ready ---------------------------
  logic rsp_waiting_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rsp_waiting_q <= 1'b0;
    else begin
      if (chi_rsp_valid && chi_rsp_ready)
        rsp_waiting_q <= 1'b0;
      else if (chi_rsp_valid && !chi_rsp_ready)
        rsp_waiting_q <= 1'b1;
      else if (!chi_rsp_valid && rsp_waiting_q)
        rsp_waiting_q <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n && rsp_waiting_q && !chi_rsp_valid)
      assert (0)
      else $error("PROTO_SVA: CHI RSP valid dropped before chi_rsp_ready");
  end

  // --- bow_inj: same as HoldChecker::posedge_sample_inj (clear when !bow_inj_en, no check)
  logic inj_waiting_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      inj_waiting_q <= 1'b0;
    else if (!bow_inj_en)
      inj_waiting_q <= 1'b0;
    else begin
      if (bow_inj_valid && bow_inj_ready)
        inj_waiting_q <= 1'b0;
      else if (bow_inj_valid && !bow_inj_ready)
        inj_waiting_q <= 1'b1;
      else if (!bow_inj_valid && inj_waiting_q)
        inj_waiting_q <= 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n && bow_inj_en && inj_waiting_q && !bow_inj_valid)
      assert (0)
      else $error("PROTO_SVA: bow_inj valid dropped before bow_inj_ready (while bow_inj_en)");
  end

endmodule : chi_integration_protocol_chk

bind chi_to_bow_integration_top chi_integration_protocol_chk u_chi_integration_protocol_chk (
    .clk(clk),
    .rst_n(rst_n),
    .chi_req_valid(chi_req_valid),
    .chi_req_ready(chi_req_ready),
    .chi_rsp_valid(chi_rsp_valid),
    .chi_rsp_ready(chi_rsp_ready),
    .bow_inj_en(bow_inj_en),
    .bow_inj_valid(bow_inj_valid),
    .bow_inj_ready(bow_inj_ready)
);

`endif  // CHI_INTEGRATION_PROTOCOL_CHK_SV
