// Reference BoW link partner for integration bring-up: completes CHI read/write traffic
// driven into the bridge (REQ_HDR/REQ_DATA on the TX path; responses on RX).
//
// Supports single-beat and multi-beat writes and reads consistent with REQ_HDR `[7:0]`
// (beats_minus_one encoding: number of REQ_DATA beats after HDR minus one for writes,
// and number of RSP_DATA beats after HDR minus one on read responses).
//
// Side facing the bridge: m_tx* observes bridge bow_tx*; s_rx* drives bow_rx*.

`timescale 1ns / 1ps

module bow_link_partner_bfm (
    input  wire        clk,
    input  wire        rst_n,
    // Bridge bow_tx (master-toward-link from bridge perspective)
    input  wire        m_tx_valid,
    output wire        m_tx_ready,
    input  wire [127:0] m_tx_data,
    // Bridge bow_rx (link toward bridge)
    output reg         s_rx_valid,
    input  wire        s_rx_ready,
    output reg  [127:0] s_rx_data
);
    localparam PKT_TYPE_REQ_HDR  = 4'h1;
    localparam PKT_TYPE_REQ_DATA  = 4'h2;
    localparam PKT_TYPE_RSP_HDR  = 4'h3;
    localparam PKT_TYPE_RSP_DATA  = 4'h4;
    localparam CHI_OP_READ       = 2'b00;
    localparam CHI_OP_WRITE       = 2'b01;
    localparam CHI_OP_READ_RESP  = 2'b10;
    localparam CHI_OP_WRITE_ACK  = 2'b11;

    localparam S_IDLE         = 3'd0;
    localparam S_WR_DATA      = 3'd1;
    localparam S_WACK         = 3'd2;
    localparam S_RD_HDR       = 3'd3;
    localparam S_RD_DATA      = 3'd4;

    reg [2:0] st = S_IDLE;

    reg [7:0] latched_txn = 8'd0;
    reg [7:0] hdr_beats_m1 = 8'd0;  // beats-1 from REQ_HDR (writes) or echoed on RSP_HDR (reads)

    // REQ_DATA beats remaining including the next REQ_DATA handshake (beats_m1+1 initial).
    reg [8:0] wr_req_left = 9'd0;
    // RSP_DATA beats remaining to transmit after HDR (beats_m1+1 total payloads).
    reg [8:0] rd_rsp_left = 9'd0;

    // Deterministic read payload per txnid — must match Cocotb / UVM / Verilator benches.
    wire [63:0] read_payload = {32'hA5A5_A5A5, 8'd0, latched_txn, 8'd0, latched_txn};

    assign m_tx_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st         <= S_IDLE;
            s_rx_valid <= 1'b0;
            s_rx_data  <= 128'd0;
            latched_txn <= 8'd0;
            hdr_beats_m1 <= 8'd0;
            wr_req_left <= 9'd0;
            rd_rsp_left <= 9'd0;
        end else begin
            case (st)
                S_IDLE: begin
                    if (m_tx_valid && m_tx_data[127:124] == PKT_TYPE_REQ_HDR) begin
                        latched_txn   <= m_tx_data[121:114];
                        hdr_beats_m1  <= m_tx_data[7:0];
                        if (m_tx_data[123:122] == CHI_OP_READ) begin
                            st <= S_RD_HDR;
                        end else if (m_tx_data[123:122] == CHI_OP_WRITE) begin
                            // Number of REQ_DATA flits expected (including first) =
                            // (beats_minus_one_field + 1); must not be zero (bridge drops illegal).
                            wr_req_left <= {1'b0, m_tx_data[7:0]} + 9'd1;
                            st <= S_WR_DATA;
                        end
                    end
                end
                S_WR_DATA: begin
                    if (m_tx_valid && m_tx_data[127:124] == PKT_TYPE_REQ_DATA) begin
                        if (wr_req_left == 9'd1)
                            st <= S_WACK;
                        else
                            wr_req_left <= wr_req_left - 9'd1;
                    end
                end
                S_WACK: begin
                    if (!s_rx_valid) begin
                        s_rx_valid <= 1'b1;
                        s_rx_data  <= (PKT_TYPE_RSP_HDR << 124)
                            | (CHI_OP_WRITE_ACK << 122)
                            | (latched_txn << 114)
                            | (1'b0 << 113)
                            | hdr_beats_m1[7:0];
                    end else if (s_rx_valid && s_rx_ready) begin
                        s_rx_valid <= 1'b0;
                        st         <= S_IDLE;
                    end
                end
                S_RD_HDR: begin
                    if (!s_rx_valid) begin
                        s_rx_valid <= 1'b1;
                        s_rx_data  <= (PKT_TYPE_RSP_HDR << 124)
                            | (CHI_OP_READ_RESP << 122)
                            | (latched_txn << 114)
                            | (1'b1 << 113)
                            | hdr_beats_m1[7:0];
                    end else if (s_rx_valid && s_rx_ready) begin
                        s_rx_valid  <= 1'b0;
                        rd_rsp_left <= {1'b0, hdr_beats_m1} + 9'd1;
                        st          <= S_RD_DATA;
                    end
                end
                S_RD_DATA: begin
                    if (!s_rx_valid) begin
                        s_rx_valid <= 1'b1;
                        s_rx_data  <= (PKT_TYPE_RSP_DATA << 124)
                            | (latched_txn << 116)
                            | {64'd0, read_payload};
                    end else if (s_rx_valid && s_rx_ready) begin
                        s_rx_valid <= 1'b0;
                        if (rd_rsp_left == 9'd1)
                            st <= S_IDLE;
                        else
                            rd_rsp_left <= rd_rsp_left - 9'd1;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
