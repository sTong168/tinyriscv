 /*                                                                      
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
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

// 控制模块
// 发出跳转、暂停流水线信号
module ctrl(

    input wire clk,
    input wire rst,

    // from ex
    input wire jump_flag_i,
    input wire[`InstAddrBus] jump_addr_i,
    input wire hold_flag_ex_i,
    input wire ls_flag_i,

    // from rib
    input wire [1:0] hold_flag_rib_i,

    // from jtag
    input wire jtag_halt_flag_i,

    // from clint
    input wire hold_flag_clint_i,

    output reg[`Hold_Flag_Bus] hold_flag_o,

    // to pc_reg
    output reg jump_flag_o,
    output reg[`InstAddrBus] jump_addr_o

    );

    // reg  jump_flag_reg;
    // reg  hold_flag_ex_reg;
    // reg  hold_flag_clint_reg;
    // reg  ls_flag_reg;

    reg jump_flag;
    reg hold_flag_ex;
    reg hold_flag_clint;
    reg ls_flag;

    // 下面两段是用寄存器保存当前的输入，由于现在每个大周期指令不变输入也不变，因此不需保存
    // always @(posedge clk) begin
    //     if (rst == `RstEnable) begin
    //         jump_flag_reg <= `JumpDisable;
    //         hold_flag_ex_reg <= `HoldDisable;
    //         hold_flag_clint_reg <= `HoldDisable;
    //         ls_flag_reg <= `False;
    //     end else if (hold_flag_rib_i[0] == `HoldDisable) begin
    //         jump_flag_reg <= `JumpDisable;
    //         hold_flag_ex_reg <= `HoldDisable;
    //         hold_flag_clint_reg <= `HoldDisable;
    //         ls_flag_reg <= `False;
    //     end else begin
    //         jump_flag_reg <= (jump_flag_i == `JumpEnable) ? `JumpEnable : jump_flag_reg;
    //         hold_flag_ex_reg <= (hold_flag_ex_i == `HoldEnable) ? `HoldEnable : hold_flag_ex_reg;
    //         hold_flag_clint_reg <= (hold_flag_clint_i == `HoldEnable) ? `HoldEnable : hold_flag_clint_reg;
    //         ls_flag_reg <= (ls_flag_i == `True) ? `True : ls_flag_reg;
    //     end
    // end

    // assign jump_flag = (hold_flag_rib_i[0] == `HoldDisable) ? jump_flag_reg : `JumpDisable;
    // assign hold_flag_ex = (hold_flag_rib_i[0] == `HoldDisable) ? hold_flag_ex_reg : `HoldDisable;
    // assign hold_flag_clint = (hold_flag_rib_i[0] == `HoldDisable) ? hold_flag_clint_reg : `HoldDisable;
    // assign ls_flag = (hold_flag_rib_i[0] == `HoldDisable && hold_flag_rib_i[1] == `HoldEnable) ? ls_flag_reg : `False;

    //这段与下面那段作用完全一样，下面的逻辑更清晰
    // assign jump_flag = (hold_flag_rib_i[0] == `HoldDisable) ? jump_flag_i : `JumpDisable;
    // assign hold_flag_ex = (hold_flag_rib_i[0] == `HoldDisable) ? hold_flag_ex_i : `HoldDisable;
    // assign hold_flag_clint = (hold_flag_rib_i[0] == `HoldDisable) ? hold_flag_clint_i : `HoldDisable;
    // assign ls_flag = (hold_flag_rib_i[0] == `HoldDisable && hold_flag_rib_i[1] == `HoldEnable) ? ls_flag_i : `False;

    always @(*) begin
        if (hold_flag_rib_i[0] == `HoldDisable) begin
            jump_flag = jump_flag_i;
            hold_flag_ex = hold_flag_ex_i;
            hold_flag_clint = hold_flag_clint_i;
            if (hold_flag_rib_i[1] == `HoldEnable) begin
                ls_flag = ls_flag_i;
            end else begin
                ls_flag = `False;
            end
        end else begin
            jump_flag = `JumpDisable;
            hold_flag_ex = `HoldDisable;
            hold_flag_clint = `HoldDisable;
            ls_flag = `False;
        end
        
    end

    always @ (*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        // 默认不暂停
        hold_flag_o = `Hold_None;
        // 按优先级处理不同模块的请求
        if (jump_flag == `JumpEnable || hold_flag_clint == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id_clr;
        end else if (hold_flag_ex == `HoldEnable) begin
            hold_flag_o = `Hold_If_keep_Id_clr;
        end else if (ls_flag == `True) begin
            hold_flag_o = `Hold_If_keep_Id_clr;
        end else if (hold_flag_rib_i[0] == `HoldEnable) begin
            // 暂停PC，即取指地址不变
            // hold_flag_o = `Hold_Pc;
            hold_flag_o = `Hold_Id_keep;
        end else if (hold_flag_rib_i[1] == `HoldEnable) begin
            // 暂停PC，即取指地址不变
            hold_flag_o = `Hold_Pc;
        end else if (jtag_halt_flag_i == `HoldEnable) begin
            // 暂停整条流水线
            hold_flag_o = `Hold_Id_clr;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule
