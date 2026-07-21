`include "defines.v"


// RIB总线模块
module rib(

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

    // master 3 interface
    input wire[`MemAddrBus] m3_addr_i,
    input wire[`MemBus] m3_data_i,
    output reg[`MemBus] m3_data_o,
    input wire m3_req_i,
    input wire m3_we_i,
    output reg m3_ack_o,

    // slave 0 interface
    output reg[`MemAddrBus] s0_addr_o,
    output reg[`MemBus] s0_data_o,
    input wire[`MemBus] s0_data_i,
    output reg s0_we_o,
    output reg s0_req_o,
    input wire s0_ack_i,

    // slave 1 interface
    output reg[`MemAddrBus] s1_addr_o,
    output reg[`MemBus] s1_data_o,
    input wire[`MemBus] s1_data_i,
    output reg s1_we_o,
    output reg s1_req_o,
    input wire s1_ack_i,

    // slave 2 interface
    output reg[`MemAddrBus] s2_addr_o,
    output reg[`MemBus] s2_data_o,
    input wire[`MemBus] s2_data_i,
    output reg s2_we_o,
    output reg s2_req_o,
    input wire s2_ack_i,

    // slave 3 interface
    output reg[`MemAddrBus] s3_addr_o,
    output reg[`MemBus] s3_data_o,
    input wire[`MemBus] s3_data_i,
    output reg s3_we_o,
    output reg s3_req_o,
    input wire s3_ack_i,

    // slave 6 interface
    output reg[`MemAddrBus] s6_addr_o,
    output reg[`MemBus] s6_data_o,
    input wire[`MemBus] s6_data_i,
    output reg s6_we_o,
    output reg s6_req_o,
    input wire s6_ack_i,

    output wire [1:0] hold_flag_o

    );


    // 访问地址的最高4位决定要访问的是哪一个从设备
    parameter [3:0]slave_0 = 4'b000x;
    // parameter [3:0]slave_1 = 4'b0001;
    parameter [3:0]slave_2 = 4'b0111;
    parameter [3:0]slave_3 = 4'b0011;
    parameter [3:0]slave_6 = 4'b0110;

    parameter [1:0]grant0 = 2'h0;
    parameter [1:0]grant1 = 2'h1;
    parameter [1:0]grant3 = 2'h3;

    wire[2:0] req;
    reg[1:0] grant;

    reg hold_flag_m;
    reg hold_flag_s;

    assign hold_flag_o = {hold_flag_m, hold_flag_s};

    // 主设备请求信号 (m0, m1, m3)
    assign req = {m3_req_i, m1_req_i, m0_req_i};

    // 仲裁逻辑: m3 > m0 > m1
    always @ (*) begin
        if (req[2]) begin
            grant = grant3;
            hold_flag_m = `HoldEnable;
        end else if (req[0]) begin
            grant = grant0;
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
        m3_data_o = `ZeroWord;
        m3_ack_o  = `RIB_NACK;

        s0_addr_o = `ZeroWord;
        s1_addr_o = `ZeroWord;
        s2_addr_o = `ZeroWord;
        s3_addr_o = `ZeroWord;
        s6_addr_o = `ZeroWord;
        s0_data_o = `ZeroWord;
        s1_data_o = `ZeroWord;
        s2_data_o = `ZeroWord;
        s3_data_o = `ZeroWord;
        s6_data_o = `ZeroWord;
        s0_we_o = `WriteDisable;
        s1_we_o = `WriteDisable;
        s2_we_o = `WriteDisable;
        s3_we_o = `WriteDisable;
        s6_we_o = `WriteDisable;
        s0_req_o  = `RIB_NREQ;
        s1_req_o  = `RIB_NREQ;
        s2_req_o  = `RIB_NREQ;
        s3_req_o  = `RIB_NREQ;
        s6_req_o  = `RIB_NREQ;

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
                    slave_2: begin
                        s2_we_o = m1_we_i;
                        s2_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
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
            grant3: begin
                casex (m3_addr_i[31:28])
                    slave_0: begin
                        s0_we_o = m3_we_i;
                        s0_addr_o = m3_addr_i;
                        s0_data_o = m3_data_i;
                        m3_data_o = s0_data_i;
                        s0_req_o  = m3_req_i;
                        m3_ack_o  = s0_ack_i;
                        hold_flag_s = (s0_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_2: begin
                        s2_we_o = m3_we_i;
                        s2_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s2_data_o = m3_data_i;
                        m3_data_o = s2_data_i;
                        s2_req_o  = m3_req_i;
                        m3_ack_o  = s2_ack_i;
                        hold_flag_s = (s2_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_3: begin
                        s3_we_o = m3_we_i;
                        s3_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s3_data_o = m3_data_i;
                        m3_data_o = s3_data_i;
                        s3_req_o  = m3_req_i;
                        m3_ack_o  = s3_ack_i;
                        hold_flag_s = (s3_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
                    end
                    slave_6: begin
                        s6_we_o = m3_we_i;
                        s6_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s6_data_o = m3_data_i;
                        m3_data_o = s6_data_i;
                        s6_req_o  = m3_req_i;
                        m3_ack_o  = s6_ack_i;
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