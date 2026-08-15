`include "../../shared/defines.v"

// Shared-clock byte bridge. One request is accepted at a time.
// Request frame: A5, command, address[31:0], write_data[31:0].
// Response frame: 5A, status, read_data[31:0].
module cpu3_chip_bridge(
    input wire clk,
    input wire rst,

    input wire req_i,
    input wire we_i,
    input wire[`MemAddrBus] addr_i,
    input wire[`MemBus] wdata_i,
    output reg[`MemBus] rdata_o,
    output wire done_o,
    output wire busy_o,

    input wire[7:0] bridge_i,
    output reg[7:0] bridge_o
    );

    localparam [7:0] FRAME_REQ  = 8'hA5;
    localparam [7:0] FRAME_RESP = 8'h5A;
    localparam [7:0] CMD_READ   = 8'h01;
    localparam [7:0] CMD_WRITE  = 8'h02;

    localparam [4:0] S_IDLE     = 5'd0;
    localparam [4:0] S_TX_SOF   = 5'd1;
    localparam [4:0] S_TX_CMD   = 5'd2;
    localparam [4:0] S_TX_A3    = 5'd3;
    localparam [4:0] S_TX_A2    = 5'd4;
    localparam [4:0] S_TX_A1    = 5'd5;
    localparam [4:0] S_TX_A0    = 5'd6;
    localparam [4:0] S_TX_D3    = 5'd7;
    localparam [4:0] S_TX_D2    = 5'd8;
    localparam [4:0] S_TX_D1    = 5'd9;
    localparam [4:0] S_TX_D0    = 5'd10;
    localparam [4:0] S_RX_SOF   = 5'd11;
    localparam [4:0] S_RX_STAT  = 5'd12;
    localparam [4:0] S_RX_D3    = 5'd13;
    localparam [4:0] S_RX_D2    = 5'd14;
    localparam [4:0] S_RX_D1    = 5'd15;
    localparam [4:0] S_RX_D0    = 5'd16;

    reg[4:0] state;
    reg we_reg;
    reg[`MemAddrBus] addr_reg;
    reg[`MemBus] wdata_reg;
    reg[7:0] rx_status;
    reg[7:0] rx_d3;
    reg[7:0] rx_d2;
    reg[7:0] rx_d1;

    assign busy_o = (state != S_IDLE);
    assign done_o = (state == S_RX_D0);

    // Include the last response byte combinationally so the consumer can
    // sample a complete word on the done cycle.
    always @ (*) begin
        if (state == S_RX_D0 && rx_status == 8'h00) begin
            rdata_o = {rx_d3, rx_d2, rx_d1, bridge_i};
        end else if (state == S_RX_D0) begin
            rdata_o = `ZeroWord;
        end else begin
            rdata_o = `ZeroWord;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= S_IDLE;
            bridge_o <= 8'h00;
            we_reg <= `WriteDisable;
            addr_reg <= `ZeroWord;
            wdata_reg <= `ZeroWord;
            rx_status <= 8'h00;
            rx_d3 <= 8'h00;
            rx_d2 <= 8'h00;
            rx_d1 <= 8'h00;
        end else begin
            case (state)
                S_IDLE: begin
                    if (req_i) begin
                        we_reg <= we_i;
                        addr_reg <= addr_i;
                        wdata_reg <= wdata_i;
                        bridge_o <= FRAME_REQ;
                        state <= S_TX_SOF;
                    end
                end
                S_TX_SOF: begin
                    bridge_o <= we_reg ? CMD_WRITE : CMD_READ;
                    state <= S_TX_CMD;
                end
                S_TX_CMD: begin
                    bridge_o <= addr_reg[31:24];
                    state <= S_TX_A3;
                end
                S_TX_A3: begin
                    bridge_o <= addr_reg[23:16];
                    state <= S_TX_A2;
                end
                S_TX_A2: begin
                    bridge_o <= addr_reg[15:8];
                    state <= S_TX_A1;
                end
                S_TX_A1: begin
                    bridge_o <= addr_reg[7:0];
                    state <= S_TX_A0;
                end
                S_TX_A0: begin
                    bridge_o <= wdata_reg[31:24];
                    state <= S_TX_D3;
                end
                S_TX_D3: begin
                    bridge_o <= wdata_reg[23:16];
                    state <= S_TX_D2;
                end
                S_TX_D2: begin
                    bridge_o <= wdata_reg[15:8];
                    state <= S_TX_D1;
                end
                S_TX_D1: begin
                    bridge_o <= wdata_reg[7:0];
                    state <= S_TX_D0;
                end
                S_TX_D0: begin
                    bridge_o <= 8'h00;
                    state <= S_RX_SOF;
                end
                S_RX_SOF: begin
                    bridge_o <= 8'h00;
                    if (bridge_i == FRAME_RESP) begin
                        state <= S_RX_STAT;
                    end
                end
                S_RX_STAT: begin
                    bridge_o <= 8'h00;
                    rx_status <= bridge_i;
                    state <= S_RX_D3;
                end
                S_RX_D3: begin
                    bridge_o <= 8'h00;
                    rx_d3 <= bridge_i;
                    state <= S_RX_D2;
                end
                S_RX_D2: begin
                    bridge_o <= 8'h00;
                    rx_d2 <= bridge_i;
                    state <= S_RX_D1;
                end
                S_RX_D1: begin
                    bridge_o <= 8'h00;
                    rx_d1 <= bridge_i;
                    state <= S_RX_D0;
                end
                S_RX_D0: begin
                    bridge_o <= 8'h00;
                    state <= S_IDLE;
                end
                default: begin
                    bridge_o <= 8'h00;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
