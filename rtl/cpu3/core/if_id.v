`include "../../shared/defines.v"

// IF/ID pipeline register.
module cpu3_if_id(
    input wire clk,
    input wire rst,
    input wire[`InstBus] inst_i,
    input wire[`InstAddrBus] inst_addr_i,
    input wire[`Hold_Flag_Bus] hold_flag_i,
    input wire inst_valid_i,
    input wire preserve_i,
    output wire[`InstBus] inst_o,
    output wire[`InstAddrBus] inst_addr_o
    );

    // A shared-register read can take a cycle.  Keep the already fetched
    // instruction in IF/ID until its operands are acknowledged instead of
    // flushing it through the normal hold-to-NOP path.
    wire hold_en = preserve_i || (hold_flag_i >= `Hold_If) || !inst_valid_i;

    cpu3_gen_pipe_dff #(32) inst_ff(clk, rst, hold_en, `INST_NOP, inst_i, inst_o);
    cpu3_gen_pipe_dff #(32) inst_addr_ff(clk, rst, hold_en, `ZeroWord, inst_addr_i, inst_addr_o);

endmodule
