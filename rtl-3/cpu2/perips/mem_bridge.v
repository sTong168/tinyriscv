`include "../core/defines.v"

// Bridge to expose on-chip slave as off-chip memory interface
// Uses 8-bit TX/RX handshake: tx_valid/tx_ready and rx_valid/rx_ready
module cpu2_mem_bridge(
    input wire clk,
    input wire rst,

    // interface from RIB (slave side)
    input wire s0_req_i,
    input wire s0_we_i,
    input wire[`MemAddrBus] s0_addr_i,
    input wire[`MemBus] s0_data_i,
    output wire[`MemBus] s0_data_o,

    input wire s1_req_i,
    input wire s1_we_i,
    input wire[`MemAddrBus] s1_addr_i,
    input wire[`MemBus] s1_data_i,
    output wire[`MemBus] s1_data_o,
    
    input wire[7:0] ext_data_i,
    output reg[7:0] ext_data_o,
    output wire hold_flag_o
    );

    localparam [3:0] S_IDLE       = 4'd0;
    localparam [3:0] S_SEND_MAGIC = 4'd1;
    localparam [3:0] S_SEND_CMD   = 4'd2;
    localparam [3:0] S_SEND_ADDR0 = 4'd3;
    localparam [3:0] S_SEND_ADDR1 = 4'd4;
    localparam [3:0] S_SEND_ADDR2 = 4'd5;
    localparam [3:0] S_SEND_ADDR3 = 4'd6;
    localparam [3:0] S_SEND_DATA0 = 4'd7;
    localparam [3:0] S_SEND_DATA1 = 4'd8;
    localparam [3:0] S_SEND_DATA2 = 4'd9;
    localparam [3:0] S_SEND_DATA3 = 4'd10;
    localparam [3:0] S_WAIT_MAGIC = 4'd11;
    localparam [3:0] S_RECV_STAT  = 4'd12;
    localparam [3:0] S_RECV_DATA  = 4'd13;
    localparam [3:0] S_DONE       = 4'd14;
    localparam [3:0] S_DELIVER    = 4'd15;

    reg[3:0] state;
    reg[1:0] recv_index;
    reg target_ram;
    reg latched_we;
    reg[`MemAddrBus] latched_addr;
    reg[`MemBus] latched_wdata;
    reg[`MemBus] latched_rdata;

    reg[31:0] ext_rom[0:255];
    reg[31:0] ext_ram[0:15];
    integer i;

    wire s0_rom_hit = (s0_addr_i[31:10] == 22'h0);
    wire s0_ram_alias_hit = (s0_addr_i[31:6] == 26'h3ffffff);

    assign s0_data_o = s0_rom_hit ? ext_rom[s0_addr_i[9:2]] :
                       (s0_ram_alias_hit ? ext_ram[s0_addr_i[5:2]] : `ZeroWord);
    assign s1_data_o = (s1_addr_i[31:6] == 26'h0) ? ext_ram[s1_addr_i[5:2]] : `ZeroWord;
    assign hold_flag_o = `HoldDisable;

    always @ (*) begin
        case (state)
            S_SEND_MAGIC: ext_data_o = 8'ha5;
            S_SEND_CMD:   ext_data_o = {6'b0, target_ram, latched_we};
            S_SEND_ADDR0: ext_data_o = latched_addr[31:24];
            S_SEND_ADDR1: ext_data_o = latched_addr[23:16];
            S_SEND_ADDR2: ext_data_o = latched_addr[15:8];
            S_SEND_ADDR3: ext_data_o = latched_addr[7:0];
            S_SEND_DATA0: ext_data_o = latched_wdata[31:24];
            S_SEND_DATA1: ext_data_o = latched_wdata[23:16];
            S_SEND_DATA2: ext_data_o = latched_wdata[15:8];
            S_SEND_DATA3: ext_data_o = latched_wdata[7:0];
            default:      ext_data_o = 8'h00;
        endcase
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state <= S_IDLE;
            recv_index <= 2'h0;
            target_ram <= 1'b0;
            latched_we <= `WriteDisable;
            latched_addr <= `ZeroWord;
            latched_wdata <= `ZeroWord;
            latched_rdata <= `ZeroWord;
            for (i = 0; i < 16; i = i + 1) begin
                ext_ram[i] <= `ZeroWord;
            end
        end else begin
            if ((s0_req_i == `RIB_REQ) && (s0_we_i == `WriteEnable) && s0_rom_hit) begin
                ext_rom[s0_addr_i[9:2]] <= s0_data_i;
            end
            if ((s0_req_i == `RIB_REQ) && (s0_we_i == `WriteEnable) && s0_ram_alias_hit) begin
                ext_ram[s0_addr_i[5:2]] <= s0_data_i;
            end
            if ((s1_req_i == `RIB_REQ) && (s1_we_i == `WriteEnable) && (s1_addr_i[31:6] == 26'h0)) begin
                ext_ram[s1_addr_i[5:2]] <= s1_data_i;
            end

            case (state)
                S_IDLE: begin
                    recv_index <= 2'h0;
                    if (s1_req_i == `RIB_REQ) begin
                        target_ram <= 1'b1;
                        latched_we <= s1_we_i;
                        latched_addr <= s1_addr_i;
                        latched_wdata <= s1_data_i;
                        state <= S_SEND_MAGIC;
                    end else if (s0_req_i == `RIB_REQ) begin
                        target_ram <= 1'b0;
                        latched_we <= s0_we_i;
                        latched_addr <= s0_addr_i;
                        latched_wdata <= s0_data_i;
                        state <= S_SEND_MAGIC;
                    end
                end
                S_SEND_MAGIC: state <= S_SEND_CMD;
                S_SEND_CMD:   state <= S_SEND_ADDR0;
                S_SEND_ADDR0: state <= S_SEND_ADDR1;
                S_SEND_ADDR1: state <= S_SEND_ADDR2;
                S_SEND_ADDR2: state <= S_SEND_ADDR3;
                S_SEND_ADDR3: state <= S_SEND_DATA0;
                S_SEND_DATA0: state <= S_SEND_DATA1;
                S_SEND_DATA1: state <= S_SEND_DATA2;
                S_SEND_DATA2: state <= S_SEND_DATA3;
                S_SEND_DATA3: state <= S_WAIT_MAGIC;
                S_WAIT_MAGIC: begin
                    if (ext_data_i == 8'h5a) begin
                        state <= S_RECV_STAT;
                    end
                end
                S_RECV_STAT: begin
                    recv_index <= 2'h0;
                    state <= S_RECV_DATA;
                end
                S_RECV_DATA: begin
                    case (recv_index)
                        2'd0: latched_rdata[31:24] <= ext_data_i;
                        2'd1: latched_rdata[23:16] <= ext_data_i;
                        2'd2: latched_rdata[15:8] <= ext_data_i;
                        2'd3: latched_rdata[7:0] <= ext_data_i;
                    endcase

                    if (recv_index == 2'd3) begin
                        state <= S_DONE;
                    end else begin
                        recv_index <= recv_index + 1'b1;
                    end
                end
                S_DONE: begin
                    state <= S_DELIVER;
                end
                S_DELIVER: begin
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule