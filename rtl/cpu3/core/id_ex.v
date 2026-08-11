`include "../../shared/defines.v"

// ID/EX pipeline register for the RV32I datapath.
module cpu3_id_ex(
    input wire clk,
    input wire rst,
    input wire[`InstBus] inst_i,
    input wire reg_we_i,
    input wire[`RegAddrBus] reg_waddr_i,
    input wire[`RegBus] reg1_rdata_i,
    input wire[`RegBus] reg2_rdata_i,
    input wire[`MemAddrBus] op1_i,
    input wire[`MemAddrBus] op2_i,
    input wire[`MemAddrBus] op1_jump_i,
    input wire[`MemAddrBus] op2_jump_i,
    input wire[`Hold_Flag_Bus] hold_flag_i,

    output wire[`MemAddrBus] op1_o,
    output wire[`MemAddrBus] op2_o,
    output wire[`MemAddrBus] op1_jump_o,
    output wire[`MemAddrBus] op2_jump_o,
    output wire[`InstBus] inst_o,
    output wire reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus] reg1_rdata_o,
    output wire[`RegBus] reg2_rdata_o
    );

    wire hold_en = (hold_flag_i >= `Hold_Id);

    cpu3_gen_pipe_dff #(32) inst_ff(clk, rst, hold_en, `INST_NOP, inst_i, inst_o);
    cpu3_gen_pipe_dff #(1) reg_we_ff(clk, rst, hold_en, `WriteDisable, reg_we_i, reg_we_o);
    cpu3_gen_pipe_dff #(5) reg_waddr_ff(clk, rst, hold_en, `ZeroReg, reg_waddr_i, reg_waddr_o);
    cpu3_gen_pipe_dff #(32) reg1_rdata_ff(clk, rst, hold_en, `ZeroWord, reg1_rdata_i, reg1_rdata_o);
    cpu3_gen_pipe_dff #(32) reg2_rdata_ff(clk, rst, hold_en, `ZeroWord, reg2_rdata_i, reg2_rdata_o);
    cpu3_gen_pipe_dff #(32) op1_ff(clk, rst, hold_en, `ZeroWord, op1_i, op1_o);
    cpu3_gen_pipe_dff #(32) op2_ff(clk, rst, hold_en, `ZeroWord, op2_i, op2_o);
    cpu3_gen_pipe_dff #(32) op1_jump_ff(clk, rst, hold_en, `ZeroWord, op1_jump_i, op1_jump_o);
    cpu3_gen_pipe_dff #(32) op2_jump_ff(clk, rst, hold_en, `ZeroWord, op2_jump_i, op2_jump_o);

endmodule
