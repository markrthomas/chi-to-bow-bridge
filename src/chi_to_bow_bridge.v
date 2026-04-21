module chi_to_bow_bridge #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64
) (
    input  wire                     clk,
    input  wire                     rst_n,

    // Simplified CHI request channel (RX from CHI fabric)
    input  wire                     chi_req_valid,
    output wire                     chi_req_ready,
    input  wire [1:0]               chi_req_opcode, // 2'b00=READ, 2'b01=WRITE
    input  wire [ADDR_WIDTH-1:0]    chi_req_addr,
    input  wire [DATA_WIDTH-1:0]    chi_req_data,
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
    input  wire [127:0]             bow_rx_data
);

    localparam CHI_OP_READ      = 2'b00;
    localparam CHI_OP_WRITE     = 2'b01;
    localparam CHI_OP_READ_RESP = 2'b10;
    localparam CHI_OP_WRITE_ACK = 2'b11;

    // BoW packet format v2 (multi-flit capable):
    // Header flit:
    // [127:124] type
    // [123:122] opcode
    // [121:114] txnid
    // [113]     has_data
    // [112:49]  addr (request header only)
    // [48:0]    reserved
    //
    // Data flit:
    // [127:124] type
    // [123:116] txnid
    // [115:0]   data payload (uses DATA_WIDTH LSBs)
    localparam PKT_TYPE_REQ_HDR  = 4'h1;
    localparam PKT_TYPE_REQ_DATA = 4'h2;
    localparam PKT_TYPE_RSP_HDR  = 4'h3;
    localparam PKT_TYPE_RSP_DATA = 4'h4;

    reg tx_need_data_flit;
    reg [7:0] tx_data_txnid;
    reg [DATA_WIDTH-1:0] tx_data_payload;
    reg [255:0] pending_txn;
    reg [255:0] rsp_need_data;
    reg [1:0] rsp_opcode_table [0:255];

    wire txn_slot_free = ~pending_txn[chi_req_txnid];
    wire can_accept_req = (~bow_tx_valid) & (~tx_need_data_flit) & txn_slot_free;
    assign chi_req_ready = can_accept_req & bow_tx_ready;

    // Always ready to consume BoW RX unless response is blocked.
    assign bow_rx_ready = (~chi_rsp_valid) | chi_rsp_ready;

    wire req_fire = chi_req_valid & chi_req_ready;
    wire rx_fire  = bow_rx_valid & bow_rx_ready;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bow_tx_valid   <= 1'b0;
            bow_tx_data    <= 128'd0;
            chi_rsp_valid  <= 1'b0;
            chi_rsp_opcode <= 2'b00;
            chi_rsp_data   <= {DATA_WIDTH{1'b0}};
            chi_rsp_txnid  <= 8'd0;
            tx_need_data_flit <= 1'b0;
            tx_data_txnid     <= 8'd0;
            tx_data_payload   <= {DATA_WIDTH{1'b0}};
            pending_txn       <= {256{1'b0}};
            rsp_need_data     <= {256{1'b0}};
            for (i = 0; i < 256; i = i + 1) begin
                rsp_opcode_table[i] <= 2'b00;
            end
        end else begin
            // Hold valid until handshake.
            if (bow_tx_valid && bow_tx_ready) begin
                bow_tx_valid <= 1'b0;
            end

            if (chi_rsp_valid && chi_rsp_ready) begin
                chi_rsp_valid <= 1'b0;
            end

            // Emit pending TX data flit before accepting new CHI traffic.
            if ((!bow_tx_valid) && tx_need_data_flit) begin
                bow_tx_valid <= 1'b1;
                bow_tx_data  <= {
                    PKT_TYPE_REQ_DATA,
                    tx_data_txnid,
                    {{(116-DATA_WIDTH){1'b0}}, tx_data_payload}
                };
                tx_need_data_flit <= 1'b0;
            end

            // Ingress CHI request -> BoW header flit (+ optional data flit)
            if (req_fire) begin
                bow_tx_valid <= 1'b1;
                bow_tx_data  <= {
                    PKT_TYPE_REQ_HDR,      // [127:124]
                    chi_req_opcode,        // [123:122]
                    chi_req_txnid,         // [121:114]
                    (chi_req_opcode == CHI_OP_WRITE), // [113] has_data
                    chi_req_addr,          // [112:49]
                    49'd0                  // [48:0]
                };
                pending_txn[chi_req_txnid] <= 1'b1;
                if (chi_req_opcode == CHI_OP_WRITE) begin
                    tx_need_data_flit <= 1'b1;
                    tx_data_txnid     <= chi_req_txnid;
                    tx_data_payload   <= chi_req_data;
                end
            end

            // Ingress BoW response flits -> CHI response
            if (rx_fire) begin
                if (bow_rx_data[127:124] == PKT_TYPE_RSP_HDR) begin
                    if (bow_rx_data[113]) begin
                        rsp_need_data[bow_rx_data[121:114]] <= 1'b1;
                        rsp_opcode_table[bow_rx_data[121:114]] <= bow_rx_data[123:122];
                    end else begin
                        chi_rsp_valid  <= 1'b1;
                        chi_rsp_opcode <= bow_rx_data[123:122];
                        chi_rsp_txnid  <= bow_rx_data[121:114];
                        chi_rsp_data   <= {DATA_WIDTH{1'b0}};
                        pending_txn[bow_rx_data[121:114]] <= 1'b0;
                    end
                end else if ((bow_rx_data[127:124] == PKT_TYPE_RSP_DATA) && rsp_need_data[bow_rx_data[123:116]]) begin
                    chi_rsp_valid                         <= 1'b1;
                    chi_rsp_opcode                        <= rsp_opcode_table[bow_rx_data[123:116]];
                    chi_rsp_txnid                         <= bow_rx_data[123:116];
                    chi_rsp_data                          <= bow_rx_data[DATA_WIDTH-1:0];
                    rsp_need_data[bow_rx_data[123:116]]  <= 1'b0;
                    pending_txn[bow_rx_data[123:116]]    <= 1'b0;
                end
            end
        end
    end

endmodule
