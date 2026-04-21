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

    // BoW packet format (single-flit fixed 128b):
    // [127:124] type
    // [123:122] opcode
    // [121:114] txnid
    // [113:50]  addr
    // [49:0]    data[49:0]   (for demo simplicity, truncated from DATA_WIDTH)
    localparam PKT_TYPE_REQ  = 4'h1;
    localparam PKT_TYPE_RESP = 4'h2;

    reg req_pending;

    wire can_accept_req = (~req_pending) & (~bow_tx_valid);
    assign chi_req_ready = can_accept_req & bow_tx_ready;

    // Always ready to consume BoW RX unless response is blocked.
    assign bow_rx_ready = (~chi_rsp_valid) | chi_rsp_ready;

    wire req_fire = chi_req_valid & chi_req_ready;
    wire rsp_fire = chi_rsp_valid & chi_rsp_ready;
    wire rx_fire  = bow_rx_valid & bow_rx_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bow_tx_valid   <= 1'b0;
            bow_tx_data    <= 128'd0;
            chi_rsp_valid  <= 1'b0;
            chi_rsp_opcode <= 2'b00;
            chi_rsp_data   <= {DATA_WIDTH{1'b0}};
            chi_rsp_txnid  <= 8'd0;
            req_pending    <= 1'b0;
        end else begin
            // Hold valid until handshake.
            if (bow_tx_valid && bow_tx_ready) begin
                bow_tx_valid <= 1'b0;
            end

            if (chi_rsp_valid && chi_rsp_ready) begin
                chi_rsp_valid <= 1'b0;
            end

            // Ingress CHI request -> BoW packet
            if (req_fire) begin
                bow_tx_valid <= 1'b1;
                bow_tx_data  <= {
                    PKT_TYPE_REQ,          // [127:124]
                    chi_req_opcode,        // [123:122]
                    chi_req_txnid,         // [121:114]
                    chi_req_addr,          // [113:50]
                    chi_req_data[49:0]     // [49:0]
                };
                req_pending <= 1'b1;
            end

            // Ingress BoW response -> CHI response
            if (rx_fire) begin
                if (bow_rx_data[127:124] == PKT_TYPE_RESP) begin
                    chi_rsp_valid  <= 1'b1;
                    chi_rsp_opcode <= bow_rx_data[123:122];
                    chi_rsp_txnid  <= bow_rx_data[121:114];
                    chi_rsp_data   <= {{(DATA_WIDTH-50){1'b0}}, bow_rx_data[49:0]};
                    req_pending    <= 1'b0;
                end
            end

            // If response accepted and no new response arrives this cycle, clear pending only if not already
            // handled by rx_fire. (No additional action needed in this simplified model.)
            if (rsp_fire && !rx_fire) begin
                // no-op
            end
        end
    end

endmodule
