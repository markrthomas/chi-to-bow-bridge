module chi_to_bow_bridge #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter FIFO_DEPTH = 4
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // Simplified CHI request channel (RX from CHI fabric)
    input  wire                     chi_req_valid,
    output wire                     chi_req_ready,
    input  wire [1:0]               chi_req_opcode, // 2'b00=READ, 2'b01=WRITE
    input  wire [ADDR_WIDTH-1:0]    chi_req_addr,
    input  wire [DATA_WIDTH-1:0]    chi_req_data,
    // Number of data beats for this transaction:
    // - writes: number of BoW REQ_DATA flits emitted after REQ_HDR
    // - reads: number of BoW RSP_DATA flits expected after RSP_HDR (has_data=1)
    // Must be >= 1. For writes, all beats currently use the same `chi_req_data` payload.
    input  wire [7:0]               chi_req_beats,
    input  wire [7:0]               chi_req_txnid,

    // Simplified CHI response channel (TX to CHI fabric)
    output reg                      chi_rsp_valid,
    input  wire                     chi_rsp_ready,
    output reg  [1:0]               chi_rsp_opcode, // 2'b10=READ_RESP, 2'b11=WRITE_ACK
    output reg  [DATA_WIDTH-1:0]    chi_rsp_data,
    output reg  [7:0]               chi_rsp_txnid,

    // BoW egress (toward die-to-die link)
    output reg                      bow_tx_valid,
    input  wire                     bow_tx_ready,
    output reg  [127:0]             bow_tx_data,

    // BoW ingress (from die-to-die link)
    input  wire                     bow_rx_valid,
    output wire                     bow_rx_ready,
    input  wire [127:0]             bow_rx_data,

    // Observability / guardrails
    output reg  [31:0]              err_unknown_txn_rsp_hdr,
    output reg  [31:0]              err_unknown_txn_rsp_data,
    output reg  [31:0]              err_dup_rsp_hdr,
    output reg  [31:0]              err_orphan_rsp_data,
    output reg  [31:0]              err_illegal_req_hdr,
    output reg  [31:0]              err_illegal_rsp_hdr,

    output reg                      err_pulse,
    output wire [7:0]               dbg_chi_req_fifo_used,
    output wire [7:0]               dbg_bow_rx_fifo_used,
    output wire [255:0]             dbg_pending_txn,
    output wire [255:0]             dbg_rsp_need_data
);

    localparam CHI_OP_READ       = 2'b00;
    localparam CHI_OP_WRITE      = 2'b01;
    localparam CHI_OP_READ_RESP   = 2'b10;
    localparam CHI_OP_WRITE_ACK  = 2'b11;

    localparam PKT_TYPE_REQ_HDR   = 4'h1;
    localparam PKT_TYPE_REQ_DATA  = 4'h2;
    localparam PKT_TYPE_RSP_HDR   = 4'h3;
    localparam PKT_TYPE_RSP_DATA  = 4'h4;

    localparam PTR_W = $clog2(FIFO_DEPTH);
    localparam CNT_W = PTR_W + 1;

    integer i;

    // ---------------------------------------------------------------------
    // Outstanding transaction table (by txnid)
    // ---------------------------------------------------------------------
    reg [255:0] pending_txn;
    reg [255:0] pending_txn_hold;

    // `txn_slot_free` must not depend on same-cycle `pending_set_mask` (TX commit), otherwise CHI
    // acceptance becomes self-referential and can wedge if a txnid is already outstanding.
    wire txn_slot_free = ~pending_txn_hold[chi_req_txnid];

    assign dbg_pending_txn = pending_txn;

    // `pending_txn` must have exactly one sequential driver. TX commits requests;
    // RX completes them (and may clear bits on protocol errors).
    reg [255:0] pending_clr_mask;

    // ---------------------------------------------------------------------
    // CHI request FIFO (packed fields)
    // ---------------------------------------------------------------------
    localparam CHI_REQ_FIFO_W = 2 + ADDR_WIDTH + DATA_WIDTH + 8 + 8;

    reg [CHI_REQ_FIFO_W-1:0] chi_mem [0:FIFO_DEPTH-1];
    reg [PTR_W-1:0] chi_wr_ptr;
    reg [PTR_W-1:0] chi_rd_ptr;
    reg [CNT_W-1:0] chi_count;

    wire chi_empty = (chi_count == {CNT_W{1'b0}});
    wire chi_full  = (chi_count == FIFO_DEPTH[CNT_W-1:0]);

    assign chi_req_ready = (!chi_full) & txn_slot_free;

    // Only enqueue legal CHI request opcodes. Illegal REQ-channel encodings are counted and dropped.
    wire chi_req_beats_ok = (chi_req_beats != 8'd0);
    wire chi_push = chi_req_valid & chi_req_ready & chi_req_beats_ok &
        ((chi_req_opcode == CHI_OP_READ) || (chi_req_opcode == CHI_OP_WRITE));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            chi_wr_ptr <= {PTR_W{1'b0}};
            chi_rd_ptr <= {PTR_W{1'b0}};
            chi_count  <= {CNT_W{1'b0}};
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                chi_mem[i] <= {CHI_REQ_FIFO_W{1'b0}};
            end
        end else begin
            if (chi_push && chi_pop) begin
                chi_count <= chi_count;
            end else if (chi_push) begin
                chi_count <= chi_count + 1'b1;
            end else if (chi_pop) begin
                chi_count <= chi_count - 1'b1;
            end

            if (chi_push) begin
                chi_mem[chi_wr_ptr] <= {
                    chi_req_opcode,
                    chi_req_addr,
                    chi_req_data,
                    chi_req_beats,
                    chi_req_txnid
                };
                chi_wr_ptr <= chi_wr_ptr + 1'b1;
            end

            if (chi_pop) begin
                chi_rd_ptr <= chi_rd_ptr + 1'b1;
            end
        end
    end

    wire [CHI_REQ_FIFO_W-1:0] chi_peek = chi_mem[chi_rd_ptr];
    // FIFO packing (MSB -> LSB): {opcode, addr, data, beats, txnid}
    wire [1:0]              chi_peek_opcode = chi_peek[CHI_REQ_FIFO_W-1 -: 2];
    wire [ADDR_WIDTH-1:0]  chi_peek_addr   = chi_peek[CHI_REQ_FIFO_W-3 -: ADDR_WIDTH];
    wire [DATA_WIDTH-1:0]  chi_peek_data   = chi_peek[CHI_REQ_FIFO_W-3-ADDR_WIDTH -: DATA_WIDTH];
    wire [7:0]              chi_peek_beats = chi_peek[15:8];
    wire [7:0]              chi_peek_txnid = chi_peek[7:0];

    assign dbg_chi_req_fifo_used = {{(8 - CNT_W){1'b0}}, chi_count};

    // ---------------------------------------------------------------------
    // BoW RX FIFO (raw flits)
    // ---------------------------------------------------------------------
    reg [127:0] bow_mem [0:FIFO_DEPTH-1];
    reg [PTR_W-1:0] bow_wr_ptr;
    reg [PTR_W-1:0] bow_rd_ptr;
    reg [CNT_W-1:0] bow_count;

    wire bow_empty = (bow_count == {CNT_W{1'b0}});
    wire bow_full  = (bow_count == FIFO_DEPTH[CNT_W-1:0]);
    wire bow_gte1  = (bow_count != {CNT_W{1'b0}});
    wire bow_gte2  = (bow_count > {{(CNT_W-1){1'b0}}, 1'b1});

    // Avoid push+pop when the FIFO is empty (count==0): the read would happen before the write
    // updates the read pointer / memory cell for that slot.
    wire bow_rx_pop_ok =
        (((!bow_empty) || bow_push) && (bow_gte2 || ((!bow_push) && bow_gte1))) &&
        ((!chi_rsp_valid) || chi_rsp_ready);

    assign bow_rx_ready = ~bow_full;

    wire bow_push = bow_rx_valid & bow_rx_ready;
    reg  bow_pop;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bow_wr_ptr <= {PTR_W{1'b0}};
            bow_rd_ptr <= {PTR_W{1'b0}};
            bow_count  <= {CNT_W{1'b0}};
            bow_pop <= 1'b0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
                bow_mem[i] <= 128'd0;
            end
        end else begin
            if (bow_push && bow_pop) begin
                bow_count <= bow_count;
            end else if (bow_push) begin
                bow_count <= bow_count + 1'b1;
            end else if (bow_pop) begin
                bow_count <= bow_count - 1'b1;
            end

            if (bow_push) begin
                bow_mem[bow_wr_ptr] <= bow_rx_data;
                bow_wr_ptr <= bow_wr_ptr + 1'b1;
            end

            if (bow_pop) begin
                bow_rd_ptr <= bow_rd_ptr + 1'b1;
            end
        end
    end

    wire [127:0] bow_peek = bow_mem[bow_rd_ptr];

    assign dbg_bow_rx_fifo_used = {{(8 - CNT_W){1'b0}}, bow_count};

    // ---------------------------------------------------------------------
    // TX: CHI request FIFO -> BoW REQ_HDR/REQ_DATA
    // ---------------------------------------------------------------------
    reg tx_need_data;
    reg [7:0] tx_data_txnid;
    reg [DATA_WIDTH-1:0] tx_data_payload;
    reg [7:0] tx_burst_rem;

    wire can_issue_data = (!bow_tx_valid) && tx_need_data && bow_tx_ready;
    wire can_issue_hdr  = (!bow_tx_valid) && (!tx_need_data) && bow_tx_ready && (!chi_empty);
    wire chi_pop = can_issue_hdr;
    wire [255:0] pending_set_mask_now =
        can_issue_hdr ? ({{255{1'b0}}, 1'b1} << chi_peek_txnid) : {256{1'b0}};
    wire [255:0] pending_next = (pending_txn_hold | pending_set_mask_now) & ~pending_clr_mask;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bow_tx_valid <= 1'b0;
            bow_tx_data  <= 128'd0;
            tx_need_data <= 1'b0;
            tx_data_txnid <= 8'd0;
            tx_data_payload <= {DATA_WIDTH{1'b0}};
            tx_burst_rem <= 8'd0;
        end else begin
            if (bow_tx_valid && bow_tx_ready) begin
                bow_tx_valid <= 1'b0;
            end

            if (can_issue_data) begin
                bow_tx_valid <= 1'b1;
                bow_tx_data  <= {
                    PKT_TYPE_REQ_DATA,
                    tx_data_txnid,
                    {{(116-DATA_WIDTH){1'b0}}, tx_data_payload}
                };
                if (tx_burst_rem > 8'd1) begin
                    tx_burst_rem <= tx_burst_rem - 8'd1;
                    tx_need_data <= 1'b1;
                end else begin
                    tx_burst_rem <= 8'd0;
                    tx_need_data <= 1'b0;
                end
            end else if (can_issue_hdr) begin
                bow_tx_valid <= 1'b1;
                bow_tx_data  <= {
                    PKT_TYPE_REQ_HDR,
                    chi_peek_opcode,
                    chi_peek_txnid,
                    (chi_peek_opcode == CHI_OP_WRITE),
                    chi_peek_addr[63:0],
                    {{(49-8){1'b0}}, (chi_peek_beats - 8'd1)}
                };

                if (chi_peek_opcode == CHI_OP_WRITE) begin
                    tx_need_data <= 1'b1;
                    tx_data_txnid <= chi_peek_txnid;
                    tx_data_payload <= chi_peek_data;
                    tx_burst_rem <= chi_peek_beats;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // RX: BoW RX FIFO -> CHI RSP (+ guardrails)
    // ---------------------------------------------------------------------
    reg [255:0] rsp_need_data;
    reg [1:0] rsp_opcode_table [0:255];
    reg [7:0] rsp_rem_beats [0:255];

    reg rx_flit_valid;
    /* verilator lint_off UNUSEDSIGNAL */
    reg [127:0] rx_flit;
    /* verilator lint_on UNUSEDSIGNAL */

    reg chi_req_seen;

    assign dbg_rsp_need_data = rsp_need_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_flit_valid <= 1'b0;
            rx_flit <= 128'd0;

            pending_txn <= {256{1'b0}};
            pending_txn_hold <= {256{1'b0}};

            chi_rsp_valid  <= 1'b0;
            chi_rsp_opcode <= 2'b00;
            chi_rsp_data   <= {DATA_WIDTH{1'b0}};
            chi_rsp_txnid  <= 8'd0;

            rsp_need_data <= {256{1'b0}};
            for (i = 0; i < 256; i = i + 1) begin
                rsp_opcode_table[i] <= 2'b00;
                rsp_rem_beats[i] <= 8'd0;
            end

            err_unknown_txn_rsp_hdr <= 32'd0;
            err_unknown_txn_rsp_data <= 32'd0;
            err_dup_rsp_hdr <= 32'd0;
            err_orphan_rsp_data <= 32'd0;
            err_illegal_req_hdr <= 32'd0;
            err_illegal_rsp_hdr <= 32'd0;
            err_pulse <= 1'b0;
            pending_clr_mask <= {256{1'b0}};
            chi_req_seen <= 1'b0;
        end else begin
            bow_pop <= 1'b0;
            err_pulse <= 1'b0;
            pending_clr_mask <= {256{1'b0}};

            if (chi_rsp_valid && chi_rsp_ready) begin
                chi_rsp_valid <= 1'b0;
            end

            // Illegal CHI request opcode values (responses are not valid on REQ channel).
            // Illegal opcodes are protocol violations even if we cannot accept them into the bridge FIFO.
            // Count once per rising edge of chi_req_valid while the opcode remains illegal.
            if (chi_req_valid && !chi_req_seen &&
                ((chi_req_opcode == CHI_OP_READ_RESP) || (chi_req_opcode == CHI_OP_WRITE_ACK))) begin
                err_illegal_req_hdr <= err_illegal_req_hdr + 32'd1;
                err_pulse <= 1'b1;
                chi_req_seen <= 1'b1;
            end else if (!chi_req_valid) begin
                chi_req_seen <= 1'b0;
            end

            // Pop one BoW RX flit per cycle when the CHI response sink can accept a new beat.
            if (rx_flit_valid) begin
                if (rx_flit[127:124] == PKT_TYPE_RSP_HDR) begin
                    if ((rx_flit[123:122] == CHI_OP_WRITE_ACK) && rx_flit[113]) begin
                        err_illegal_rsp_hdr <= err_illegal_rsp_hdr + 32'd1;
                        err_pulse <= 1'b1;
                    end else if ((rx_flit[123:122] == CHI_OP_READ_RESP) && !rx_flit[113]) begin
                        err_illegal_rsp_hdr <= err_illegal_rsp_hdr + 32'd1;
                        err_pulse <= 1'b1;
                    end

                    if ((rx_flit[123:122] == CHI_OP_READ_RESP) && rx_flit[113] && !pending_txn_hold[rx_flit[121:114]]) begin
                        err_unknown_txn_rsp_hdr <= err_unknown_txn_rsp_hdr + 32'd1;
                        err_pulse <= 1'b1;
                    end else if ((rx_flit[123:122] == CHI_OP_WRITE_ACK) && !pending_txn_hold[rx_flit[121:114]]) begin
                        err_unknown_txn_rsp_hdr <= err_unknown_txn_rsp_hdr + 32'd1;
                        err_pulse <= 1'b1;
                    end else if (rx_flit[113]) begin
                        if (rsp_need_data[rx_flit[121:114]]) begin
                            err_dup_rsp_hdr <= err_dup_rsp_hdr + 32'd1;
                            err_pulse <= 1'b1;
                            rsp_need_data[rx_flit[121:114]] <= 1'b0;
                            rsp_rem_beats[rx_flit[121:114]] <= 8'd0;
                            pending_clr_mask[rx_flit[121:114]] <= 1'b1;
                        end else begin
                            rsp_need_data[rx_flit[121:114]] <= 1'b1;
                            rsp_opcode_table[rx_flit[121:114]] <= rx_flit[123:122];
                            rsp_rem_beats[rx_flit[121:114]] <= rx_flit[7:0];
                        end
                    end else begin
                        chi_rsp_valid  <= 1'b1;
                        chi_rsp_opcode <= rx_flit[123:122];
                        chi_rsp_txnid  <= rx_flit[121:114];
                        chi_rsp_data   <= {DATA_WIDTH{1'b0}};
                        pending_clr_mask[rx_flit[121:114]] <= 1'b1;
                    end
                end else if (rx_flit[127:124] == PKT_TYPE_RSP_DATA) begin
                    if (!rsp_need_data[rx_flit[123:116]]) begin
                        err_orphan_rsp_data <= err_orphan_rsp_data + 32'd1;
                        err_pulse <= 1'b1;
                    end else if (!pending_txn_hold[rx_flit[123:116]]) begin
                        err_unknown_txn_rsp_data <= err_unknown_txn_rsp_data + 32'd1;
                        err_pulse <= 1'b1;
                        rsp_need_data[rx_flit[123:116]] <= 1'b0;
                        rsp_rem_beats[rx_flit[123:116]] <= 8'd0;
                    end else begin
                        if (rsp_rem_beats[rx_flit[123:116]] != 8'd0) begin
                            rsp_rem_beats[rx_flit[123:116]] <= rsp_rem_beats[rx_flit[123:116]] - 8'd1;
                        end else begin
                            chi_rsp_valid  <= 1'b1;
                            chi_rsp_opcode <= rsp_opcode_table[rx_flit[123:116]];
                            chi_rsp_txnid  <= rx_flit[123:116];
                            chi_rsp_data   <= rx_flit[DATA_WIDTH-1:0];
                            rsp_need_data[rx_flit[123:116]] <= 1'b0;
                            pending_clr_mask[rx_flit[123:116]] <= 1'b1;
                        end
                    end
                end

                rx_flit_valid <= 1'b0;
            end else if (bow_rx_pop_ok) begin
                rx_flit <= bow_peek;
                rx_flit_valid <= 1'b1;
                bow_pop <= 1'b1;
            end

            pending_txn <= pending_next;
            pending_txn_hold <= pending_next;
        end
    end

endmodule
