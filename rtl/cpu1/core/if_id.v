`include "defines.v"

module cpu1_if_id(
    input wire clk,
    input wire rst,
    input wire[`InstBus] inst_i,
    input wire[`InstAddrBus] inst_addr_i,
    input wire[`Hold_Flag_Bus] hold_flag_i,
    output wire[`InstBus] inst_o,
    output wire[`InstAddrBus] inst_addr_o
);

    wire hold_en = (hold_flag_i >= `Hold_If);

    wire[`InstBus] inst;
    cpu1_gen_pipe_dff #(32) inst_ff(clk, rst, hold_en, `INST_NOP, inst_i, inst);
    assign inst_o = inst;

    wire[`InstAddrBus] inst_addr;
    cpu1_gen_pipe_dff #(32) inst_addr_ff(clk, rst, hold_en, `ZeroWord, inst_addr_i, inst_addr);
    assign inst_addr_o = inst_addr;

endmodule
