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


// RIB总线模块 (增加 slave_6=PWM, slave_7=I2C)
module cpu1_rib(

    input wire clk,
    input wire rst,

    // master 0 interface
    input wire[`MemAddrBus] m0_addr_i,
    input wire[`MemBus] m0_data_i,
    output reg[`MemBus] m0_data_o,
    input wire m0_req_i,
    input wire m0_we_i,

    // master 1 interface
    input wire[`MemAddrBus] m1_addr_i,
    input wire[`MemBus] m1_data_i,
    output reg[`MemBus] m1_data_o,
    input wire m1_req_i,
    input wire m1_we_i,

    // master 2 interface
    input wire[`MemAddrBus] m2_addr_i,
    input wire[`MemBus] m2_data_i,
    output reg[`MemBus] m2_data_o,
    input wire m2_req_i,
    input wire m2_we_i,

    // master 3 interface
    input wire[`MemAddrBus] m3_addr_i,
    input wire[`MemBus] m3_data_i,
    output reg[`MemBus] m3_data_o,
    input wire m3_req_i,
    input wire m3_we_i,

    // slave 0 interface (ROM  0x0000_0000)
    output reg[`MemAddrBus] s0_addr_o,
    output reg[`MemBus] s0_data_o,
    input wire[`MemBus] s0_data_i,
    output reg s0_we_o,

    // slave 1 interface (RAM  0x1000_0000)
    output reg[`MemAddrBus] s1_addr_o,
    output reg[`MemBus] s1_data_o,
    input wire[`MemBus] s1_data_i,
    output reg s1_we_o,

    // slave 2 interface (0x2000_0000 - unused, was Timer)
    output reg[`MemAddrBus] s2_addr_o,
    output reg[`MemBus] s2_data_o,
    input wire[`MemBus] s2_data_i,
    output reg s2_we_o,

    // slave 3 interface (UART 0x3000_0000)
    output reg[`MemAddrBus] s3_addr_o,
    output reg[`MemBus] s3_data_o,
    input wire[`MemBus] s3_data_i,
    output reg s3_we_o,

    // slave 4 interface (GPIO 0x4000_0000)
    output reg[`MemAddrBus] s4_addr_o,
    output reg[`MemBus] s4_data_o,
    input wire[`MemBus] s4_data_i,
    output reg s4_we_o,

    // slave 5 interface (0x5000_0000 - unused, was SPI)
    output reg[`MemAddrBus] s5_addr_o,
    output reg[`MemBus] s5_data_o,
    input wire[`MemBus] s5_data_i,
    output reg s5_we_o,

    // slave 6 interface (PWM  0x6000_0000)
    output reg[`MemAddrBus] s6_addr_o,
    output reg[`MemBus] s6_data_o,
    input wire[`MemBus] s6_data_i,
    output reg s6_we_o,

    // slave 7 interface (I2C  0x7000_0000)
    output reg[`MemAddrBus] s7_addr_o,
    output reg[`MemBus] s7_data_o,
    input wire[`MemBus] s7_data_i,
    output reg s7_we_o,

    output reg hold_flag_o

    );


    parameter [3:0]slave_0 = 4'b0000;
    parameter [3:0]slave_1 = 4'b0001;
    parameter [3:0]slave_2 = 4'b0010;
    parameter [3:0]slave_3 = 4'b0011;
    parameter [3:0]slave_4 = 4'b0100;
    parameter [3:0]slave_5 = 4'b0101;
    parameter [3:0]slave_6 = 4'b0110;
    parameter [3:0]slave_7 = 4'b0111;

    parameter [1:0]grant0 = 2'h0;
    parameter [1:0]grant1 = 2'h1;
    parameter [1:0]grant2 = 2'h2;
    parameter [1:0]grant3 = 2'h3;

    wire[3:0] req;
    reg[1:0] grant;


    assign req = {m3_req_i, m2_req_i, m1_req_i, m0_req_i};

    always @ (*) begin
        if (req[3]) begin
            grant = grant3;
            hold_flag_o = `HoldEnable;
        end else if (req[0]) begin
            grant = grant0;
            hold_flag_o = `HoldEnable;
        end else if (req[2]) begin
            grant = grant2;
            hold_flag_o = `HoldEnable;
        end else begin
            grant = grant1;
            hold_flag_o = `HoldDisable;
        end
    end

    always @ (*) begin
        m0_data_o = `ZeroWord;
        m1_data_o = `INST_NOP;
        m2_data_o = `ZeroWord;
        m3_data_o = `ZeroWord;

        s0_addr_o = `ZeroWord; s1_addr_o = `ZeroWord;
        s2_addr_o = `ZeroWord; s3_addr_o = `ZeroWord;
        s4_addr_o = `ZeroWord; s5_addr_o = `ZeroWord;
        s6_addr_o = `ZeroWord; s7_addr_o = `ZeroWord;
        s0_data_o = `ZeroWord; s1_data_o = `ZeroWord;
        s2_data_o = `ZeroWord; s3_data_o = `ZeroWord;
        s4_data_o = `ZeroWord; s5_data_o = `ZeroWord;
        s6_data_o = `ZeroWord; s7_data_o = `ZeroWord;
        s0_we_o = `WriteDisable; s1_we_o = `WriteDisable;
        s2_we_o = `WriteDisable; s3_we_o = `WriteDisable;
        s4_we_o = `WriteDisable; s5_we_o = `WriteDisable;
        s6_we_o = `WriteDisable; s7_we_o = `WriteDisable;

        case (grant)
            grant0: begin
                case (m0_addr_i[31:28])
                    slave_0: begin s0_we_o=m0_we_i; s0_addr_o={{4'h0},{m0_addr_i[27:0]}}; s0_data_o=m0_data_i; m0_data_o=s0_data_i; end
                    slave_1: begin s1_we_o=m0_we_i; s1_addr_o={{4'h0},{m0_addr_i[27:0]}}; s1_data_o=m0_data_i; m0_data_o=s1_data_i; end
                    slave_2: begin s2_we_o=m0_we_i; s2_addr_o={{4'h0},{m0_addr_i[27:0]}}; s2_data_o=m0_data_i; m0_data_o=s2_data_i; end
                    slave_3: begin s3_we_o=m0_we_i; s3_addr_o={{4'h0},{m0_addr_i[27:0]}}; s3_data_o=m0_data_i; m0_data_o=s3_data_i; end
                    slave_4: begin s4_we_o=m0_we_i; s4_addr_o={{4'h0},{m0_addr_i[27:0]}}; s4_data_o=m0_data_i; m0_data_o=s4_data_i; end
                    slave_5: begin s5_we_o=m0_we_i; s5_addr_o={{4'h0},{m0_addr_i[27:0]}}; s5_data_o=m0_data_i; m0_data_o=s5_data_i; end
                    slave_6: begin s6_we_o=m0_we_i; s6_addr_o={{4'h0},{m0_addr_i[27:0]}}; s6_data_o=m0_data_i; m0_data_o=s6_data_i; end
                    slave_7: begin s7_we_o=m0_we_i; s7_addr_o={{4'h0},{m0_addr_i[27:0]}}; s7_data_o=m0_data_i; m0_data_o=s7_data_i; end
                    default: begin end
                endcase
            end
            grant1: begin
                case (m1_addr_i[31:28])
                    slave_0: begin s0_we_o=m1_we_i; s0_addr_o={{4'h0},{m1_addr_i[27:0]}}; s0_data_o=m1_data_i; m1_data_o=s0_data_i; end
                    slave_1: begin s1_we_o=m1_we_i; s1_addr_o={{4'h0},{m1_addr_i[27:0]}}; s1_data_o=m1_data_i; m1_data_o=s1_data_i; end
                    slave_2: begin s2_we_o=m1_we_i; s2_addr_o={{4'h0},{m1_addr_i[27:0]}}; s2_data_o=m1_data_i; m1_data_o=s2_data_i; end
                    slave_3: begin s3_we_o=m1_we_i; s3_addr_o={{4'h0},{m1_addr_i[27:0]}}; s3_data_o=m1_data_i; m1_data_o=s3_data_i; end
                    slave_4: begin s4_we_o=m1_we_i; s4_addr_o={{4'h0},{m1_addr_i[27:0]}}; s4_data_o=m1_data_i; m1_data_o=s4_data_i; end
                    slave_5: begin s5_we_o=m1_we_i; s5_addr_o={{4'h0},{m1_addr_i[27:0]}}; s5_data_o=m1_data_i; m1_data_o=s5_data_i; end
                    slave_6: begin s6_we_o=m1_we_i; s6_addr_o={{4'h0},{m1_addr_i[27:0]}}; s6_data_o=m1_data_i; m1_data_o=s6_data_i; end
                    slave_7: begin s7_we_o=m1_we_i; s7_addr_o={{4'h0},{m1_addr_i[27:0]}}; s7_data_o=m1_data_i; m1_data_o=s7_data_i; end
                    default: begin end
                endcase
            end
            grant2: begin
                case (m2_addr_i[31:28])
                    slave_0: begin s0_we_o=m2_we_i; s0_addr_o={{4'h0},{m2_addr_i[27:0]}}; s0_data_o=m2_data_i; m2_data_o=s0_data_i; end
                    slave_1: begin s1_we_o=m2_we_i; s1_addr_o={{4'h0},{m2_addr_i[27:0]}}; s1_data_o=m2_data_i; m2_data_o=s1_data_i; end
                    slave_2: begin s2_we_o=m2_we_i; s2_addr_o={{4'h0},{m2_addr_i[27:0]}}; s2_data_o=m2_data_i; m2_data_o=s2_data_i; end
                    slave_3: begin s3_we_o=m2_we_i; s3_addr_o={{4'h0},{m2_addr_i[27:0]}}; s3_data_o=m2_data_i; m2_data_o=s3_data_i; end
                    slave_4: begin s4_we_o=m2_we_i; s4_addr_o={{4'h0},{m2_addr_i[27:0]}}; s4_data_o=m2_data_i; m2_data_o=s4_data_i; end
                    slave_5: begin s5_we_o=m2_we_i; s5_addr_o={{4'h0},{m2_addr_i[27:0]}}; s5_data_o=m2_data_i; m2_data_o=s5_data_i; end
                    slave_6: begin s6_we_o=m2_we_i; s6_addr_o={{4'h0},{m2_addr_i[27:0]}}; s6_data_o=m2_data_i; m2_data_o=s6_data_i; end
                    slave_7: begin s7_we_o=m2_we_i; s7_addr_o={{4'h0},{m2_addr_i[27:0]}}; s7_data_o=m2_data_i; m2_data_o=s7_data_i; end
                    default: begin end
                endcase
            end
            grant3: begin
                case (m3_addr_i[31:28])
                    slave_0: begin s0_we_o=m3_we_i; s0_addr_o={{4'h0},{m3_addr_i[27:0]}}; s0_data_o=m3_data_i; m3_data_o=s0_data_i; end
                    slave_1: begin s1_we_o=m3_we_i; s1_addr_o={{4'h0},{m3_addr_i[27:0]}}; s1_data_o=m3_data_i; m3_data_o=s1_data_i; end
                    slave_2: begin s2_we_o=m3_we_i; s2_addr_o={{4'h0},{m3_addr_i[27:0]}}; s2_data_o=m3_data_i; m3_data_o=s2_data_i; end
                    slave_3: begin s3_we_o=m3_we_i; s3_addr_o={{4'h0},{m3_addr_i[27:0]}}; s3_data_o=m3_data_i; m3_data_o=s3_data_i; end
                    slave_4: begin s4_we_o=m3_we_i; s4_addr_o={{4'h0},{m3_addr_i[27:0]}}; s4_data_o=m3_data_i; m3_data_o=s4_data_i; end
                    slave_5: begin s5_we_o=m3_we_i; s5_addr_o={{4'h0},{m3_addr_i[27:0]}}; s5_data_o=m3_data_i; m3_data_o=s5_data_i; end
                    slave_6: begin s6_we_o=m3_we_i; s6_addr_o={{4'h0},{m3_addr_i[27:0]}}; s6_data_o=m3_data_i; m3_data_o=s6_data_i; end
                    slave_7: begin s7_we_o=m3_we_i; s7_addr_o={{4'h0},{m3_addr_i[27:0]}}; s7_data_o=m3_data_i; m3_data_o=s7_data_i; end
                    default: begin end
                endcase
            end
            default: begin end
        endcase
    end

endmodule
