// mem_bridge_master.v — chip-side EMIF-8 (16-wire, in-band handshake)
// Shared clk with FPGA. No em_req/em_ack pins.
// Dout is combinational from state (same style as gxy) so each cycle's byte is aligned.
`include "../core/defines.v"

module cpu1_mem_bridge_master(
    input  wire        clk,
    input  wire        rst,

    input  wire        start_i,
    input  wire        memsel_i,
    input  wire        we_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    output reg  [31:0] rdata_o,
    output reg         done_o,
    output reg         busy_o,

    output wire [7:0]  bridge_o,
    input  wire [7:0]  bridge_i
);

    localparam S_IDLE       = 4'd0;
    localparam S_SEND_MAGIC = 4'd1;
    localparam S_SEND_CMD   = 4'd2;
    localparam S_SEND_ADDR0 = 4'd3;
    localparam S_SEND_ADDR1 = 4'd4;
    localparam S_SEND_ADDR2 = 4'd5;
    localparam S_SEND_ADDR3 = 4'd6;
    localparam S_SEND_DATA0 = 4'd7;
    localparam S_SEND_DATA1 = 4'd8;
    localparam S_SEND_DATA2 = 4'd9;
    localparam S_SEND_DATA3 = 4'd10;
    localparam S_WAIT_ACK   = 4'd11;
    localparam S_RECV_DATA0 = 4'd12;
    localparam S_RECV_DATA1 = 4'd13;
    localparam S_RECV_DATA2 = 4'd14;
    localparam S_RECV_DATA3 = 4'd15;

    reg [3:0]  state;
    reg [31:0] addr_r, wdata_r, rdata_r;
    reg        memsel_r, we_r;
    reg [7:0]  dout;

    assign bridge_o = dout;

    always @ (*) begin
        case (state)
            S_SEND_MAGIC: dout = `EMIF_MAGIC;
            S_SEND_CMD:   dout = {6'b0, memsel_r, we_r};
            S_SEND_ADDR0: dout = addr_r[31:24];
            S_SEND_ADDR1: dout = addr_r[23:16];
            S_SEND_ADDR2: dout = addr_r[15:8];
            S_SEND_ADDR3: dout = addr_r[7:0];
            S_SEND_DATA0: dout = we_r ? wdata_r[31:24] : `EMIF_IDLE;
            S_SEND_DATA1: dout = we_r ? wdata_r[23:16] : `EMIF_IDLE;
            S_SEND_DATA2: dout = we_r ? wdata_r[15:8]  : `EMIF_IDLE;
            S_SEND_DATA3: dout = we_r ? wdata_r[7:0]   : `EMIF_IDLE;
            default:      dout = `EMIF_IDLE;
        endcase
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state    <= S_IDLE;
            busy_o   <= 1'b0;
            done_o   <= 1'b0;
            rdata_o  <= 32'h0;
            addr_r   <= 32'h0;
            wdata_r  <= 32'h0;
            rdata_r  <= 32'h0;
            memsel_r <= 1'b0;
            we_r     <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy_o <= 1'b0;
                    if (start_i) begin
                        addr_r   <= addr_i;
                        wdata_r  <= wdata_i;
                        memsel_r <= memsel_i;
                        we_r     <= we_i;
                        busy_o   <= 1'b1;
                        state    <= S_SEND_MAGIC;
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
                S_SEND_DATA3: state <= S_WAIT_ACK;

                S_WAIT_ACK: begin
                    if (bridge_i == `EMIF_ACK) begin
                        if (we_r) begin
                            done_o <= 1'b1;
                            state  <= S_IDLE;
                        end else begin
                            state <= S_RECV_DATA0;
                        end
                    end
                end

                S_RECV_DATA0: begin
                    rdata_r[31:24] <= bridge_i;
                    state <= S_RECV_DATA1;
                end
                S_RECV_DATA1: begin
                    rdata_r[23:16] <= bridge_i;
                    state <= S_RECV_DATA2;
                end
                S_RECV_DATA2: begin
                    rdata_r[15:8] <= bridge_i;
                    state <= S_RECV_DATA3;
                end
                S_RECV_DATA3: begin
                    rdata_r[7:0] <= bridge_i;
                    rdata_o <= {rdata_r[31:8], bridge_i};
                    done_o  <= 1'b1;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
