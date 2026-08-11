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

`include "../../shared/defines.v"

// 控制模块
// 发出跳转、暂停流水线信号
module cpu2_ctrl(

    input wire rst,

    // from ex
    input wire jump_flag_i,
    input wire[`InstAddrBus] jump_addr_i,
    input wire hold_flag_ex_i,
    input wire ls_flag_i,                   // load/store 访存标志

    // from rib: {master 仲裁等待, slave 外部存储事务等待}
    input wire [1:0] hold_flag_rib_i,

    output reg[`Hold_Flag_Bus] hold_flag_o,

    // to pc_reg
    output reg jump_flag_o,
    output reg[`InstAddrBus] jump_addr_o

    );

    reg jump_flag;
    reg hold_flag_ex;
    reg ls_flag;

    // slave 等待（外部存储事务进行中）时屏蔽跳转和 ex 暂停，
    // 保证事务不被流水线状态变化打断（cpu0 同款逻辑）
    always @ (*) begin
        if (hold_flag_rib_i[0] == `HoldDisable) begin
            jump_flag = jump_flag_i;
            hold_flag_ex = hold_flag_ex_i;
            if (hold_flag_rib_i[1] == `HoldEnable) begin
                ls_flag = ls_flag_i;
            end else begin
                ls_flag = `LSDisable;
            end
        end else begin
            jump_flag = `JumpDisable;
            hold_flag_ex = `HoldDisable;
            ls_flag = `LSDisable;
        end
    end

    always @ (*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        // 默认不暂停
        hold_flag_o = `Hold_None;
        // 按优先级处理不同模块的请求
        if (jump_flag == `JumpEnable) begin
            // 跳转：清空整条流水线
            hold_flag_o = `Hold_Id_clr;
        end else if (hold_flag_ex == `HoldEnable || ls_flag == `LSEnable) begin
            // ex 多周期等待 / load/store 气泡注入：IF 保持、ID/EX 清空
            hold_flag_o = `Hold_If_keep_Id_clr;
        end else if (hold_flag_rib_i[0] == `HoldEnable) begin
            // 外部存储事务未完成：冻结整条流水线（保持）
            hold_flag_o = `Hold_Id_keep;
        end else if (hold_flag_rib_i[1] == `HoldEnable) begin
            // 仲裁等待：暂停PC，即取指地址不变
            hold_flag_o = `Hold_Pc;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule
