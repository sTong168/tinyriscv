`include "../core/defines.v"

// 32-bit Fibonacci LFSR — hardware random number generator
// Slave address: 0x2000_0000  (slave 2 on RIB bus)
//
// Register map (all accesses word-aligned):
//   Read  any address : return current LFSR value
//   Write any address : reseed LFSR with written value (0 → use default seed)
//
// Polynomial: x^32 + x^22 + x^2 + x + 1  (primitive, maximal-length 2^32-1)
// Feedback:   lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]  (left-shift)
module cpu1_lfsr(
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] addr_i,
    input  wire [31:0] data_i,
    input  wire        we_i,
    output wire [31:0] data_o
);

    localparam SEED = 32'hDEAD_BEEF;

    reg [31:0] lfsr_r;

    wire fb = lfsr_r[31] ^ lfsr_r[21] ^ lfsr_r[1] ^ lfsr_r[0];

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            lfsr_r <= SEED;
        end else if (we_i) begin
            // CPU reseed: write 0 to reset to default seed, else use value
            lfsr_r <= (data_i == 32'h0) ? SEED : data_i;
        end else begin
            // Advance LFSR every clock cycle
            lfsr_r <= {lfsr_r[30:0], fb};
        end
    end

    assign data_o = lfsr_r;

endmodule
