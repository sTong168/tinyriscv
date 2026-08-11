`include "../../shared/defines.v"

// Pipeline control for branches, memory stalls, and EX stalls.
module cpu3_ctrl(
    input wire jump_flag_i,
    input wire[`InstAddrBus] jump_addr_i,
    input wire hold_flag_ex_i,
    input wire hold_flag_mem_i,
    input wire hold_flag_rib_i,
    output reg[`Hold_Flag_Bus] hold_flag_o,
    output reg jump_flag_o,
    output reg[`InstAddrBus] jump_addr_o
    );

    always @ (*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        if (jump_flag_i == `JumpEnable || hold_flag_ex_i == `HoldEnable ||
            hold_flag_mem_i == `HoldEnable) begin
            hold_flag_o = `Hold_Id;
        end else if (hold_flag_rib_i == `HoldEnable) begin
            // The IF/ID stage is flushed to NOP while a fetch is pending;
            // keeping only the PC stalled lets the instruction already in
            // the pipeline drain into ID/EX exactly once.
            hold_flag_o = `Hold_Pc;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule
