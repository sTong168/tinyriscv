`include "../core/defines.v"

// FPGA-side bridge endpoint and external memories.
module fpga_bridge(
    input wire clk,
    input wire rst,
    input wire[7:0] bridge_i,
    output reg[7:0] bridge_o,

    output wire rom_we_o,
    output wire[7:0] rom_addr_o,
    output wire[`MemBus] rom_wdata_o,
    input wire[`MemBus] rom_rdata_i,
    output wire ram_we_o,
    output wire[3:0] ram_addr_o,
    output wire[`MemBus] ram_wdata_o,
    input wire[`MemBus] ram_rdata_i
    );

    localparam [7:0] FRAME_REQ  = 8'hA5;
    localparam [7:0] FRAME_RESP = 8'h5A;
    localparam [7:0] CMD_READ   = 8'h01;
    localparam [7:0] CMD_WRITE  = 8'h02;

    localparam [4:0] S_RX_IDLE  = 5'd0;
    localparam [4:0] S_RX_CMD   = 5'd1;
    localparam [4:0] S_RX_A3    = 5'd2;
    localparam [4:0] S_RX_A2    = 5'd3;
    localparam [4:0] S_RX_A1    = 5'd4;
    localparam [4:0] S_RX_A0    = 5'd5;
    localparam [4:0] S_RX_D3    = 5'd6;
    localparam [4:0] S_RX_D2    = 5'd7;
    localparam [4:0] S_RX_D1    = 5'd8;
    localparam [4:0] S_RX_D0    = 5'd9;
    localparam [4:0] S_TX_SOF   = 5'd10;
    localparam [4:0] S_TX_STAT  = 5'd11;
    localparam [4:0] S_TX_D3    = 5'd12;
    localparam [4:0] S_TX_D2    = 5'd13;
    localparam [4:0] S_TX_D1    = 5'd14;
    localparam [4:0] S_TX_D0    = 5'd15;

    reg[4:0] state;
    reg[7:0] cmd_reg;
    reg[`MemAddrBus] addr_reg;
    reg[7:0] data_d3;
    reg[7:0] data_d2;
    reg[7:0] data_d1;
    reg[7:0] response_status;
    reg[`MemBus] response_data;

    wire rom_sel = (addr_reg[31:28] == 4'h0) && (addr_reg[31:10] == 22'h0);
    wire ram_sel = (addr_reg[31:28] == 4'h1) && (addr_reg[27:6] == 22'h0);
    wire[`MemBus] request_data = {data_d3, data_d2, data_d1, bridge_i};

    assign rom_we_o = (state == S_RX_D0) && (cmd_reg == CMD_WRITE) && rom_sel;
    assign rom_addr_o = addr_reg[9:2];
    assign rom_wdata_o = request_data;
    assign ram_we_o = (state == S_RX_D0) && (cmd_reg == CMD_WRITE) && ram_sel;
    assign ram_addr_o = addr_reg[5:2];
    assign ram_wdata_o = request_data;

    always @ (*) begin
        bridge_o = 8'h00;
        case (state)
            S_TX_SOF:  bridge_o = FRAME_RESP;
            S_TX_STAT: bridge_o = response_status;
            S_TX_D3:   bridge_o = response_data[31:24];
            S_TX_D2:   bridge_o = response_data[23:16];
            S_TX_D1:   bridge_o = response_data[15:8];
            S_TX_D0:   bridge_o = response_data[7:0];
            default:   bridge_o = 8'h00;
        endcase
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= S_RX_IDLE;
            cmd_reg <= 8'h00;
            addr_reg <= `ZeroWord;
            data_d3 <= 8'h00;
            data_d2 <= 8'h00;
            data_d1 <= 8'h00;
            response_status <= 8'h00;
            response_data <= `ZeroWord;
        end else begin
            case (state)
                S_RX_IDLE: begin
                    if (bridge_i == FRAME_REQ) begin
                        state <= S_RX_CMD;
                    end
                end
                S_RX_CMD: begin
                    cmd_reg <= bridge_i;
                    state <= S_RX_A3;
                end
                S_RX_A3: begin
                    addr_reg[31:24] <= bridge_i;
                    state <= S_RX_A2;
                end
                S_RX_A2: begin
                    addr_reg[23:16] <= bridge_i;
                    state <= S_RX_A1;
                end
                S_RX_A1: begin
                    addr_reg[15:8] <= bridge_i;
                    state <= S_RX_A0;
                end
                S_RX_A0: begin
                    addr_reg[7:0] <= bridge_i;
                    state <= S_RX_D3;
                end
                S_RX_D3: begin
                    data_d3 <= bridge_i;
                    state <= S_RX_D2;
                end
                S_RX_D2: begin
                    data_d2 <= bridge_i;
                    state <= S_RX_D1;
                end
                S_RX_D1: begin
                    data_d1 <= bridge_i;
                    state <= S_RX_D0;
                end
                S_RX_D0: begin
                    response_data <= `ZeroWord;
                    if (cmd_reg == CMD_READ) begin
                        if (rom_sel) begin
                            response_status <= 8'h00;
                            response_data <= rom_rdata_i;
                        end else if (ram_sel) begin
                            response_status <= 8'h00;
                            response_data <= ram_rdata_i;
                        end else begin
                            response_status <= 8'h01;
                        end
                    end else if (cmd_reg == CMD_WRITE) begin
                        if (rom_sel || ram_sel) begin
                            response_status <= 8'h00;
                        end else begin
                            response_status <= 8'h01;
                        end
                    end else begin
                        response_status <= 8'h01;
                    end
                    state <= S_TX_SOF;
                end
                S_TX_SOF:  state <= S_TX_STAT;
                S_TX_STAT: state <= S_TX_D3;
                S_TX_D3:   state <= S_TX_D2;
                S_TX_D2:   state <= S_TX_D1;
                S_TX_D1:   state <= S_TX_D0;
                S_TX_D0:   state <= S_RX_IDLE;
                default:   state <= S_RX_IDLE;
            endcase
        end
    end

endmodule

module fpga_bridge_top(
    input wire clk,
    input wire rst,
    input wire[7:0] bridge_i,
    output wire[7:0] bridge_o
    );

    wire rom_we;
    wire[7:0] rom_addr;
    wire[`MemBus] rom_wdata;
    wire[`MemBus] rom_rdata;
    wire ram_we;
    wire[3:0] ram_addr;
    wire[`MemBus] ram_wdata;
    wire[`MemBus] ram_rdata;

    fpga_bridge u_fpga_bridge(
        .clk(clk),
        .rst(rst),
        .bridge_i(bridge_i),
        .bridge_o(bridge_o),
        .rom_we_o(rom_we),
        .rom_addr_o(rom_addr),
        .rom_wdata_o(rom_wdata),
        .rom_rdata_i(rom_rdata),
        .ram_we_o(ram_we),
        .ram_addr_o(ram_addr),
        .ram_wdata_o(ram_wdata),
        .ram_rdata_i(ram_rdata)
    );

    external_rom u_external_rom(
        .clk(clk),
        .we_i(rom_we),
        .addr_i(rom_addr),
        .data_i(rom_wdata),
        .data_o(rom_rdata)
    );

    external_ram u_external_ram(
        .clk(clk),
        .we_i(ram_we),
        .addr_i(ram_addr),
        .data_i(ram_wdata),
        .data_o(ram_rdata)
    );

endmodule
