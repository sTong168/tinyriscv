`include "../core/defines.v"


// RIB总线模块 — cpu0-style req/ack; s0=cpu1_bridge(ROM/RAM), s2=LFSR, s3=UART, s6=PWM, s7=I2C
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

    // master 3 interface
    input wire[`MemAddrBus] m3_addr_i,
    input wire[`MemBus] m3_data_i,
    output reg[`MemBus] m3_data_o,
    input wire m3_req_i,
    input wire m3_we_i,
    output reg m3_ack_o,

    // slave 0 interface (memory cpu1_bridge: ROM 0x0 / RAM 0x1)
    output reg[`MemAddrBus] s0_addr_o,
    output reg[`MemBus] s0_data_o,
    input wire[`MemBus] s0_data_i,
    output reg s0_we_o,
    output reg s0_req_o,
    input wire s0_ack_i,

    // slave 2 interface (LFSR 0x2)
    output reg[`MemAddrBus] s2_addr_o,
    output reg[`MemBus] s2_data_o,
    input wire[`MemBus] s2_data_i,
    output reg s2_we_o,
    output reg s2_req_o,
    input wire s2_ack_i,

    // slave 3 interface (UART 0x3)
    output reg[`MemAddrBus] s3_addr_o,
    output reg[`MemBus] s3_data_o,
    input wire[`MemBus] s3_data_i,
    output reg s3_we_o,
    output reg s3_req_o,
    input wire s3_ack_i,

    // slave 6 interface (PWM 0x6)
    output reg[`MemAddrBus] s6_addr_o,
    output reg[`MemBus] s6_data_o,
    input wire[`MemBus] s6_data_i,
    output reg s6_we_o,
    output reg s6_req_o,
    input wire s6_ack_i,

    // slave 7 interface (I2C 0x7)
    output reg[`MemAddrBus] s7_addr_o,
    output reg[`MemBus] s7_data_o,
    input wire[`MemBus] s7_data_i,
    output reg s7_we_o,
    output reg s7_req_o,
    input wire s7_ack_i,

    output wire [1:0] hold_flag_o

    );


    parameter [3:0]slave_0 = 4'b000x;
    parameter [3:0]slave_2 = 4'b0010;
    parameter [3:0]slave_3 = 4'b0011;
    parameter [3:0]slave_6 = 4'b0110;
    parameter [3:0]slave_7 = 4'b0111;

    parameter [1:0]grant0 = 2'h0;
    parameter [1:0]grant1 = 2'h1;
    parameter [1:0]grant3 = 2'h3;

    wire[2:0] req;
    reg[1:0] grant;

    reg hold_flag_m;
    reg hold_flag_s;

    assign hold_flag_o = {hold_flag_m, hold_flag_s};

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

    always @ (*) begin
        m0_data_o = `ZeroWord;
        m1_data_o = `INST_NOP;
        m3_data_o = `ZeroWord;
        m3_ack_o  = `RIB_NACK;

        s0_addr_o = `ZeroWord;
        s2_addr_o = `ZeroWord;
        s3_addr_o = `ZeroWord;
        s6_addr_o = `ZeroWord;
        s7_addr_o = `ZeroWord;
        s0_data_o = `ZeroWord;
        s2_data_o = `ZeroWord;
        s3_data_o = `ZeroWord;
        s6_data_o = `ZeroWord;
        s7_data_o = `ZeroWord;
        s0_we_o = `WriteDisable;
        s2_we_o = `WriteDisable;
        s3_we_o = `WriteDisable;
        s6_we_o = `WriteDisable;
        s7_we_o = `WriteDisable;
        s0_req_o  = `RIB_NREQ;
        s2_req_o  = `RIB_NREQ;
        s3_req_o  = `RIB_NREQ;
        s6_req_o  = `RIB_NREQ;
        s7_req_o  = `RIB_NREQ;

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
                    slave_7: begin
                        s7_we_o = m0_we_i;
                        s7_addr_o = {{4'h0}, {m0_addr_i[27:0]}};
                        s7_data_o = m0_data_i;
                        m0_data_o = s7_data_i;
                        s7_req_o  = m0_req_i;
                        hold_flag_s = (s7_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
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
                    slave_7: begin
                        s7_we_o = m1_we_i;
                        s7_addr_o = {{4'h0}, {m1_addr_i[27:0]}};
                        s7_data_o = m1_data_i;
                        m1_data_o = s7_data_i;
                        s7_req_o  = m1_req_i;
                        hold_flag_s = (s7_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
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
                    slave_7: begin
                        s7_we_o = m3_we_i;
                        s7_addr_o = {{4'h0}, {m3_addr_i[27:0]}};
                        s7_data_o = m3_data_i;
                        m3_data_o = s7_data_i;
                        s7_req_o  = m3_req_i;
                        m3_ack_o  = s7_ack_i;
                        hold_flag_s = (s7_ack_i == `RIB_ACK) ? `HoldDisable : `HoldEnable;
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
