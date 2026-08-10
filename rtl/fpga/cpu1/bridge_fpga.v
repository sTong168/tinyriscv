`include "../core/defines.v"

module bridge_fpga (

input        clk      ,
input        rst      ,

inout [15:0] bridge_io
);

localparam S_RECV_A  = 3'd0;
localparam S_RECV_DH = 3'd1;
localparam S_RECV_DL = 3'd2;
localparam S_SEND_DH = 3'd3;
localparam S_SEND_DL = 3'd4;

reg   [2:0] state     ;
reg   [2:0] next_state;

reg  [15:0] addr      ;
reg  [31:0] wdata     ;
wire [31:0] rdata     ;

reg  [15:0] bridge_in ;
reg         bridge_oe ;

assign bridge_io = bridge_oe ? bridge_in : 16'bz;

wire [`MemBus] ram_data_out;
wire [`MemBus] rom_data_out;

wire           we          ;
wire           mem_sel     ;
wire           ram_we      ;
wire           rom_we      ;

always @ (posedge clk) begin
    if (rst == `RstEnable) begin
        state   <= S_RECV_A;
    end else begin
        state   <= next_state;
    end
end

always @ (*) begin
    bridge_in = 16'h0;
    case (state)
        S_RECV_A: begin
            if (bridge_io[14:11] == `MEM_Start) begin
                next_state = (bridge_io[15] == `WriteEnable) ? S_RECV_DH : S_SEND_DH;
            end else next_state = S_RECV_A;
        end

        S_RECV_DH: begin
            next_state = S_RECV_DL;
        end

        S_RECV_DL: begin
            next_state = S_RECV_A;
        end

        S_SEND_DH: begin
            next_state = S_SEND_DL;
            bridge_in = rdata[31:16];
        end

        S_SEND_DL: begin
            next_state = S_RECV_A;
            bridge_in = rdata[15:0];
        end

        default: begin
            next_state = S_RECV_A ;
            bridge_in  = 16'h0;
        end
    endcase
end

always @ (posedge clk) begin
    if (rst == `RstEnable) begin
        addr      <= 16'b0;
        wdata     <= `ZeroWord;
        bridge_oe <= `False;
    end else begin
        case (state)
            S_RECV_A: begin
                wdata <= `ZeroWord;
                if (bridge_io[14:11] == `MEM_Start) begin
                    addr    <= bridge_io;
                    bridge_oe <= (bridge_io[15] == `WriteDisable) ? `True : `False;
                end else begin
                    addr    <= `ZeroWord;
                end
            end

            S_RECV_DH: begin
                wdata[31:16] <= bridge_io;
            end

            S_RECV_DL: begin
                wdata[15:0] <= bridge_io;
                bridge_oe <= `False;
            end

            S_SEND_DL: begin
                bridge_oe <= `False;
            end
        endcase
    end
end

assign we      = addr[15];
assign mem_sel = addr[10];
assign rom_we  = (state != S_RECV_A) ? `WriteDisable : (mem_sel == `SEL_ROM) ? we : `WriteDisable;
assign ram_we  = (state != S_RECV_A) ? `WriteDisable : (mem_sel == `SEL_RAM) ? we : `WriteDisable;
assign rdata   = (mem_sel == `SEL_ROM) ? rom_data_out : ram_data_out;

rom u_rom(
.clk(clk),
.rst(rst),
.we_i(rom_we),
.addr_i({22'b0, addr[9:0]}),
.data_i(wdata),
.data_o(rom_data_out)
);

ram u_ram(
.clk(clk),
.rst(rst),
.we_i(ram_we),
.addr_i({22'b0, addr[9:0]}),
.data_i(wdata),
.data_o(ram_data_out)
);

endmodule
