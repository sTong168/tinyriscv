`include "defines.v"

module cpu1_pc_reg(
    input wire clk,
    input wire rst,
    input wire jump_flag_i,
    input wire[`InstAddrBus] jump_addr_i,
    input wire[`Hold_Flag_Bus] hold_flag_i,
    output reg[`InstAddrBus] pc_o
);

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            pc_o <= `CpuResetAddr;
        end else if (jump_flag_i == `JumpEnable) begin
            pc_o <= jump_addr_i;
        end else if (hold_flag_i >= `Hold_Pc) begin
            pc_o <= pc_o;
        end else begin
            pc_o <= pc_o + 4'h4;
        end
    end

endmodule
