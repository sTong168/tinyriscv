`include "../core/defines.v"

// Chip-side bridge to external (FPGA-side) ROM/RAM over an 8-bit frame bus.
// No storage lives inside this module: every access performs a full frame
// exchange over ext_data_o/ext_data_i, and the RIB stalls the CPU
// (ext_hold) until the FPGA-side bridge answers. Read data is delivered
// on the S_DELIVER cycle (done_o pulse), so the CPU samples it in the same
// cycle the stall is released.
//
// Request frame: A5, {6'b0, target_ram, we}, addr[31:0], wdata[31:0]
// Response frame: 5A, status, rdata[31:0]  (big-endian byte order)
module cpu2_mem_bridge(
    input wire clk,
    input wire rst,

    // slave 0 interface (external ROM) from RIB
    input wire s0_req_i,
    input wire s0_we_i,
    input wire[`MemAddrBus] s0_addr_i,
    input wire[`MemBus] s0_data_i,
    output wire[`MemBus] s0_data_o,
    output wire s0_done_o,

    // slave 1 interface (external RAM) from RIB
    input wire s1_req_i,
    input wire s1_we_i,
    input wire[`MemAddrBus] s1_addr_i,
    input wire[`MemBus] s1_data_i,
    output wire[`MemBus] s1_data_o,
    output wire s1_done_o,

    // 8-bit frame bus to FPGA
    input wire[7:0] ext_data_i,
    output reg[7:0] ext_data_o
    );

    localparam [4:0] S_IDLE       = 5'd0;
    localparam [4:0] S_SEND_MAGIC = 5'd1;
    localparam [4:0] S_SEND_CMD   = 5'd2;
    localparam [4:0] S_SEND_ADDR0 = 5'd3;
    localparam [4:0] S_SEND_ADDR1 = 5'd4;
    localparam [4:0] S_SEND_ADDR2 = 5'd5;
    localparam [4:0] S_SEND_ADDR3 = 5'd6;
    localparam [4:0] S_SEND_DATA0 = 5'd7;
    localparam [4:0] S_SEND_DATA1 = 5'd8;
    localparam [4:0] S_SEND_DATA2 = 5'd9;
    localparam [4:0] S_SEND_DATA3 = 5'd10;
    localparam [4:0] S_WAIT_MAGIC = 5'd11;
    localparam [4:0] S_RECV_STAT  = 5'd12;
    localparam [4:0] S_RECV_DATA  = 5'd13;
    localparam [4:0] S_DONE       = 5'd14;
    localparam [4:0] S_DELIVER    = 5'd15;

    reg[4:0] state;
    reg[1:0] recv_index;
    reg target_ram;                 // 0 = ROM, 1 = RAM
    reg latched_we;
    reg[`MemAddrBus] latched_addr;
    reg[`MemBus] latched_wdata;
    reg[`MemBus] latched_rdata;
    reg[`MemBus] rdata_o0;          // delivered read data, slave 0 (ROM)
    reg[`MemBus] rdata_o1;          // delivered read data, slave 1 (RAM)

    assign s0_data_o = rdata_o0;
    assign s1_data_o = rdata_o1;
    assign s0_done_o = (state == S_DELIVER) && (target_ram == 1'b0);
    assign s1_done_o = (state == S_DELIVER) && (target_ram == 1'b1);

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
            rdata_o0 <= `ZeroWord;
            rdata_o1 <= `ZeroWord;
        end else begin
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
                        2'd3: begin
                            // deliver the completed word already on the last
                            // data cycle: the CPU samples it on the
                            // S_DELIVER edge, one cycle later
                            if (target_ram == 1'b1) begin
                                rdata_o1 <= {latched_rdata[31:8], ext_data_i};
                            end else begin
                                rdata_o0 <= {latched_rdata[31:8], ext_data_i};
                            end
                        end
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
