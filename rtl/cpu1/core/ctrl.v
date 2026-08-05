`include "defines.v"

module cpu1_ctrl(
    input wire rst,
    input wire jump_flag_i,
    input wire[`InstAddrBus] jump_addr_i,
    input wire hold_flag_ex_i,
    input wire hold_flag_rib_i,
    output reg[`Hold_Flag_Bus] hold_flag_o,
    output reg jump_flag_o,
    output reg[`InstAddrBus] jump_addr_o
);

    always @ (*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        hold_flag_o = `Hold_None;
        if (jump_flag_i == `JumpEnable || hold_flag_ex_i == `HoldEnable) begin
            hold_flag_o = `Hold_Id;
        end else if (hold_flag_rib_i == `HoldEnable) begin
            hold_flag_o = `Hold_Pc;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule
