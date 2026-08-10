`include "../core/defines.v"

// FPGA-side data RAM. The address selects one of sixteen 32-bit words.
module external_ram(
    input wire clk,
    input wire we_i,
    input wire[3:0] addr_i,
    input wire[`MemBus] data_i,
    output wire[`MemBus] data_o
    );

    reg[`MemBus] mem[0:15];

    always @ (posedge clk) begin
        if (we_i) begin
            mem[addr_i] <= data_i;
        end
    end

    assign data_o = mem[addr_i];

endmodule
