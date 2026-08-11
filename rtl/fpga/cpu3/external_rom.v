`include "../../shared/defines.v"

// FPGA-side external ROM image. The image is writable by uart_debug during
// firmware download and is read by both instruction and data transactions.
module external_rom(
    input wire clk,
    input wire we_i,
    input wire[7:0] addr_i,
    input wire[`MemBus] data_i,
    output wire[`MemBus] data_o
    );

    reg[`MemBus] mem[0:255];

    always @ (posedge clk) begin
        if (we_i) begin
            mem[addr_i] <= data_i;
        end
    end

    assign data_o = mem[addr_i];

endmodule
