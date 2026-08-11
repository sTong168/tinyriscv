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
`define UART_TX_REG             32'h3000000C
`define UART_STATUS_REG         32'h30000004
`define I2C_TX_REG              32'h70020000
`define I2C_RX_REG              32'h70030000
`define I2C_RX_DATA_REG          32'h70030008
`define I2C_STATUS_REG          32'h70050000

// 执行模块
module cpu2_ex(

    input wire clk,

    input wire rst,

    // from id_ex
    input wire[`InstBus] inst_i,            // 指令内容
    input wire[`InstAddrBus] inst_addr_i,   // 指令地址
    input wire reg_we_i,                    // 是否写通用寄存器
    input wire[`RegAddrBus] reg_waddr_i,    // 写通用寄存器地址
    input wire[`RegBus] reg1_rdata_i,       // 通用寄存器1输入数据
    input wire[`RegBus] reg2_rdata_i,       // 通用寄存器2输入数据
    input wire[`MemAddrBus] op1_i,
    input wire[`MemAddrBus] op2_i,
    input wire[`MemAddrBus] op1_jump_i,
    input wire[`MemAddrBus] op2_jump_i,

    // from mem (RIB bus read data)
    input wire[`MemBus] mem_rdata_i,        // 内存输入数据

    // to mem (RIB bus)
    output reg[`MemBus] mem_wdata_o,        // 写内存数据
    output reg[`MemAddrBus] mem_raddr_o,    // 读内存地址
    output reg[`MemAddrBus] mem_waddr_o,    // 写内存地址
    output wire mem_we_o,                   // 是否要写内存
    output wire mem_req_o,                  // 请求访问内存标志

    // to regs
    output wire[`RegBus] reg_wdata_o,       // 写寄存器数据
    output wire reg_we_o,                   // 是否要写通用寄存器
    output wire[`RegAddrBus] reg_waddr_o,   // 写通用寄存器地址

    // to ctrl
    output wire hold_flag_o,                // 是否暂停标志
    output wire ls_flag_o,                  // 是否访存标志（load/store）
    output wire jump_flag_o,                // 是否跳转标志
    output wire[`InstAddrBus] jump_addr_o   // 跳转目的地址

    );

    wire[1:0] mem_raddr_index;
    wire[1:0] mem_waddr_index;
    wire[31:0] sr_shift;
    wire[31:0] sri_shift;
    wire[31:0] sr_shift_mask;
    wire[31:0] sri_shift_mask;
    wire[31:0] op1_add_op2_res;
    wire[31:0] op1_jump_add_op2_jump_res;
    wire op1_ge_op2_signed;
    wire op1_ge_op2_unsigned;
    wire op1_eq_op2;
    wire[6:0] opcode;
    wire[2:0] funct3;
    wire[6:0] funct7;
    wire[4:0] rd;
    wire[4:0] uimm;
    reg[`RegBus] reg_wdata;
    reg reg_we;
    reg[`RegAddrBus] reg_waddr;
    reg hold_flag;
    reg jump_flag;
    reg[`InstAddrBus] jump_addr;
    reg mem_we;
    reg mem_req;

    // ========== sID指令相关寄存器 ==========
    reg[3:0] sid_byte_index;
    reg sid_busy;
    reg[7:0] sid_byte_to_send;
    reg[1:0] sid_phase;
    reg sid_byte_sent;
    reg sid_done;

    localparam SID_IDLE  = 2'b00;
    localparam SID_POLL  = 2'b01;
    localparam SID_WRITE = 2'b10;

    // rT phase definitions
    localparam RT_IDLE     = 3'd0;
    localparam RT_WR_PTR   = 3'd1;
    localparam RT_POLL_WR  = 3'd2;
    localparam RT_RD_TRIG  = 3'd3;
    localparam RT_POLL_RD  = 3'd4;
    localparam RT_RD_DATA  = 3'd5;
    localparam RT_DONE_S   = 3'd6;

    // 学号ASCII码表（2025210674）
    function [7:0] get_student_id;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  get_student_id = 8'h32; // '2'
                4'd1:  get_student_id = 8'h30; // '0'
                4'd2:  get_student_id = 8'h32; // '2'
                4'd3:  get_student_id = 8'h35; // '5'
                4'd4:  get_student_id = 8'h32; // '2'
                4'd5:  get_student_id = 8'h31; // '1'
                4'd6:  get_student_id = 8'h30; // '0'
                4'd7:  get_student_id = 8'h36; // '6'
                4'd8:  get_student_id = 8'h37; // '7'
                4'd9:  get_student_id = 8'h34; // '4'
                default: get_student_id = 8'h30;
            endcase
        end
    endfunction

    assign opcode = inst_i[6:0];
    assign funct3 = inst_i[14:12];
    assign funct7 = inst_i[31:25];
    assign rd = inst_i[11:7];
    assign uimm = inst_i[19:15];

    assign sr_shift = reg1_rdata_i >> reg2_rdata_i[4:0];
    assign sri_shift = reg1_rdata_i >> inst_i[24:20];
    assign sr_shift_mask = 32'hffffffff >> reg2_rdata_i[4:0];
    assign sri_shift_mask = 32'hffffffff >> inst_i[24:20];

    assign op1_add_op2_res = op1_i + op2_i;
    assign op1_jump_add_op2_jump_res = op1_jump_i + op2_jump_i;

    assign op1_ge_op2_signed = $signed(op1_i) >= $signed(op2_i);
    assign op1_ge_op2_unsigned = op1_i >= op2_i;
    assign op1_eq_op2 = (op1_i == op2_i);

    assign mem_raddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:20]}) & 2'b11;
    assign mem_waddr_index = (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}) & 2'b11;

    assign reg_wdata_o = reg_wdata;
    assign reg_we_o = reg_we;
    assign reg_waddr_o = reg_waddr;

    assign mem_we_o = mem_we;
    assign mem_req_o = mem_req;

    assign hold_flag_o = hold_flag;
    assign ls_flag_o = (opcode == `INST_TYPE_L) || (opcode == `INST_TYPE_S);
    assign jump_flag_o = jump_flag;
    assign jump_addr_o = jump_addr;


    // 处理 sID 指令（轮询 UART_STATUS，再写 UART_TXDATA）
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            sid_byte_index <= 4'd0;
            sid_busy <= 1'b0;
            sid_byte_to_send <= 8'h00;
            sid_phase <= SID_IDLE;
            sid_byte_sent <= 1'b0;
            sid_done <= 1'b0;
        end else if (opcode == `INST_CUSTOM && funct3 == `INST_SID && !sid_busy && !sid_done) begin
            sid_busy <= 1'b1;
            sid_byte_index <= 4'd0;
            sid_phase <= SID_POLL;
            sid_byte_sent <= 1'b0;
            sid_byte_to_send <= get_student_id(4'd0);
        end else if (sid_busy) begin
            case (sid_phase)
                SID_POLL: begin
                    sid_byte_to_send <= get_student_id(sid_byte_index);
                    if (sid_byte_sent) begin
                        if (mem_rdata_i[0] == 1'b0) begin
                            if (sid_byte_index < 4'd9) begin
                                sid_byte_index <= sid_byte_index + 1'b1;
                                sid_byte_sent <= 1'b0;
                            end else begin
                                sid_done <= 1'b1;
                                sid_busy <= 1'b0;
                                sid_phase <= SID_IDLE;
                                sid_byte_sent <= 1'b0;
                            end
                        end
                    end else begin
                        if (mem_rdata_i[0] == 1'b0) begin
                            sid_phase <= SID_WRITE;
                        end
                    end
                end
                SID_WRITE: begin
                    sid_byte_sent <= 1'b1;
                    sid_phase <= SID_POLL;
                end
                default: begin
                    sid_phase <= SID_POLL;
                end
            endcase
        end
    end

    reg rt_busy;
    reg rt_done;
    reg [7:0] rt_temperature;
    reg [2:0] rt_phase;
    reg rt_req_sent;
    reg rt_seen_busy;
    reg [`RegAddrBus] rt_rd;

    // ========== IF指令相关寄存器 ==========
    reg if_busy;
    reg if_done;
    reg[7:0] if_fire_byte;
    reg[1:0] if_phase;

    localparam IF_IDLE  = 2'b00;
    localparam IF_POLL  = 2'b01;
    localparam IF_WRITE = 2'b10;

    // LM75上电延时
    `ifdef SIMULATION
        localparam PWRON_DELAY = 25'd6000;
    `else
        localparam PWRON_DELAY = 25'd5000000;
    `endif
    reg [24:0] rt_pwron_cnt;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            rt_pwron_cnt <= 25'd0;
        end else if (rt_pwron_cnt < PWRON_DELAY) begin
            rt_pwron_cnt <= rt_pwron_cnt + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            rt_busy <= 1'b0;
            rt_done <= 1'b0;
            rt_temperature <= 8'h00;
            rt_phase <= RT_IDLE;
            rt_req_sent <= 1'b0;
            rt_seen_busy <= 1'b0;
            rt_rd <= 5'b0;
        end else if (opcode == `INST_CUSTOM && funct3 == `INST_RT && !rt_busy && !rt_done) begin
            rt_busy <= 1'b1;
            rt_done <= 1'b0;
            rt_rd <= reg_waddr_i;
            rt_req_sent <= 1'b0;
            rt_seen_busy <= 1'b0;
            rt_phase <= RT_IDLE;
        end else if (rt_busy) begin
            case (rt_phase)
                RT_IDLE: begin
                    if (rt_pwron_cnt >= PWRON_DELAY) begin
                        rt_phase <= RT_WR_PTR;
                    end
                end
                RT_WR_PTR: begin
                    rt_req_sent <= 1'b0;
                    rt_seen_busy <= 1'b0;
                    rt_phase <= RT_POLL_WR;
                end
                RT_POLL_WR: begin
                    if (rt_req_sent) begin
                        if (mem_rdata_i[6])
                            rt_seen_busy <= 1'b1;
                        if (rt_seen_busy && mem_rdata_i[7] && !mem_rdata_i[6]) begin
                            rt_phase <= RT_RD_TRIG;
                            rt_req_sent <= 1'b0;
                            rt_seen_busy <= 1'b0;
                        end else begin
                            rt_req_sent <= 1'b0;
                        end
                    end else begin
                        rt_req_sent <= 1'b1;
                    end
                end
                RT_RD_TRIG: begin
                    rt_req_sent <= 1'b0;
                    rt_seen_busy <= 1'b0;
                    rt_phase <= RT_POLL_RD;
                end
                RT_POLL_RD: begin
                    if (rt_req_sent) begin
                        if (mem_rdata_i[6])
                            rt_seen_busy <= 1'b1;
                        if (rt_seen_busy && mem_rdata_i[7] && !mem_rdata_i[6]) begin
                            rt_phase <= RT_RD_DATA;
                            rt_req_sent <= 1'b0;
                            rt_seen_busy <= 1'b0;
                        end else begin
                            rt_req_sent <= 1'b0;
                        end
                    end else begin
                        rt_req_sent <= 1'b1;
                    end
                end
                RT_RD_DATA: begin
                    if (rt_req_sent) begin
                        rt_temperature <= mem_rdata_i[7:0];
                        rt_phase <= RT_DONE_S;
                        rt_req_sent <= 1'b0;
                    end else begin
                        rt_req_sent <= 1'b1;
                    end
                end
                RT_DONE_S: begin
                    rt_busy <= 1'b0;
                    rt_done <= 1'b1;
                    rt_phase <= RT_IDLE;
                end
                default: rt_phase <= RT_IDLE;
            endcase
        end else if (rt_done) begin
            rt_done <= 1'b0;
        end
    end

    // 处理 IF 指令（轮询UART_STATUS后写UART_TXDATA发送1字节, 同sID方式）
    // 修复: 原实现单周期直写UART_TX, UART忙时写入被丢弃, 改为busy轮询
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            if_busy <= 1'b0;
            if_done <= 1'b0;
            if_fire_byte <= 8'h00;
            if_phase <= IF_IDLE;
        end else if (if_busy) begin
            case (if_phase)
                IF_POLL: begin
                    if (mem_rdata_i[0] == 1'b0) begin
                        if_phase <= IF_WRITE;
                    end
                end
                IF_WRITE: begin
                    if_busy <= 1'b0;
                    if_phase <= IF_IDLE;
                end
                default: if_phase <= IF_IDLE;
            endcase
        end else if (opcode == `INST_CUSTOM && funct3 == `INST_IF &&
                     op1_jump_i == 32'h0 &&
                     $signed(op1_i) >= $signed(reg2_rdata_i)) begin
            if_busy <= 1'b1;
            if_done <= 1'b1;
            if_fire_byte <= op1_i[7:0];
            if_phase <= IF_POLL;
        end else if (opcode == `INST_CUSTOM && funct3 == `INST_IF) begin
            if_done <= 1'b0;
        end
    end

    // 执行
    always @ (*) begin
        reg_we = reg_we_i;
        reg_waddr = reg_waddr_i;
        mem_req = `RIB_NREQ;

        case (opcode)
            `INST_TYPE_I: begin
                case (funct3)
                    `INST_ADDI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_add_op2_res;
                    end
                    `INST_SLTI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1;
                    end
                    `INST_SLTIU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1;
                    end
                    `INST_XORI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i ^ op2_i;
                    end
                    `INST_ORI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i | op2_i;
                    end
                    `INST_ANDI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i & op2_i;
                    end
                    `INST_SLLI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = reg1_rdata_i << inst_i[24:20];
                    end
                    `INST_SRI: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        if (inst_i[30] == 1'b1) begin
                            reg_wdata = (sri_shift & sri_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sri_shift_mask));
                        end else begin
                            reg_wdata = reg1_rdata_i >> inst_i[24:20];
                        end
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_R_M: begin
                case (funct3)
                    `INST_ADD_SUB: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        if (inst_i[30] == 1'b0) begin
                            reg_wdata = op1_add_op2_res;
                        end else begin
                            reg_wdata = op1_i - op2_i;
                        end
                    end
                    `INST_SLL: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i << op2_i[4:0];
                    end
                    `INST_SLT: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_signed)}} & 32'h1;
                    end
                    `INST_SLTU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = {32{(~op1_ge_op2_unsigned)}} & 32'h1;
                    end
                    `INST_XOR: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i ^ op2_i;
                    end
                    `INST_SR: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        if (inst_i[30] == 1'b1) begin
                            reg_wdata = (sr_shift & sr_shift_mask) | ({32{reg1_rdata_i[31]}} & (~sr_shift_mask));
                        end else begin
                            reg_wdata = reg1_rdata_i >> reg2_rdata_i[4:0];
                        end
                    end
                    `INST_OR: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i | op2_i;
                    end
                    `INST_AND: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = op1_i & op2_i;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_L: begin
                case (funct3)
                    `INST_LB: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: reg_wdata = {{24{mem_rdata_i[7]}}, mem_rdata_i[7:0]};
                            2'b01: reg_wdata = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
                            2'b10: reg_wdata = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
                            default: reg_wdata = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
                        endcase
                    end
                    `INST_LH: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_raddr_index == 2'b0)
                            reg_wdata = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
                        else
                            reg_wdata = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};
                    end
                    `INST_LW: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        reg_wdata = mem_rdata_i;
                    end
                    `INST_LBU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: reg_wdata = {24'h0, mem_rdata_i[7:0]};
                            2'b01: reg_wdata = {24'h0, mem_rdata_i[15:8]};
                            2'b10: reg_wdata = {24'h0, mem_rdata_i[23:16]};
                            default: reg_wdata = {24'h0, mem_rdata_i[31:24]};
                        endcase
                    end
                    `INST_LHU: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_raddr_index == 2'b0)
                            reg_wdata = {16'h0, mem_rdata_i[15:0]};
                        else
                            reg_wdata = {16'h0, mem_rdata_i[31:16]};
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_S: begin
                case (funct3)
                    `INST_SB: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_waddr_index)
                            2'b00: mem_wdata_o = {mem_rdata_i[31:8], reg2_rdata_i[7:0]};
                            2'b01: mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[7:0], mem_rdata_i[7:0]};
                            2'b10: mem_wdata_o = {mem_rdata_i[31:24], reg2_rdata_i[7:0], mem_rdata_i[15:0]};
                            default: mem_wdata_o = {reg2_rdata_i[7:0], mem_rdata_i[23:0]};
                        endcase
                    end
                    `INST_SH: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_waddr_index == 2'b00)
                            mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[15:0]};
                        else
                            mem_wdata_o = {reg2_rdata_i[15:0], mem_rdata_i[15:0]};
                    end
                    `INST_SW: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        reg_wdata = `ZeroWord;
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        mem_wdata_o = reg2_rdata_i;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_TYPE_B: begin
                case (funct3)
                    `INST_BEQ: begin
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = op1_eq_op2 & `JumpEnable;
                        jump_addr = {32{op1_eq_op2}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BNE: begin
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_eq_op2) & `JumpEnable;
                        jump_addr = {32{(~op1_eq_op2)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BLT: begin
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_ge_op2_signed) & `JumpEnable;
                        jump_addr = {32{(~op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BGE: begin
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (op1_ge_op2_signed) & `JumpEnable;
                        jump_addr = {32{(op1_ge_op2_signed)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BLTU: begin
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (~op1_ge_op2_unsigned) & `JumpEnable;
                        jump_addr = {32{(~op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res;
                    end
                    `INST_BGEU: begin
                        hold_flag = `HoldDisable;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                        jump_flag = (op1_ge_op2_unsigned) & `JumpEnable;
                        jump_addr = {32{(op1_ge_op2_unsigned)}} & op1_jump_add_op2_jump_res;
                    end
                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            `INST_JAL, `INST_JALR: begin
                hold_flag = `HoldDisable;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
                reg_wdata = op1_add_op2_res;
            end
            `INST_LUI, `INST_AUIPC: begin
                hold_flag = `HoldDisable;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                jump_addr = `ZeroWord;
                jump_flag = `JumpDisable;
                reg_wdata = op1_add_op2_res;
            end
            `INST_NOP_OP: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
            end
            `INST_CUSTOM: begin
                case (funct3)
                    `INST_SID: begin
                        jump_flag = `JumpDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_NREQ;
                        reg_wdata = `ZeroWord;
                        reg_we = `WriteDisable;
                        hold_flag = `HoldEnable;
                    end

                    `INST_RT: begin
                        jump_flag = `JumpEnable;
                        hold_flag = `HoldEnable;
                        jump_addr = op1_jump_add_op2_jump_res;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        mem_req = `RIB_NREQ;
                        reg_wdata = `ZeroWord;
                        reg_we = `WriteDisable;
                    end

                    `INST_IF: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        if (op1_jump_i == 32'h0) begin
                            if ($signed(op1_i) >= $signed(reg2_rdata_i)) begin
                                // fire: 发送由if状态机完成(先轮询UART busy再写)
                                if (if_busy) begin
                                    hold_flag = `HoldEnable;
                                end
                                reg_wdata = `ZeroWord;
                            end else begin
                                reg_wdata = op1_i;
                            end
                        end else begin
                            reg_wdata = op1_i + op2_i;
                        end
                    end

                    default: begin
                        jump_flag = `JumpDisable;
                        hold_flag = `HoldDisable;
                        jump_addr = `ZeroWord;
                        mem_wdata_o = `ZeroWord;
                        mem_raddr_o = `ZeroWord;
                        mem_waddr_o = `ZeroWord;
                        mem_we = `WriteDisable;
                        reg_wdata = `ZeroWord;
                    end
                endcase
            end
            default: begin
                jump_flag = `JumpDisable;
                hold_flag = `HoldDisable;
                jump_addr = `ZeroWord;
                mem_wdata_o = `ZeroWord;
                mem_raddr_o = `ZeroWord;
                mem_waddr_o = `ZeroWord;
                mem_we = `WriteDisable;
                reg_wdata = `ZeroWord;
            end
        endcase

        // sID multi-cycle override
        if (sid_busy && !sid_done) begin
            hold_flag = `HoldEnable;
            reg_we = `WriteDisable;
            reg_wdata = `ZeroWord;
            jump_flag = `JumpDisable;
            jump_addr = `ZeroWord;

            case (sid_phase)
                SID_POLL: begin
                    mem_req = `RIB_REQ;
                    mem_raddr_o = `UART_STATUS_REG;
                    mem_we = `WriteDisable;
                    mem_wdata_o = `ZeroWord;
                    mem_waddr_o = `ZeroWord;
                end
                SID_WRITE: begin
                    mem_req = `RIB_REQ;
                    mem_we = `WriteEnable;
                    mem_waddr_o = `UART_TX_REG;
                    mem_wdata_o = {24'h0, sid_byte_to_send};
                    mem_raddr_o = `ZeroWord;
                end
                default: begin
                    mem_req = `RIB_NREQ;
                    mem_we = `WriteDisable;
                    mem_wdata_o = `ZeroWord;
                    mem_raddr_o = `ZeroWord;
                    mem_waddr_o = `ZeroWord;
                end
            endcase
        end

        // rT multi-cycle override
        if (rt_busy || rt_done) begin
            hold_flag = `HoldEnable;
            reg_we = `WriteDisable;
            reg_wdata = `ZeroWord;
            jump_flag = `JumpDisable;
            jump_addr = `ZeroWord;
            mem_req = `RIB_NREQ;
            mem_we = `WriteDisable;
            mem_wdata_o = `ZeroWord;
            mem_raddr_o = `ZeroWord;
            mem_waddr_o = `ZeroWord;

            if (rt_done) begin
                hold_flag = `HoldDisable;
                reg_we = `WriteEnable;
                reg_wdata = {{24{rt_temperature[7]}}, rt_temperature};
                reg_waddr = rt_rd;
            end else begin
                case (rt_phase)
                    RT_WR_PTR: begin
                        mem_req = `RIB_REQ;
                        mem_we = `WriteEnable;
                        mem_waddr_o = `I2C_TX_REG;
                        mem_wdata_o = 32'h0000_0000;
                    end
                    RT_POLL_WR: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = `I2C_STATUS_REG;
                    end
                    RT_RD_TRIG: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = `I2C_RX_REG;
                    end
                    RT_POLL_RD: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = `I2C_STATUS_REG;
                    end
                    RT_RD_DATA: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = `I2C_RX_DATA_REG;
                    end
                    default: ;
                endcase
            end
        end

        // IF 指令多周期override: 轮询UART_STATUS -> 写UART_TXDATA
        if (if_busy) begin
            hold_flag = `HoldEnable;
            reg_we = `WriteDisable;
            reg_wdata = `ZeroWord;
            jump_flag = `JumpDisable;
            jump_addr = `ZeroWord;
            mem_req = `RIB_NREQ;
            mem_we = `WriteDisable;
            mem_wdata_o = `ZeroWord;
            mem_waddr_o = `ZeroWord;
            case (if_phase)
                IF_POLL: begin
                    mem_req = `RIB_REQ;
                    mem_raddr_o = `UART_STATUS_REG;
                end
                IF_WRITE: begin
                    mem_req = `RIB_REQ;
                    mem_we = `WriteEnable;
                    mem_waddr_o = `UART_TX_REG;
                    mem_wdata_o = {24'h0, if_fire_byte};
                    mem_raddr_o = `ZeroWord;
                end
                default: begin
                    mem_raddr_o = `ZeroWord;
                end
            endcase
        end
    end

endmodule
