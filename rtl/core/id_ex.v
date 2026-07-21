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

`include "defines.v"

// 灏嗚瘧鐮佺粨鏋滃悜鎵ц妯″潡浼犻€?
module id_ex(

    input wire clk,
    input wire rst,

    input wire[`InstBus] inst_i,            // 鎸囦护鍐呭
    input wire[`InstAddrBus] inst_addr_i,   // 鎸囦护鍦板潃
    input wire reg_we_i,                    // 鍐欓€氱敤瀵勫瓨鍣ㄦ爣蹇?
    input wire[`RegAddrBus] reg_waddr_i,    // 鍐欓€氱敤瀵勫瓨鍣ㄥ湴鍧€
    input wire[`RegBus] reg1_rdata_i,       // 閫氱敤瀵勫瓨鍣?璇绘暟鎹?
    input wire[`RegBus] reg2_rdata_i,       // 閫氱敤瀵勫瓨鍣?璇绘暟鎹?    input wire[`MemAddrBus] op1_i,
    input wire[`MemAddrBus] op2_i,
    input wire[`MemAddrBus] op1_jump_i,
    input wire[`MemAddrBus] op2_jump_i,

    input wire[`Hold_Flag_Bus] hold_flag_i, // 娴佹按绾挎殏鍋滄爣蹇?

    output wire[`MemAddrBus] op1_o,
    output wire[`MemAddrBus] op2_o,
    output wire[`MemAddrBus] op1_jump_o,
    output wire[`MemAddrBus] op2_jump_o,
    output wire[`InstBus] inst_o,            // 鎸囦护鍐呭
    output wire[`InstAddrBus] inst_addr_o,   // 鎸囦护鍦板潃
    output wire reg_we_o,                    // 鍐欓€氱敤瀵勫瓨鍣ㄦ爣蹇?
    output wire[`RegAddrBus] reg_waddr_o,    // 鍐欓€氱敤瀵勫瓨鍣ㄥ湴鍧€
    output wire[`RegBus] reg1_rdata_o,       // 閫氱敤瀵勫瓨鍣?璇绘暟鎹?
    output wire[`RegBus] reg2_rdata_o,       // 閫氱敤瀵勫瓨鍣?璇绘暟鎹?
    );

    wire clear_en = (hold_flag_i == `Hold_Id_clr || hold_flag_i == `Hold_If_keep_Id_clr);
    wire hold_en = (hold_flag_i == `Hold_Id_keep);

    wire[`InstBus] inst;
    gen_pipe_dff #(32) inst_ff(clk, rst, clear_en, hold_en, `INST_NOP, inst_i, inst);
    assign inst_o = inst;

    wire[`InstAddrBus] inst_addr;
    gen_pipe_dff #(32) inst_addr_ff(clk, rst, clear_en, hold_en, `ZeroWord, inst_addr_i, inst_addr);
    assign inst_addr_o = inst_addr;

    wire reg_we;
    gen_pipe_dff #(1) reg_we_ff(clk, rst, clear_en, hold_en, `WriteDisable, reg_we_i, reg_we);
    assign reg_we_o = reg_we;

    wire[`RegAddrBus] reg_waddr;
    gen_pipe_dff #(5) reg_waddr_ff(clk, rst, clear_en, hold_en, `ZeroReg, reg_waddr_i, reg_waddr);
    assign reg_waddr_o = reg_waddr;

    wire[`RegBus] reg1_rdata;
    gen_pipe_dff #(32) reg1_rdata_ff(clk, rst, clear_en, hold_en, `ZeroWord, reg1_rdata_i, reg1_rdata);
    assign reg1_rdata_o = reg1_rdata;

    wire[`RegBus] reg2_rdata;
    gen_pipe_dff #(32) reg2_rdata_ff(clk, rst, clear_en, hold_en, `ZeroWord, reg2_rdata_i, reg2_rdata);
    assign reg2_rdata_o = reg2_rdata;    wire[`MemAddrBus] op1;
    gen_pipe_dff #(32) op1_ff(clk, rst, clear_en, hold_en, `ZeroWord, op1_i, op1);
    assign op1_o = op1;

    wire[`MemAddrBus] op2;
    gen_pipe_dff #(32) op2_ff(clk, rst, clear_en, hold_en, `ZeroWord, op2_i, op2);
    assign op2_o = op2;

    wire[`MemAddrBus] op1_jump;
    gen_pipe_dff #(32) op1_jump_ff(clk, rst, clear_en, hold_en, `ZeroWord, op1_jump_i, op1_jump);
    assign op1_jump_o = op1_jump;

    wire[`MemAddrBus] op2_jump;
    gen_pipe_dff #(32) op2_jump_ff(clk, rst, clear_en, hold_en, `ZeroWord, op2_jump_i, op2_jump);
    assign op2_jump_o = op2_jump;

endmodule


