// Integration top: CHI to BoW bridge + in-repo BoW link partner (reference BFM).
// Same CHI, clock, and observability ports as standalone bridge, plus optional bow_inj_* BoW RX mux hooks
// for TB fault injection (bow_inj_en=0 selects partner BFM responses only).

`timescale 1ns / 1ps

module chi_to_bow_integration_top #(
    parameter ADDR_WIDTH  = 64,
    parameter DATA_WIDTH  = 64,
    parameter FIFO_DEPTH  = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Simplified CHI request
    input  wire                    chi_req_valid,
    output wire                    chi_req_ready,
    input  wire [1:0]              chi_req_opcode,
    input  wire [ADDR_WIDTH-1:0]  chi_req_addr,
    input  wire [DATA_WIDTH-1:0]  chi_req_data,
    input  wire [7:0]              chi_req_beats,
    input  wire [7:0]              chi_req_txnid,
    // Simplified CHI response
    output wire                    chi_rsp_valid,
    input  wire                    chi_rsp_ready,
    output wire [1:0]              chi_rsp_opcode,
    output wire [DATA_WIDTH-1:0]  chi_rsp_data,
    output wire [7:0]              chi_rsp_txnid,
    // Observability / guardrails
    output wire [31:0]            err_unknown_txn_rsp_hdr,
    output wire [31:0]            err_unknown_txn_rsp_data,
    output wire [31:0]            err_dup_rsp_hdr,
    output wire [31:0]            err_orphan_rsp_data,
    output wire [31:0]            err_illegal_req_hdr,
    output wire [31:0]            err_illegal_rsp_hdr,
    output wire                    err_pulse,
    output wire [7:0]              dbg_chi_req_fifo_used,
    output wire [7:0]              dbg_bow_rx_fifo_used,
    output wire [255:0]            dbg_pending_txn,
    output wire [255:0]            dbg_rsp_need_data,
    // TB injection on the bridge BoW RX path (stalls partner BFM s_rx_* when asserted).
    // When bow_inj_en=0, companion bow_inj_* pins are ignored; tie bow_inj_valid=0 in normal sims.
    input  wire                   bow_inj_en,
    input  wire                   bow_inj_valid,
    output wire                   bow_inj_ready,
    input  wire [63:0]            bow_inj_data_hi,
    input  wire [63:0]            bow_inj_data_lo
);
    wire        bow_tx_valid;
    wire        bow_tx_ready;
    wire [127:0] bow_tx_data;

    wire        bfm_rx_valid;
    wire        bfm_rx_ready;
    wire [127:0] bfm_rx_data;

    wire [127:0] bow_inj_packed = {bow_inj_data_hi, bow_inj_data_lo};

    wire        rx_mux_valid;
    wire        rx_mux_ready;
    wire [127:0] rx_mux_data;

    assign rx_mux_valid = bow_inj_en ? bow_inj_valid : bfm_rx_valid;
    assign rx_mux_data  = bow_inj_en ? bow_inj_packed : bfm_rx_data;
    assign bfm_rx_ready = bow_inj_en ? 1'b0 : rx_mux_ready;
    assign bow_inj_ready = bow_inj_en ? rx_mux_ready : 1'b0;

    chi_to_bow_bridge #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_bridge (
        .clk     (clk),
        .rst_n   (rst_n),
        .chi_req_valid  (chi_req_valid),
        .chi_req_ready  (chi_req_ready),
        .chi_req_opcode (chi_req_opcode),
        .chi_req_addr   (chi_req_addr),
        .chi_req_data   (chi_req_data),
        .chi_req_beats  (chi_req_beats),
        .chi_req_txnid  (chi_req_txnid),
        .chi_rsp_valid  (chi_rsp_valid),
        .chi_rsp_ready  (chi_rsp_ready),
        .chi_rsp_opcode (chi_rsp_opcode),
        .chi_rsp_data   (chi_rsp_data),
        .chi_rsp_txnid  (chi_rsp_txnid),
        .bow_tx_valid  (bow_tx_valid),
        .bow_tx_ready  (bow_tx_ready),
        .bow_tx_data   (bow_tx_data),
        .bow_rx_valid  (rx_mux_valid),
        .bow_rx_ready  (rx_mux_ready),
        .bow_rx_data   (rx_mux_data),
        .err_unknown_txn_rsp_hdr  (err_unknown_txn_rsp_hdr),
        .err_unknown_txn_rsp_data (err_unknown_txn_rsp_data),
        .err_dup_rsp_hdr     (err_dup_rsp_hdr),
        .err_orphan_rsp_data  (err_orphan_rsp_data),
        .err_illegal_req_hdr  (err_illegal_req_hdr),
        .err_illegal_rsp_hdr  (err_illegal_rsp_hdr),
        .err_pulse            (err_pulse),
        .dbg_chi_req_fifo_used (dbg_chi_req_fifo_used),
        .dbg_bow_rx_fifo_used  (dbg_bow_rx_fifo_used),
        .dbg_pending_txn   (dbg_pending_txn),
        .dbg_rsp_need_data  (dbg_rsp_need_data)
    );

    bow_link_partner_bfm u_link (
        .clk         (clk),
        .rst_n       (rst_n),
        .m_tx_valid  (bow_tx_valid),
        .m_tx_ready  (bow_tx_ready),
        .m_tx_data   (bow_tx_data),
        .s_rx_valid  (bfm_rx_valid),
        .s_rx_ready  (bfm_rx_ready),
        .s_rx_data   (bfm_rx_data)
    );
endmodule
