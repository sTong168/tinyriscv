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
// slave 等 ACK 时屏蔽 jump（避免误 Hold_Id_clr）；但放行 hold_flag_ex（rT）。
// 否则 16-bit bridge 取指等 ACK 会掐断 rT stall → Temp=0xFF。
module cpu1_ctrl(

    input wire clk,
    input wire rst,

    // from cpu1_ex
    input wire jump_flag_i,
    input wire[`InstAddrBus] jump_addr_i,
    input wire hold_flag_ex_i,
    input wire ls_flag_i,

    // from cpu1_rib: {master_req_hold, slave_wait_ack}
    input wire [1:0] hold_flag_rib_i,

    output reg[`Hold_Flag_Bus] hold_flag_o,

    // to cpu1_pc_reg
    output reg jump_flag_o,
    output reg[`InstAddrBus] jump_addr_o

    );

    reg jump_flag;
    reg hold_flag_ex;
    reg ls_flag;

    always @ (*) begin
        if (hold_flag_rib_i[0] == `HoldDisable) begin
            jump_flag = jump_flag_i;
            hold_flag_ex = hold_flag_ex_i;
            if (hold_flag_rib_i[1] == `HoldEnable) begin
                ls_flag = ls_flag_i;
            end else begin
                ls_flag = `False;
            end
        end else begin
            jump_flag = `JumpDisable;
            hold_flag_ex = hold_flag_ex_i;
            ls_flag = `False;
        end
    end

    always @ (*) begin
        jump_addr_o = jump_addr_i;
        jump_flag_o = jump_flag_i;
        hold_flag_o = `Hold_None;

        if (jump_flag == `JumpEnable) begin
            hold_flag_o = `Hold_Id_clr;
        end else if (hold_flag_ex == `HoldEnable) begin
            hold_flag_o = `Hold_If_keep_Id_clr;
        end else if (ls_flag == `True) begin
            hold_flag_o = `Hold_If_keep_Id_clr;
        end else if (hold_flag_rib_i[0] == `HoldEnable) begin
            hold_flag_o = `Hold_Id_keep;
        end else if (hold_flag_rib_i[1] == `HoldEnable) begin
            hold_flag_o = `Hold_Pc;
        end else begin
            hold_flag_o = `Hold_None;
        end
    end

endmodule
