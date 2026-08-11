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

// tinyriscv处理器核顶层模块
module cpu2_tinyriscv(

    input wire clk,
    input wire rst,

    output wire[`MemAddrBus] rib_ex_addr_o,    // 读、写外设的地址
    input wire[`MemBus] rib_ex_data_i,         // 从外设读取的数据
    output wire[`MemBus] rib_ex_data_o,        // 写入外设的数据
    output wire rib_ex_req_o,                  // 访问外设请求
    output wire rib_ex_we_o,                   // 写外设标志

    output wire[`MemAddrBus] rib_pc_addr_o,    // 取指地址
    input wire[`MemBus] rib_pc_data_i,         // 取到的指令内容

    input wire [1:0] rib_hold_flag_i,          // {master 仲裁等待, slave 外部事务等待}

    // shared regs interface
    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input wire[`RegBus]     reg_rdata1_i,
    input wire[`RegBus]     reg_rdata2_i

    );

    // pc_reg模块输出信号
    wire[`InstAddrBus] pc_pc_o;

    // if_id模块输出信号
    wire[`InstBus] if_inst_o;
    wire[`InstAddrBus] if_inst_addr_o;

    // id模块输出信号
    wire[`RegAddrBus] id_reg1_raddr_o;
    wire[`RegAddrBus] id_reg2_raddr_o;
    wire[`InstBus] id_inst_o;
    wire[`InstAddrBus] id_inst_addr_o;
    wire[`RegBus] id_reg1_rdata_o;
    wire[`RegBus] id_reg2_rdata_o;
    wire id_reg_we_o;
    wire[`RegAddrBus] id_reg_waddr_o;
    wire[`MemAddrBus] id_op1_o;
    wire[`MemAddrBus] id_op2_o;
    wire[`MemAddrBus] id_op1_jump_o;
    wire[`MemAddrBus] id_op2_jump_o;

    // id_ex模块输出信号
    wire[`InstBus] ie_inst_o;
    wire[`InstAddrBus] ie_inst_addr_o;
    wire ie_reg_we_o;
    wire[`RegAddrBus] ie_reg_waddr_o;
    wire[`RegBus] ie_reg1_rdata_o;
    wire[`RegBus] ie_reg2_rdata_o;
    wire[`MemAddrBus] ie_op1_o;
    wire[`MemAddrBus] ie_op2_o;
    wire[`MemAddrBus] ie_op1_jump_o;
    wire[`MemAddrBus] ie_op2_jump_o;

    // ex模块输出信号
    wire[`MemBus] ex_mem_wdata_o;
    wire[`MemAddrBus] ex_mem_raddr_o;
    wire[`MemAddrBus] ex_mem_waddr_o;
    wire ex_mem_we_o;
    wire ex_mem_req_o;
    wire[`RegBus] ex_reg_wdata_o;
    wire ex_reg_we_o;
    wire[`RegAddrBus] ex_reg_waddr_o;
    wire ex_hold_flag_o;
    wire ex_ls_flag_o;
    wire ex_jump_flag_o;
    wire[`InstAddrBus] ex_jump_addr_o;

    // ctrl模块输出信号
    wire[`Hold_Flag_Bus] ctrl_hold_flag_o;
    wire ctrl_jump_flag_o;
    wire[`InstAddrBus] ctrl_jump_addr_o;


    assign rib_ex_addr_o = (ex_mem_we_o == `WriteEnable)? ex_mem_waddr_o: ex_mem_raddr_o;
    assign rib_ex_data_o = ex_mem_wdata_o;
    assign rib_ex_req_o = ex_mem_req_o;
    assign rib_ex_we_o = ex_mem_we_o;

    // shared regs interface
    assign reg_we_o = ex_reg_we_o;
    assign reg_waddr_o = ex_reg_waddr_o;
    assign reg_wdata_o = ex_reg_wdata_o;
    assign reg_raddr1_o = id_reg1_raddr_o;
    assign reg_raddr2_o = id_reg2_raddr_o;

    assign rib_pc_addr_o = pc_pc_o;


    // pc_reg模块例化
    cpu2_pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .pc_o(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .jump_flag_i(ctrl_jump_flag_o),
        .jump_addr_i(ctrl_jump_addr_o)
    );

    // ctrl模块例化
    cpu2_ctrl u_ctrl(
        .rst(rst),
        .jump_flag_i(ex_jump_flag_o),
        .jump_addr_i(ex_jump_addr_o),
        .hold_flag_ex_i(ex_hold_flag_o),
        .ls_flag_i(ex_ls_flag_o),
        .hold_flag_rib_i(rib_hold_flag_i),
        .hold_flag_o(ctrl_hold_flag_o),
        .jump_flag_o(ctrl_jump_flag_o),
        .jump_addr_o(ctrl_jump_addr_o)
    );

    // if_id模块例化
    cpu2_if_id u_if_id(
        .clk(clk),
        .rst(rst),
        .inst_i(rib_pc_data_i),
        .inst_addr_i(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_o(if_inst_o),
        .inst_addr_o(if_inst_addr_o)
    );

    // id模块例化
    cpu2_id u_id(
        .rst(rst),
        .inst_i(if_inst_o),
        .inst_addr_i(if_inst_addr_o),
        .reg1_rdata_i(reg_rdata1_i),
        .reg2_rdata_i(reg_rdata2_i),
        .ex_jump_flag_i(ex_jump_flag_o),
        .reg1_raddr_o(id_reg1_raddr_o),
        .reg2_raddr_o(id_reg2_raddr_o),
        .inst_o(id_inst_o),
        .inst_addr_o(id_inst_addr_o),
        .reg1_rdata_o(id_reg1_rdata_o),
        .reg2_rdata_o(id_reg2_rdata_o),
        .reg_we_o(id_reg_we_o),
        .reg_waddr_o(id_reg_waddr_o),
        .op1_o(id_op1_o),
        .op2_o(id_op2_o),
        .op1_jump_o(id_op1_jump_o),
        .op2_jump_o(id_op2_jump_o)
    );

    // id_ex模块例化
    cpu2_id_ex u_id_ex(
        .clk(clk),
        .rst(rst),
        .inst_i(id_inst_o),
        .inst_addr_i(id_inst_addr_o),
        .reg_we_i(id_reg_we_o),
        .reg_waddr_i(id_reg_waddr_o),
        .reg1_rdata_i(id_reg1_rdata_o),
        .reg2_rdata_i(id_reg2_rdata_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_o(ie_inst_o),
        .inst_addr_o(ie_inst_addr_o),
        .reg_we_o(ie_reg_we_o),
        .reg_waddr_o(ie_reg_waddr_o),
        .reg1_rdata_o(ie_reg1_rdata_o),
        .reg2_rdata_o(ie_reg2_rdata_o),
        .op1_i(id_op1_o),
        .op2_i(id_op2_o),
        .op1_jump_i(id_op1_jump_o),
        .op2_jump_i(id_op2_jump_o),
        .op1_o(ie_op1_o),
        .op2_o(ie_op2_o),
        .op1_jump_o(ie_op1_jump_o),
        .op2_jump_o(ie_op2_jump_o)
    );

    // ex模块例化
    cpu2_ex u_ex(
        .clk(clk),
        .rst(rst),
        .inst_i(ie_inst_o),
        .inst_addr_i(ie_inst_addr_o),
        .reg_we_i(ie_reg_we_o),
        .reg_waddr_i(ie_reg_waddr_o),
        .reg1_rdata_i(ie_reg1_rdata_o),
        .reg2_rdata_i(ie_reg2_rdata_o),
        .op1_i(ie_op1_o),
        .op2_i(ie_op2_o),
        .op1_jump_i(ie_op1_jump_o),
        .op2_jump_i(ie_op2_jump_o),
        .mem_rdata_i(rib_ex_data_i),
        .mem_wdata_o(ex_mem_wdata_o),
        .mem_raddr_o(ex_mem_raddr_o),
        .mem_waddr_o(ex_mem_waddr_o),
        .mem_we_o(ex_mem_we_o),
        .mem_req_o(ex_mem_req_o),
        .reg_wdata_o(ex_reg_wdata_o),
        .reg_we_o(ex_reg_we_o),
        .reg_waddr_o(ex_reg_waddr_o),
        .hold_flag_o(ex_hold_flag_o),
        .ls_flag_o(ex_ls_flag_o),
        .jump_flag_o(ex_jump_flag_o),
        .jump_addr_o(ex_jump_addr_o)
    );

endmodule
