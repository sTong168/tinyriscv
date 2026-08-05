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
module cpu2_rib(

    input wire clk,
    input wire rst,

    // master 0 interface (CPU data access)
    input wire[`MemAddrBus] m0_addr_i,
    input wire[`MemBus] m0_data_i,
    output reg[`MemBus] m0_data_o,
    input wire m0_req_i,
    input wire m0_we_i,

    // master 1 interface (CPU instruction fetch)
    input wire[`MemAddrBus] m1_addr_i,
    input wire[`MemBus] m1_data_i,
    output reg[`MemBus] m1_data_o,
    input wire m1_req_i,
    input wire m1_we_i,

    // master 3 interface (uart_debug firmware download)
    input wire[`MemAddrBus] m3_addr_i,
    input wire[`MemBus] m3_data_i,
    output reg[`MemBus] m3_data_o,
    input wire m3_req_i,
    input wire m3_we_i,

    // slave 0 interface (ROM via mem_bridge, 0x0000_0000)
    output reg[`MemAddrBus] s0_addr_o,
    output reg[`MemBus] s0_data_o,
    input wire[`MemBus] s0_data_i,
    output reg s0_we_o,

    // slave 1 interface (RAM via mem_bridge, 0x1000_0000)
    output reg[`MemAddrBus] s1_addr_o,
    output reg[`MemBus] s1_data_o,
    input wire[`MemBus] s1_data_i,
    output reg s1_we_o,

    // slave 3 interface (UART, 0x3000_0000)
    output reg[`MemAddrBus] s3_addr_o,
    output reg[`MemBus] s3_data_o,
    input wire[`MemBus] s3_data_i,
    output reg s3_we_o,

    // slave 6 interface (PWM, 0x6000_0000)
    output reg[`MemAddrBus] s6_addr_o,
    output reg[`MemBus] s6_data_o,
    input wire[`MemBus] s6_data_i,
    output reg s6_we_o,

    // slave 7 interface (I2C, 0x7000_0000)
    output reg[`MemAddrBus] s7_addr_o,
    output reg[`MemBus] s7_data_o,
    input wire[`MemBus] s7_data_i,
    output reg s7_we_o,

    output reg hold_flag_o                 // 暂停流水线标志

    );


    // 访问地址的最高4位决定要访问的是哪一个从设备
    parameter [3:0] slave_0 = 4'b0000;
    parameter [3:0] slave_1 = 4'b0001;
    parameter [3:0] slave_3 = 4'b0011;
    parameter [3:0] slave_6 = 4'b0110;
    parameter [3:0] slave_7 = 4'b0111;

    parameter [1:0] grant0 = 2'h0;
    parameter [1:0] grant1 = 2'h1;
    parameter [1:0] grant3 = 2'h3;

    wire[2:0] req;
    reg[1:0] grant;


    // 主设备请求信号 (m3, m1, m0)
    assign req = {m3_req_i, m1_req_i, m0_req_i};

    // 仲裁逻辑
    // 固定优先级: m3 > m0 > m1
    always @ (*) begin
        if (req[2]) begin
            grant = grant3;
            hold_flag_o = `HoldEnable;
        end else if (req[0]) begin
            grant = grant0;
            hold_flag_o = `HoldEnable;
        end else begin
            grant = grant1;
            hold_flag_o = `HoldDisable;
        end
    end

    // 根据仲裁结果，选择对应的从设备
    always @ (*) begin
        m0_data_o = `ZeroWord;
        m1_data_o = `INST_NOP;
        m3_data_o = `ZeroWord;

        s0_addr_o = `ZeroWord;
        s1_addr_o = `ZeroWord;
        s3_addr_o = `ZeroWord;
        s6_addr_o = `ZeroWord;
        s7_addr_o = `ZeroWord;
        s0_data_o = `ZeroWord;
        s1_data_o = `ZeroWord;
        s3_data_o = `ZeroWord;
        s6_data_o = `ZeroWord;
        s7_data_o = `ZeroWord;
        s0_we_o = `WriteDisable;
        s1_we_o = `WriteDisable;
        s3_we_o = `WriteDisable;
        s6_we_o = `WriteDisable;
        s7_we_o = `WriteDisable;

        case (grant)
            grant0: begin
                case (m0_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m0_we_i;
                        s0_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s0_data_o = m0_data_i;
                        m0_data_o = s0_data_i;
                    end
                    slave_1: begin
                        s1_we_o = m0_we_i;
                        s1_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s1_data_o = m0_data_i;
                        m0_data_o = s1_data_i;
                    end
                    slave_3: begin
                        s3_we_o = m0_we_i;
                        s3_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s3_data_o = m0_data_i;
                        m0_data_o = s3_data_i;
                    end
                    slave_6: begin
                        s6_we_o = m0_we_i;
                        s6_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s6_data_o = m0_data_i;
                        m0_data_o = s6_data_i;
                    end
                    slave_7: begin
                        s7_we_o = m0_we_i;
                        s7_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s7_data_o = m0_data_i;
                        m0_data_o = s7_data_i;
                    end
                    default: begin

                    end
                endcase
            end
            grant1: begin
                case (m1_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m1_we_i;
                        s0_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s0_data_o = m1_data_i;
                        m1_data_o = s0_data_i;
                    end
                    slave_1: begin
                        s1_we_o = m1_we_i;
                        s1_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s1_data_o = m1_data_i;
                        m1_data_o = s1_data_i;
                    end
                    slave_3: begin
                        s3_we_o = m1_we_i;
                        s3_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s3_data_o = m1_data_i;
                        m1_data_o = s3_data_i;
                    end
                    slave_6: begin
                        s6_we_o = m1_we_i;
                        s6_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s6_data_o = m1_data_i;
                        m1_data_o = s6_data_i;
                    end
                    slave_7: begin
                        s7_we_o = m1_we_i;
                        s7_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s7_data_o = m1_data_i;
                        m1_data_o = s7_data_i;
                    end
                    default: begin

                    end
                endcase
            end
            grant3: begin
                case (m3_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m3_we_i;
                        s0_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s0_data_o = m3_data_i;
                        m3_data_o = s0_data_i;
                    end
                    slave_1: begin
                        s1_we_o = m3_we_i;
                        s1_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s1_data_o = m3_data_i;
                        m3_data_o = s1_data_i;
                    end
                    slave_3: begin
                        s3_we_o = m3_we_i;
                        s3_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s3_data_o = m3_data_i;
                        m3_data_o = s3_data_i;
                    end
                    slave_6: begin
                        s6_we_o = m3_we_i;
                        s6_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s6_data_o = m3_data_i;
                        m3_data_o = s6_data_i;
                    end
                    slave_7: begin
                        s7_we_o = m3_we_i;
                        s7_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s7_data_o = m3_data_i;
                        m3_data_o = s7_data_i;
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
