`include "../../shared/defines.v"

// FPGA-side bridge to interoperate with chip mem_bridge via 8-bit handshake
module cpu2_bridge_fpga (
    input wire clk,
    input wire rst,

    // from chip
    input  wire [7:0] chip_data_i,
    // to chip
    output reg  [7:0] chip_data_o
    );

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_RECV_CMD   = 4'd1;
    localparam [3:0] S_RECV_ADDR0 = 4'd2;
    localparam [3:0] S_RECV_ADDR1 = 4'd3;
    localparam [3:0] S_RECV_ADDR2 = 4'd4;
    localparam [3:0] S_RECV_ADDR3 = 4'd5;
    localparam [3:0] S_RECV_DATA0 = 4'd6;
    localparam [3:0] S_RECV_DATA1 = 4'd7;
    localparam [3:0] S_RECV_DATA2 = 4'd8;
    localparam [3:0] S_RECV_DATA3 = 4'd9;
    localparam [3:0] S_EXEC       = 4'd10;
    localparam [3:0] S_SEND_MAGIC = 4'd11;
    localparam [3:0] S_SEND_STAT  = 4'd12;
    localparam [3:0] S_SEND_DATA0 = 4'd13;
    localparam [3:0] S_SEND_DATA1 = 4'd14;
    localparam [3:0] S_SEND_DATA2 = 4'd15;

    reg[3:0] state;
    reg send_data3;
    reg write_en;
    reg target_ram;
    reg[`MemAddrBus] addr;
    reg[`MemBus] wdata;
    reg[`MemBus] rdata;

    reg[31:0] ext_rom[0:255];
    reg[31:0] ext_ram[0:15];

    integer i;

    always @ (*) begin
        if (send_data3 == 1'b1) begin
            chip_data_o = rdata[7:0];
        end else begin
            case (state)
                S_SEND_MAGIC: chip_data_o = 8'h5a;
                S_SEND_STAT:  chip_data_o = 8'h00;
                S_SEND_DATA0: chip_data_o = rdata[31:24];
                S_SEND_DATA1: chip_data_o = rdata[23:16];
                S_SEND_DATA2: chip_data_o = rdata[15:8];
                default:      chip_data_o = 8'h00;
            endcase
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= S_IDLE;
            send_data3 <= 1'b0;
            write_en <= `WriteDisable;
            target_ram <= 1'b0;
            addr <= `ZeroWord;
            wdata <= `ZeroWord;
            rdata <= `ZeroWord;
            for (i = 0; i < 16; i = i + 1) begin
                ext_ram[i] <= `ZeroWord;
            end
        end else begin
            case (state)
                S_IDLE: begin
                    send_data3 <= 1'b0;
                    if (chip_data_i == 8'ha5) begin
                        state <= S_RECV_CMD;
                    end
                end
                S_RECV_CMD: begin
                    write_en <= chip_data_i[0];
                    target_ram <= chip_data_i[1];
                    state <= S_RECV_ADDR0;
                end
                S_RECV_ADDR0: begin
                    addr[31:24] <= chip_data_i;
                    state <= S_RECV_ADDR1;
                end
                S_RECV_ADDR1: begin
                    addr[23:16] <= chip_data_i;
                    state <= S_RECV_ADDR2;
                end
                S_RECV_ADDR2: begin
                    addr[15:8] <= chip_data_i;
                    state <= S_RECV_ADDR3;
                end
                S_RECV_ADDR3: begin
                    addr[7:0] <= chip_data_i;
                    state <= S_RECV_DATA0;
                end
                S_RECV_DATA0: begin
                    wdata[31:24] <= chip_data_i;
                    state <= S_RECV_DATA1;
                end
                S_RECV_DATA1: begin
                    wdata[23:16] <= chip_data_i;
                    state <= S_RECV_DATA2;
                end
                S_RECV_DATA2: begin
                    wdata[15:8] <= chip_data_i;
                    state <= S_RECV_DATA3;
                end
                S_RECV_DATA3: begin
                    wdata[7:0] <= chip_data_i;
                    state <= S_EXEC;
                end
                S_EXEC: begin
                    if (target_ram == 1'b1) begin
                        if (addr[31:6] == 26'h0) begin
                            if (write_en == `WriteEnable) begin
                                ext_ram[addr[5:2]] <= wdata;
                                rdata <= wdata;
                            end else begin
                                rdata <= ext_ram[addr[5:2]];
                            end
                        end else begin
                            rdata <= `ZeroWord;
                        end
                    end else begin
                        if (addr[31:10] == 22'h0) begin
                            if (write_en == `WriteEnable) begin
                                ext_rom[addr[9:2]] <= wdata;
                                rdata <= wdata;
                            end else begin
                                rdata <= ext_rom[addr[9:2]];
                            end
                        end else begin
                            rdata <= `ZeroWord;
                        end
                    end
                    state <= S_SEND_MAGIC;
                end
                S_SEND_MAGIC: begin
                    state <= S_SEND_STAT;
                end
                S_SEND_STAT: begin
                    state <= S_SEND_DATA0;
                end
                S_SEND_DATA0: begin
                    state <= S_SEND_DATA1;
                end
                S_SEND_DATA1: begin
                    state <= S_SEND_DATA2;
                end
                S_SEND_DATA2: begin
                    send_data3 <= 1'b1;
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                    send_data3 <= 1'b0;
                end
            endcase
        end
    end

endmodule