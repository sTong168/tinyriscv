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
    input wire preserve_i,

    output reg[`MemAddrBus] op1_o,
    output reg[`MemAddrBus] op2_o,
    output reg[`MemAddrBus] op1_jump_o,
    output reg[`MemAddrBus] op2_jump_o,
    output reg[`InstBus] inst_o,
    output reg reg_we_o,
    output reg[`RegAddrBus] reg_waddr_o,
    output reg[`RegBus] reg1_rdata_o,
    output reg[`RegBus] reg2_rdata_o
    );

    wire hold_en = (hold_flag_i >= `Hold_Id);
    wire imm_opcode = (inst_i[6:0] == `INST_TYPE_I) ||
                      (inst_i[6:0] == `INST_TYPE_L);
    wire[`MemAddrBus] op2_capture = imm_opcode ?
                                    {{20{inst_i[31]}}, inst_i[31:20]} :
                                    op2_i;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            inst_o <= `INST_NOP;
            reg_we_o <= `WriteDisable;
            reg_waddr_o <= `ZeroReg;
            reg1_rdata_o <= `ZeroWord;
            reg2_rdata_o <= `ZeroWord;
            op1_o <= `ZeroWord;
            op2_o <= `ZeroWord;
            op1_jump_o <= `ZeroWord;
            op2_jump_o <= `ZeroWord;
        end else if (preserve_i) begin
            // Keep the execute inputs stable while writeback samples them.
        end else if (hold_en) begin
            inst_o <= `INST_NOP;
            reg_we_o <= `WriteDisable;
            reg_waddr_o <= `ZeroReg;
            reg1_rdata_o <= `ZeroWord;
            reg2_rdata_o <= `ZeroWord;
            op1_o <= `ZeroWord;
            op2_o <= `ZeroWord;
            op1_jump_o <= `ZeroWord;
            op2_jump_o <= `ZeroWord;
        end else begin
            inst_o <= inst_i;
            reg_we_o <= reg_we_i;
            reg_waddr_o <= reg_waddr_i;
            reg1_rdata_o <= reg1_rdata_i;
            reg2_rdata_o <= reg2_rdata_i;
            op1_o <= op1_i;
            op2_o <= op2_capture;
            op1_jump_o <= op1_jump_i;
            op2_jump_o <= op2_jump_i;
        end
    end

endmodule
