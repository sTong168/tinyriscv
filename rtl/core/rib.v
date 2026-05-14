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


// RIB总线模块
module rib(

    input wire clk,
    input wire rst,

    // master 0 interface
    input wire[`MemAddrBus] m0_addr_i,     // 主设备0读、写地址
    input wire[`MemBus] m0_data_i,         // 主设备0写数据
    output reg[`MemBus] m0_data_o,         // 主设备0读取到的数据
    input wire m0_req_i,                   // 主设备0访问请求标志
    input wire m0_we_i,                    // 主设备0写标志

    // master 1 interface
    input wire[`MemAddrBus] m1_addr_i,     // 主设备1读、写地址
    input wire[`MemBus] m1_data_i,         // 主设备1写数据
    output reg[`MemBus] m1_data_o,         // 主设备1读取到的数据
    input wire m1_req_i,                   // 主设备1访问请求标志
    input wire m1_we_i,                    // 主设备1写标志

    // master 2 interface
    input wire[`MemAddrBus] m2_addr_i,     // 主设备2读、写地址
    input wire[`MemBus] m2_data_i,         // 主设备2写数据
    output reg[`MemBus] m2_data_o,         // 主设备2读取到的数据
    input wire m2_req_i,                   // 主设备2访问请求标志
    input wire m2_we_i,                    // 主设备2写标志

    // master 3 interface
    input wire[`MemAddrBus] m3_addr_i,     // 主设备3读、写地址
    input wire[`MemBus] m3_data_i,         // 主设备3写数据
    output reg[`MemBus] m3_data_o,         // 主设备3读取到的数据
    input wire m3_req_i,                   // 主设备3访问请求标志
    input wire m3_we_i,                    // 主设备3写标志

    // slave 0 interface
    output reg[`MemAddrBus] s0_addr_o,     // 从设备0读、写地址
    output reg[`MemBus] s0_data_o,         // 从设备0写数据
    input wire[`MemBus] s0_data_i,         // 从设备0读取到的数据
    output reg s0_we_o,                    // 从设备0写标志
    output reg s0_req_o,                   // 从设备0开始信号
    input wire s0_ack_i,                   // 从设备0准备信号

    // slave 1 interface
    output reg[`MemAddrBus] s1_addr_o,     // 从设备1读、写地址
    output reg[`MemBus] s1_data_o,         // 从设备1写数据
    input wire[`MemBus] s1_data_i,         // 从设备1读取到的数据
    output reg s1_we_o,                    // 从设备1写标志
    output reg s1_req_o,                   // 从设备1开始信号
    input wire s1_ack_i,                   // 从设备1准备信号

    // slave 2 interface
    output reg[`MemAddrBus] s2_addr_o,     // 从设备2读、写地址
    output reg[`MemBus] s2_data_o,         // 从设备2写数据
    input wire[`MemBus] s2_data_i,         // 从设备2读取到的数据
    output reg s2_we_o,                    // 从设备2写标志
    output reg s2_req_o,                   // 从设备2开始信号
    input wire s2_ack_i,                   // 从设备2准备信号

    // slave 3 interface
    output reg[`MemAddrBus] s3_addr_o,     // 从设备3读、写地址
    output reg[`MemBus] s3_data_o,         // 从设备3写数据
    input wire[`MemBus] s3_data_i,         // 从设备3读取到的数据
    output reg s3_we_o,                    // 从设备3写标志
    output reg s3_req_o,                   // 从设备3开始信号
    input wire s3_ack_i,                   // 从设备3准备信号

    // slave 4 interface
    output reg[`MemAddrBus] s4_addr_o,     // 从设备4读、写地址
    output reg[`MemBus] s4_data_o,         // 从设备4写数据
    input wire[`MemBus] s4_data_i,         // 从设备4读取到的数据
    output reg s4_we_o,                    // 从设备4写标志
    output reg s4_req_o,                   // 从设备4开始信号
    input wire s4_ack_i,                   // 从设备4准备信号

    // slave 5 interface
    output reg[`MemAddrBus] s5_addr_o,     // 从设备5读、写地址
    output reg[`MemBus] s5_data_o,         // 从设备5写数据
    input wire[`MemBus] s5_data_i,         // 从设备5读取到的数据
    output reg s5_we_o,                    // 从设备5写标志
    output reg s5_req_o,                   // 从设备5开始信号
    input wire s5_ack_i,                   // 从设备5准备信号

    // slave 6 interface
    output reg[`MemAddrBus] s6_addr_o,     // 从设备6读、写地址
    output reg[`MemBus] s6_data_o,         // 从设备6写数据
    input wire[`MemBus] s6_data_i,         // 从设备6读取到的数据
    output reg s6_we_o,                    // 从设备6写标志
    output reg s6_req_o,                   // 从设备6开始信号
    input wire s6_ack_i,                   // 从设备6准备信号

    output wire [1:0] hold_flag_o                 // 暂停流水线标志

    );


    // 访问地址的最高4位决定要访问的是哪一个从设备
    // 因此最多支持16个从设备
    parameter [3:0]slave_0 = 4'b000x;
    // parameter [3:0]slave_1 = 4'b0001;
    parameter [3:0]slave_2 = 4'b0111;
    parameter [3:0]slave_3 = 4'b0011;
    parameter [3:0]slave_4 = 4'b0100;
    parameter [3:0]slave_5 = 4'b0101;
    parameter [3:0]slave_6 = 4'b0110;

    parameter [1:0]grant0 = 2'h0;
    parameter [1:0]grant1 = 2'h1;
    parameter [1:0]grant2 = 2'h2;
    parameter [1:0]grant3 = 2'h3;

    wire[3:0] req;
    reg[1:0] grant;

    reg hold_flag_m; // 主设备占用总线标志
    reg hold_flag_s; // 从设备占用总线标志

    // reg [1:0] cnt;

    // always @(posedge clk) begin
    //     if (rst == `RstEnable) begin
    //         cnt <= 2'd0;
    //     end else if (hold_flag_m == `HoldEnable && cnt == 2'b0) begin
    //         cnt <= 2'd3;
    //     end else if (hold_flag_m == `HoldEnable) begin
    //         cnt <= cnt - 2'd1;
    //     end else begin
    //         cnt <= cnt;
    //     end
    // end

    assign hold_flag_o = {hold_flag_m, hold_flag_s};

    // 主设备请求信号
    assign req = {m3_req_i, m2_req_i, m1_req_i, m0_req_i};

    // 仲裁逻辑
    // 固定优先级仲裁机制
    // 优先级由高到低：主设备3，主设备0，主设备2，主设备1
    always @ (*) begin
        if (req[3]) begin
            grant = grant3;
            hold_flag_m = `HoldEnable;
        end else if (req[0]) begin
            grant = grant0;
            hold_flag_m = `HoldEnable;
        end else if (req[2]) begin
            grant = grant2;
            hold_flag_m = `HoldEnable;
        end else begin
            grant = grant1;
            hold_flag_m = `HoldDisable;
        end
    end

    // 根据仲裁结果，选择(访问)对应的从设备
    always @ (*) begin
        m0_data_o = `ZeroWord;
        m1_data_o = `INST_NOP;
        m2_data_o = `ZeroWord;
        m3_data_o = `ZeroWord;

        s0_addr_o = `ZeroWord;
        s1_addr_o = `ZeroWord;
        s2_addr_o = `ZeroWord;
        s3_addr_o = `ZeroWord;
        s4_addr_o = `ZeroWord;
        s5_addr_o = `ZeroWord;
        s0_data_o = `ZeroWord;
        s1_data_o = `ZeroWord;
        s2_data_o = `ZeroWord;
        s3_data_o = `ZeroWord;
        s4_data_o = `ZeroWord;
        s5_data_o = `ZeroWord;
        s0_we_o = `WriteDisable;
        s1_we_o = `WriteDisable;
        s2_we_o = `WriteDisable;
        s3_we_o = `WriteDisable;
        s4_we_o = `WriteDisable;
        s5_we_o = `WriteDisable;
        s0_req_o  = `RIB_NREQ;
        s1_req_o  = `RIB_NREQ;
        s2_req_o  = `RIB_NREQ;
        s3_req_o  = `RIB_NREQ;
        s4_req_o  = `RIB_NREQ;
        s5_req_o  = `RIB_NREQ;

        hold_flag_s = `HoldDisable;

        case (grant)
            grant0: begin
                casex (m0_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m0_we_i;
                        s0_addr_o = m0_addr_i;
                        s0_data_o = m0_data_i;
                        m0_data_o = s0_data_i;
                        s0_req_o  = m0_req_i;
                        hold_flag_s = (s0_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    // slave_1: begin
                    //     s1_we_o = m0_we_i;
                    //     s1_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                    //     s1_data_o = m0_data_i;
                    //     m0_data_o = s1_data_i;
                    //     s1_req_o  = m0_req_i;
                    //     m0_ack_o  = s1_ack_i;
                    // end
                    slave_2: begin
                        s2_we_o = m0_we_i;
                        s2_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s2_data_o = m0_data_i;
                        m0_data_o = s2_data_i;
                        s2_req_o  = m0_req_i;
                        hold_flag_s = (s2_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_3: begin
                        s3_we_o = m0_we_i;
                        s3_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s3_data_o = m0_data_i;
                        m0_data_o = s3_data_i;
                        s3_req_o  = m0_req_i;
                        hold_flag_s = (s3_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_4: begin
                        s4_we_o = m0_we_i;
                        s4_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s4_data_o = m0_data_i;
                        m0_data_o = s4_data_i;
                        s4_req_o  = m0_req_i;
                        hold_flag_s = (s4_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_5: begin
                        s5_we_o = m0_we_i;
                        s5_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s5_data_o = m0_data_i;
                        m0_data_o = s5_data_i;
                        s5_req_o  = m0_req_i;
                        hold_flag_s = (s5_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_6: begin
                        s6_we_o = m0_we_i;
                        s6_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s6_data_o = m0_data_i;
                        m0_data_o = s6_data_i;
                        s6_req_o  = m0_req_i;
                        hold_flag_s = (s6_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    default: begin

                    end
                endcase
            end
            grant1: begin
                casex (m1_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m1_we_i;
                        s0_addr_o = m1_addr_i;
                        s0_data_o = m1_data_i;
                        m1_data_o = s0_data_i;
                        s0_req_o  = m1_req_i;
                        hold_flag_s = (s0_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    // slave_1: begin
                    //     s1_we_o = m1_we_i;
                    //     s1_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                    //     s1_data_o = m1_data_i;
                    //     m1_data_o = s1_data_i;
                    //     s1_req_o  = m1_req_i;
                    //     m1_ack_o  = s1_ack_i;
                    // end
                    slave_2: begin
                        s2_we_o = m1_we_i;
                        s2_addr_o = m1_addr_i;
                        s2_data_o = m1_data_i;
                        m1_data_o = s2_data_i;
                        s2_req_o  = m1_req_i;
                        hold_flag_s = (s2_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_3: begin
                        s3_we_o = m1_we_i;
                        s3_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s3_data_o = m1_data_i;
                        m1_data_o = s3_data_i;
                        s3_req_o  = m1_req_i;
                        hold_flag_s = (s3_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_4: begin
                        s4_we_o = m1_we_i;
                        s4_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s4_data_o = m1_data_i;
                        m1_data_o = s4_data_i;
                        s4_req_o  = m1_req_i;
                        hold_flag_s = (s4_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_5: begin
                        s5_we_o = m1_we_i;
                        s5_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s5_data_o = m1_data_i;
                        m1_data_o = s5_data_i;
                        s5_req_o  = m1_req_i;
                        hold_flag_s = (s5_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_6: begin
                        s6_we_o = m1_we_i;
                        s6_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s6_data_o = m1_data_i;
                        m1_data_o = s6_data_i;
                        s6_req_o  = m1_req_i;
                        hold_flag_s = (s6_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    default: begin

                    end
                endcase
            end
            grant2: begin
                casex (m2_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m2_we_i;
                        s0_addr_o = m2_addr_i;
                        s0_data_o = m2_data_i;
                        m2_data_o = s0_data_i;
                        s0_req_o  = m2_req_i;
                        hold_flag_s = (s0_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    // slave_1: begin
                    //     s1_we_o = m2_we_i;
                    //     s1_addr_o = {{4'h0}, {m2_addr_i[27:0]}};
                    //     s1_data_o = m2_data_i;
                    //     m2_data_o = s1_data_i;
                    //     s1_req_o  = m2_req_i;
                    //     m2_ack_o  = s1_ack_i;
                    // end
                    slave_2: begin
                        s2_we_o = m2_we_i;
                        s2_addr_o = {{4'h0}, {m2_addr_i[27:0]}};
                        s2_data_o = m2_data_i;
                        m2_data_o = s2_data_i;
                        s2_req_o  = m2_req_i;
                        hold_flag_s = (s2_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_3: begin
                        s3_we_o = m2_we_i;
                        s3_addr_o = {{4'h0}, {m2_addr_i[27:0]}};
                        s3_data_o = m2_data_i;
                        m2_data_o = s3_data_i;
                        s3_req_o  = m2_req_i;
                        hold_flag_s = (s3_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_4: begin
                        s4_we_o = m2_we_i;
                        s4_addr_o = {{4'h0}, {m2_addr_i[27:0]}};
                        s4_data_o = m2_data_i;
                        m2_data_o = s4_data_i;
                        s4_req_o  = m2_req_i;
                        hold_flag_s = (s4_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_5: begin
                        s5_we_o = m2_we_i;
                        s5_addr_o = {{4'h0}, {m2_addr_i[27:0]}};
                        s5_data_o = m2_data_i;
                        m2_data_o = s5_data_i;
                        s5_req_o  = m2_req_i;
                        hold_flag_s = (s5_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_6: begin
                        s6_we_o = m2_we_i;
                        s6_addr_o = {{4'h0}, {m2_addr_i[27:0]}};
                        s6_data_o = m2_data_i;
                        m2_data_o = s6_data_i;
                        s6_req_o  = m2_req_i;
                        hold_flag_s = (s6_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    default: begin

                    end
                endcase
            end
            grant3: begin
                casex (m3_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m3_we_i;
                        s0_addr_o = m3_addr_i;
                        s0_data_o = m3_data_i;
                        m3_data_o = s0_data_i;
                        s0_req_o  = m3_req_i;
                        hold_flag_s = (s0_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    // slave_1: begin
                    //     s1_we_o = m3_we_i;
                    //     s1_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                    //     s1_data_o = m3_data_i;
                    //     m3_data_o = s1_data_i;
                    //     s1_req_o  = m3_req_i;
                    //     m3_ack_o  = s1_ack_i;
                    // end
                    slave_2: begin
                        s2_we_o = m3_we_i;
                        s2_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s2_data_o = m3_data_i;
                        m3_data_o = s2_data_i;
                        s2_req_o  = m3_req_i;
                        hold_flag_s = (s2_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_3: begin
                        s3_we_o = m3_we_i;
                        s3_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s3_data_o = m3_data_i;
                        m3_data_o = s3_data_i;
                        s3_req_o  = m3_req_i;
                        hold_flag_s = (s3_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_4: begin
                        s4_we_o = m3_we_i;
                        s4_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s4_data_o = m3_data_i;
                        m3_data_o = s4_data_i;
                        s4_req_o  = m3_req_i;
                        hold_flag_s = (s4_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_5: begin
                        s5_we_o = m3_we_i;
                        s5_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s5_data_o = m3_data_i;
                        m3_data_o = s5_data_i;
                        s5_req_o  = m3_req_i;
                        hold_flag_s = (s5_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_6: begin
                        s6_we_o = m3_we_i;
                        s6_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s6_data_o = m3_data_i;
                        m3_data_o = s6_data_i;
                        s6_req_o  = m3_req_i;
                        hold_flag_s = (s6_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    default: begin

                    end
                endcase
            end
            default: begin

            end
        endcase
    end

endmodule
