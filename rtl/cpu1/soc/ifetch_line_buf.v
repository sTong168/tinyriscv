// ifetch_line_buf.v — single-word ROM fetch buffer for EMIF-8 mode
`include "../core/defines.v"

module cpu1_ifetch_line_buf(
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] addr_i,
    input  wire        req_i,
    output wire [31:0] rdata_o,
    output wire        hit_o,
    output wire        miss_o,

    output reg  [31:0] refill_addr_o,
    output reg         refill_req_o,
    input  wire [31:0] refill_rdata_i,
    input  wire        refill_done_i
);

    reg [31:0] tag_q, data_q;
    reg        valid_q;

    wire tag_match = valid_q && (tag_q[31:2] == addr_i[31:2]);

    assign hit_o   = req_i && tag_match;
    assign miss_o  = req_i && !tag_match;
    assign rdata_o = data_q;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            valid_q      <= 1'b0;
            refill_req_o <= 1'b0;
        end else begin
            refill_req_o <= miss_o && !refill_req_o;
            if (miss_o)
                refill_addr_o <= addr_i;
            if (refill_done_i) begin
                valid_q <= 1'b1;
                tag_q   <= refill_addr_o;
                data_q  <= refill_rdata_i;
            end
        end
    end

endmodule
