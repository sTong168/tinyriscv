// =============================================================================
// cpu1_inst_rt_ctrl - rT driver for improved cpu1_i2c
// Desktop preview only; does NOT replace project RTL until you choose to.
//
// Behavior:
//   - Does NOT force slave address every time (uses ADDR reset default 0x48,
//     or whatever software last programmed into 0x7010_0000)
//   - Loads TX = 0x00 (LM75 Temp pointer)
//   - Issues CMD = WR_RD2 (3): write pointer + Sr + read 2 bytes
//   - Writes rd = RX0 (integer Celsius / Temp MSB), same software-visible
//     result style as the old rT path
//
// Module name / ports match existing cpu1_inst_rt_ctrl for later drop-in.
// =============================================================================
`include "../../shared/defines.v"

module cpu1_inst_rt_ctrl(
    input  wire        clk,
    input  wire        rst,

    input  wire        start_i,
    input  wire[`MemBus] mem_rdata_i,
    input  wire[`RegAddrBus] reg_waddr_i,

    output reg         busy_o,
    output reg[`MemAddrBus] addr_o,
    output reg[`MemBus] wdata_o,
    output reg         we_o,
    output reg         req_o,
    output reg         reg_we_o,
    output reg[`RegAddrBus] reg_waddr_o,
    output reg[`RegBus] reg_wdata_o
);

    localparam I2C_STATUS = 32'h70000000;
    localparam I2C_TX     = 32'h70200000;
    localparam I2C_RX0    = 32'h70300000;
    localparam I2C_CMD    = 32'h70400000;

    localparam CMD_WR_RD2 = 32'd3;

    localparam S_IDLE     = 3'd0;
    localparam S_SET_TX   = 3'd1;
    localparam S_SET_CMD  = 3'd2;
    localparam S_WAITBUSY = 3'd3;
    localparam S_WAITDONE = 3'd4;
    localparam S_READ     = 3'd5;
    localparam S_DONE     = 3'd6;

    reg [2:0] state;
    reg [`RegAddrBus] saved_rd;
    reg [`RegBus] result;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state       <= S_IDLE;
            busy_o      <= `HoldDisable;
            addr_o      <= `ZeroWord;
            wdata_o     <= `ZeroWord;
            we_o        <= `WriteDisable;
            req_o       <= `RIB_NREQ;
            saved_rd    <= `ZeroReg;
            result      <= `ZeroWord;
            reg_we_o    <= `WriteDisable;
            reg_waddr_o <= `ZeroReg;
            reg_wdata_o <= `ZeroWord;
        end else begin
            reg_we_o <= `WriteDisable;
            case (state)
                S_IDLE: begin
                    busy_o      <= `HoldDisable;
                    we_o        <= `WriteDisable;
                    req_o       <= `RIB_NREQ;
                    reg_waddr_o <= `ZeroReg;
                    reg_wdata_o <= `ZeroWord;
                    if (start_i == `True) begin
                        saved_rd <= reg_waddr_i;
                        busy_o   <= `HoldEnable;
                        // pointer = Temp register
                        state    <= S_SET_TX;
                        addr_o   <= I2C_TX;
                        wdata_o  <= 32'h00;
                        we_o     <= `WriteEnable;
                        req_o    <= `RIB_REQ;
                    end
                end

                S_SET_TX: begin
                    state   <= S_SET_CMD;
                    addr_o  <= I2C_CMD;
                    wdata_o <= CMD_WR_RD2;
                    we_o    <= `WriteEnable;
                    req_o   <= `RIB_REQ;
                end

                S_SET_CMD: begin
                    state  <= S_WAITBUSY;
                    addr_o <= I2C_STATUS;
                    we_o   <= `WriteDisable;
                    req_o  <= `RIB_REQ;
                end

                S_WAITBUSY: begin
                    addr_o <= I2C_STATUS;
                    we_o   <= `WriteDisable;
                    req_o  <= `RIB_REQ;
                    if (mem_rdata_i[0] == 1'b1)
                        state <= S_WAITDONE;
                end

                S_WAITDONE: begin
                    addr_o <= I2C_STATUS;
                    we_o   <= `WriteDisable;
                    req_o  <= `RIB_REQ;
                    if (mem_rdata_i[0] == 1'b0) begin
                        state  <= S_READ;
                        addr_o <= I2C_RX0;
                    end
                end

                S_READ: begin
                    result <= {24'h0, mem_rdata_i[7:0]};
                    state  <= S_DONE;
                    we_o   <= `WriteDisable;
                    req_o  <= `RIB_NREQ;
                end

                S_DONE: begin
                    state       <= S_IDLE;
                    busy_o      <= `HoldDisable;
                    req_o       <= `RIB_NREQ;
                    reg_we_o    <= `WriteEnable;
                    reg_waddr_o <= saved_rd;
                    reg_wdata_o <= result;
                end

                default: begin
                    state  <= S_IDLE;
                    busy_o <= `HoldDisable;
                    req_o  <= `RIB_NREQ;
                end
            endcase
        end
    end

endmodule
