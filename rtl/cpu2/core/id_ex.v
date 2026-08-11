 /*
 Copyright 2020 Blue Liang, liangkangnan@163.com

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

`include "../../shared/defines.v"

// 将译码结果向执行模块传递
module cpu2_id_ex(

    input wire clk,
    input wire rst,

    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址
    input wire reg_we_i,                    // 写通用寄存器标志
    input wire[`RegAddrBus] reg_waddr_i,    // 写通用寄存器地址
    input wire[`RegBus] reg1_rdata_i,       // 通用寄存器1读数据
    input wire[`RegBus] reg2_rdata_i,       // 通用寄存器2读数据
    input wire[`MemAddrBus] op1_i,
    input wire[`MemAddrBus] op2_i,
    input wire[`MemAddrBus] op1_jump_i,
    input wire[`MemAddrBus] op2_jump_i,

    input wire[`Hold_Flag_Bus] hold_flag_i, // 流水线暂停标志

    output wire[`MemAddrBus] op1_o,
    output wire[`MemAddrBus] op2_o,
    output wire[`MemAddrBus] op1_jump_o,
    output wire[`MemAddrBus] op2_jump_o,
    output wire[`InstBus] inst_o,            // 指令内容
    output wire[`InstAddrBus] inst_addr_o,   // 指令地址
    output wire reg_we_o,                    // 写通用寄存器标志
    output wire[`RegAddrBus] reg_waddr_o,    // 写通用寄存器地址
    output wire[`RegBus] reg1_rdata_o,       // 通用寄存器1读数据
    output wire[`RegBus] reg2_rdata_o        // 通用寄存器2读数据

    );

    // cpu0-style dual-enable: clear -> NOP bubble, hold -> keep value
    wire clear_en = (hold_flag_i == `Hold_Id_clr ||
                     hold_flag_i == `Hold_If_keep_Id_clr);
    wire hold_en = (hold_flag_i == `Hold_Id_keep);

    wire[`InstBus] inst;
    cpu2_gen_pipe_dff #(32) inst_ff(clk, rst, clear_en, hold_en, `INST_NOP, inst_i, inst);
    assign inst_o = inst;

    wire[`InstAddrBus] inst_addr;
    cpu2_gen_pipe_dff #(32) inst_addr_ff(clk, rst, clear_en, hold_en, `ZeroWord, inst_addr_i, inst_addr);
    assign inst_addr_o = inst_addr;

    wire reg_we;
    cpu2_gen_pipe_dff #(1) reg_we_ff(clk, rst, clear_en, hold_en, `WriteDisable, reg_we_i, reg_we);
    assign reg_we_o = reg_we;

    wire[`RegAddrBus] reg_waddr;
    cpu2_gen_pipe_dff #(5) reg_waddr_ff(clk, rst, clear_en, hold_en, `ZeroReg, reg_waddr_i, reg_waddr);
    assign reg_waddr_o = reg_waddr;

    wire[`RegBus] reg1_rdata;
    cpu2_gen_pipe_dff #(32) reg1_rdata_ff(clk, rst, clear_en, hold_en, `ZeroWord, reg1_rdata_i, reg1_rdata);
    assign reg1_rdata_o = reg1_rdata;

    wire[`RegBus] reg2_rdata;
    cpu2_gen_pipe_dff #(32) reg2_rdata_ff(clk, rst, clear_en, hold_en, `ZeroWord, reg2_rdata_i, reg2_rdata);
    assign reg2_rdata_o = reg2_rdata;

    wire[`MemAddrBus] op1;
    cpu2_gen_pipe_dff #(32) op1_ff(clk, rst, clear_en, hold_en, `ZeroWord, op1_i, op1);
    assign op1_o = op1;

    wire[`MemAddrBus] op2;
    cpu2_gen_pipe_dff #(32) op2_ff(clk, rst, clear_en, hold_en, `ZeroWord, op2_i, op2);
    assign op2_o = op2;

    wire[`MemAddrBus] op1_jump;
    cpu2_gen_pipe_dff #(32) op1_jump_ff(clk, rst, clear_en, hold_en, `ZeroWord, op1_jump_i, op1_jump);
    assign op1_jump_o = op1_jump;

    wire[`MemAddrBus] op2_jump;
    cpu2_gen_pipe_dff #(32) op2_jump_ff(clk, rst, clear_en, hold_en, `ZeroWord, op2_jump_i, op2_jump);
    assign op2_jump_o = op2_jump;

endmodule
