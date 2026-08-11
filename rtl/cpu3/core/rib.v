`include "../../shared/defines.v"

// Fixed-priority interconnect with one external-memory slave.
// Region 0/1 are external ROM/RAM, region 3 is UART, region 4 is I2C,
// and region 6 is PWM.
// Local peripherals complete in one cycle; region 0/1 use the bridge wait path.
module cpu3_rib(
    input wire clk,
    input wire rst,

    input wire[`MemAddrBus] m0_addr_i,
    input wire[`MemBus] m0_data_i,
    output reg[`MemBus] m0_data_o,
    input wire m0_req_i,
    input wire m0_we_i,
    output reg m0_done_o,

    input wire[`MemAddrBus] m1_addr_i,
    input wire[`MemBus] m1_data_i,
    output reg[`MemBus] m1_data_o,
    input wire m1_req_i,
    input wire m1_we_i,
    output reg m1_done_o,

    input wire[`MemAddrBus] m2_addr_i,
    input wire[`MemBus] m2_data_i,
    output reg[`MemBus] m2_data_o,
    input wire m2_req_i,
    input wire m2_we_i,
    output reg m2_done_o,

    input wire[`MemAddrBus] m3_addr_i,
    input wire[`MemBus] m3_data_i,
    output reg[`MemBus] m3_data_o,
    input wire m3_req_i,
    input wire m3_we_i,
    output reg m3_done_o,

    input wire[`MemAddrBus] m4_addr_i,
    input wire[`MemBus] m4_data_i,
    output reg[`MemBus] m4_data_o,
    input wire m4_req_i,
    input wire m4_we_i,
    output reg m4_done_o,

    output reg s0_req_o,
    output reg[`MemAddrBus] s0_addr_o,
    output reg[`MemBus] s0_data_o,
    input wire[`MemBus] s0_data_i,
    input wire s0_done_i,
    output reg s0_we_o,

    output reg[`MemAddrBus] s2_addr_o,
    output reg[`MemBus] s2_data_o,
    input wire[`MemBus] s2_data_i,
    output reg s2_we_o,

    output reg s3_req_o,
    output reg[`MemAddrBus] s3_addr_o,
    output reg[`MemBus] s3_data_o,
    input wire[`MemBus] s3_data_i,
    output reg s3_we_o,
    input wire s3_ready_i,

    output reg[`MemAddrBus] s4_addr_o,
    output reg[`MemBus] s4_data_o,
    input wire[`MemBus] s4_data_i,
    output reg s4_we_o,

    output reg hold_flag_o
    );

    localparam [2:0] SRC_M0 = 3'd0;
    localparam [2:0] SRC_M1 = 3'd1;
    localparam [2:0] SRC_M2 = 3'd2;
    localparam [2:0] SRC_M3 = 3'd3;
    localparam [2:0] SRC_M4 = 3'd4;

    localparam [2:0] ACTIVE_NONE = 3'd0;
    localparam [2:0] ACTIVE_M0   = 3'd1;
    localparam [2:0] ACTIVE_M1   = 3'd2;
    localparam [2:0] ACTIVE_M2   = 3'd3;
    localparam [2:0] ACTIVE_M3   = 3'd4;

    reg[2:0] active;
    reg[`MemAddrBus] active_addr;
    reg[`MemBus] active_data;
    reg active_we;

    reg[2:0] selected_src;
    reg[`MemAddrBus] selected_addr;
    reg[`MemBus] selected_data;
    reg selected_we;
    reg selected_req;
    reg selected_to_s0;
    reg selected_to_s2;
    reg selected_to_s3;
    reg selected_to_s4;

    always @ (*) begin
        selected_src = SRC_M1;
        selected_addr = m1_addr_i;
        selected_data = m1_data_i;
        selected_we = m1_we_i;
        selected_req = m1_req_i;

        // Arbitration priority: IF (m4) > UART debug (m3) > sID (m2) >
        // CPU data (m0) > CPU instruction fetch (m1).
        if (m4_req_i) begin
            selected_src = SRC_M4;
            selected_addr = m4_addr_i;
            selected_data = m4_data_i;
            selected_we = m4_we_i;
            selected_req = m4_req_i;
        end else if (m3_req_i) begin
            selected_src = SRC_M3;
            selected_addr = m3_addr_i;
            selected_data = m3_data_i;
            selected_we = m3_we_i;
            selected_req = m3_req_i;
        end else if (m2_req_i) begin
            selected_src = SRC_M2;
            selected_addr = m2_addr_i;
            selected_data = m2_data_i;
            selected_we = m2_we_i;
            selected_req = m2_req_i;
        end else if (m0_req_i) begin
            selected_src = SRC_M0;
            selected_addr = m0_addr_i;
            selected_data = m0_data_i;
            selected_we = m0_we_i;
            selected_req = m0_req_i;
        end

        selected_to_s0 = selected_req &&
                         ((selected_addr[31:28] == 4'h0) ||
                          (selected_addr[31:28] == 4'h1));
        selected_to_s2 = selected_req && (selected_addr[31:28] == 4'h6);
        selected_to_s3 = selected_req && (selected_addr[31:28] == 4'h3);
        selected_to_s4 = selected_req && (selected_addr[31:28] == 4'h4);
    end

    always @ (*) begin
        m0_data_o = `ZeroWord;
        m1_data_o = `INST_NOP;
        m2_data_o = `ZeroWord;
        m3_data_o = `ZeroWord;
        m4_data_o = `ZeroWord;
        m0_done_o = `RIB_NACK;
        m1_done_o = `RIB_NACK;
        m2_done_o = `RIB_NACK;
        m3_done_o = `RIB_NACK;
        m4_done_o = `RIB_NACK;

        s0_req_o = `RIB_NREQ;
        s0_addr_o = `ZeroWord;
        s0_data_o = `ZeroWord;
        s0_we_o = `WriteDisable;
        s2_addr_o = `ZeroWord;
        s2_data_o = `ZeroWord;
        s2_we_o = `WriteDisable;
        s3_req_o = `RIB_NREQ;
        s3_addr_o = `ZeroWord;
        s3_data_o = `ZeroWord;
        s3_we_o = `WriteDisable;
        s4_addr_o = `ZeroWord;
        s4_data_o = `ZeroWord;
        s4_we_o = `WriteDisable;

        if (active != ACTIVE_NONE) begin
            s0_addr_o = active_addr;
            s0_data_o = active_data;
            s0_we_o = active_we;
            if (s0_done_i) begin
                case (active)
                    ACTIVE_M0: begin
                        m0_data_o = s0_data_i;
                        m0_done_o = `RIB_ACK;
                    end
                    ACTIVE_M1: begin
                        m1_data_o = s0_data_i;
                        m1_done_o = `RIB_ACK;
                    end
                    ACTIVE_M2: begin
                        m2_data_o = s0_data_i;
                        m2_done_o = `RIB_ACK;
                    end
                    ACTIVE_M3: begin
                        m3_data_o = s0_data_i;
                        m3_done_o = `RIB_ACK;
                    end
                    default: begin end
                endcase
            end
        end else if (selected_req) begin
            if (selected_to_s0) begin
                s0_req_o = `RIB_REQ;
                s0_addr_o = selected_addr;
                s0_data_o = selected_data;
                s0_we_o = selected_we;
            end else if (selected_to_s2) begin
                s2_addr_o = {4'h0, selected_addr[27:0]};
                s2_data_o = selected_data;
                s2_we_o = selected_we;
                case (selected_src)
                    SRC_M0: begin
                        m0_data_o = s2_data_i;
                        m0_done_o = `RIB_ACK;
                    end
                    SRC_M1: begin
                        m1_data_o = s2_data_i;
                        m1_done_o = `RIB_ACK;
                    end
                    SRC_M2: begin
                        m2_data_o = s2_data_i;
                        m2_done_o = `RIB_ACK;
                    end
                    SRC_M3: begin
                        m3_data_o = s2_data_i;
                        m3_done_o = `RIB_ACK;
                    end
                    SRC_M4: begin
                        m4_data_o = s2_data_i;
                        m4_done_o = `RIB_ACK;
                    end
                    default: begin end
                endcase
            end else if (selected_to_s3) begin
                s3_req_o = `RIB_REQ;
                s3_addr_o = {4'h0, selected_addr[27:0]};
                s3_data_o = selected_data;
                s3_we_o = selected_we;
                case (selected_src)
                    SRC_M0: begin
                        m0_data_o = s3_data_i;
                        m0_done_o = s3_ready_i ? `RIB_ACK : `RIB_NACK;
                    end
                    SRC_M1: begin
                        m1_data_o = s3_data_i;
                        m1_done_o = s3_ready_i ? `RIB_ACK : `RIB_NACK;
                    end
                    SRC_M2: begin
                        m2_data_o = s3_data_i;
                        m2_done_o = s3_ready_i ? `RIB_ACK : `RIB_NACK;
                    end
                    SRC_M3: begin
                        m3_data_o = s3_data_i;
                        m3_done_o = s3_ready_i ? `RIB_ACK : `RIB_NACK;
                    end
                    SRC_M4: begin
                        m4_data_o = s3_data_i;
                        m4_done_o = s3_ready_i ? `RIB_ACK : `RIB_NACK;
                    end
                    default: begin end
                endcase
            end else if (selected_to_s4) begin
                s4_addr_o = {4'h0, selected_addr[27:0]};
                s4_data_o = selected_data;
                s4_we_o = selected_we;
                case (selected_src)
                    SRC_M0: begin
                        m0_data_o = s4_data_i;
                        m0_done_o = `RIB_ACK;
                    end
                    SRC_M1: begin
                        m1_data_o = s4_data_i;
                        m1_done_o = `RIB_ACK;
                    end
                    SRC_M2: begin
                        m2_data_o = s4_data_i;
                        m2_done_o = `RIB_ACK;
                    end
                    SRC_M3: begin
                        m3_data_o = s4_data_i;
                        m3_done_o = `RIB_ACK;
                    end
                    SRC_M4: begin
                        m4_data_o = s4_data_i;
                        m4_done_o = `RIB_ACK;
                    end
                    default: begin end
                endcase
            end else begin
                case (selected_src)
                    SRC_M0: m0_done_o = `RIB_ACK;
                    SRC_M1: m1_done_o = `RIB_ACK;
                    SRC_M2: m2_done_o = `RIB_ACK;
                    SRC_M3: m3_done_o = `RIB_ACK;
                    SRC_M4: m4_done_o = `RIB_ACK;
                    default: begin end
                endcase
            end
        end

        // The bridge and debug master must be allowed to finish before a
        // new instruction fetch is issued.
        if (m4_req_i || m2_req_i || m3_req_i || (active == ACTIVE_M2) ||
            ((active == ACTIVE_M1) && !s0_done_i) ||
            ((active == ACTIVE_NONE) && m0_req_i && selected_to_s0)) begin
            hold_flag_o = `HoldEnable;
        end else begin
            hold_flag_o = `HoldDisable;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            active <= ACTIVE_NONE;
            active_addr <= `ZeroWord;
            active_data <= `ZeroWord;
            active_we <= `WriteDisable;
        end else begin
            if (active != ACTIVE_NONE) begin
                if (s0_done_i) begin
                    active <= ACTIVE_NONE;
                end
            end else if (selected_to_s0) begin
                case (selected_src)
                    SRC_M0: active <= ACTIVE_M0;
                    SRC_M1: active <= ACTIVE_M1;
                    SRC_M2: active <= ACTIVE_M2;
                    SRC_M3: active <= ACTIVE_M3;
                    default: active <= ACTIVE_NONE;
                endcase
                active_addr <= selected_addr;
                active_data <= selected_data;
                active_we <= selected_we;
            end
        end
    end

endmodule
