`include "../../shared/defines.v"

module cpu1_bridge (

    input  wire        clk      ,
    input  wire        rst      ,

    // slave interface
    input  wire [31:0] addr_i   ,
    input  wire [31:0] data_i   ,
    output wire [31:0] data_o   ,
    input  wire        we_i     ,

    input  wire        req_i  ,
    output reg         ack_o  ,

    // pad-style 16-bit half-duplex (assembled to inout at chip/FPGA top)
    output reg  [15:0] bridge_o,
    output reg         bridge_oe,
    input  wire [15:0] bridge_in
    );

    localparam S_IDLE    = 3'd0;
    localparam S_SEND_A  = 3'd1;
    localparam S_SEND_DH = 3'd2;
    localparam S_SEND_DL = 3'd3;
    localparam S_RECV_DH = 3'd4;
    localparam S_RECV_DL = 3'd5;

    reg  [2:0] state     ;
    reg  [2:0] next_state;

    reg [31:0] addr      ;
    reg [31:0] wdata     ;
    reg        we        ;
    reg [31:0] rdata     ;
    reg        mem_sel   ;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state   <= S_SEND_A;
        end else begin
            state   <= next_state;
        end
    end

    always @ (*) begin
        mem_sel = addr[28];
        case (state)
            S_SEND_A: begin
                if (req_i == `True && addr_i[31:29] == 3'b0) begin
                    next_state = (we_i == `WriteEnable) ? S_SEND_DH : S_IDLE;
                end else next_state = S_SEND_A;
                ack_o = `False;
            end

            S_SEND_DH: begin
                next_state = S_SEND_DL;
                ack_o = `False;
            end

            S_SEND_DL: begin
                next_state = S_SEND_A;
                ack_o = `True;
            end

            S_IDLE: begin
                next_state = S_RECV_DH;
                ack_o = `False;
            end

            S_RECV_DH: begin
                next_state = S_RECV_DL;
                ack_o = `False;
            end

            S_RECV_DL: begin
                next_state = S_SEND_A;
                ack_o = `True;
            end

            default: begin
                next_state = S_SEND_A;
                ack_o = `False;
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            addr      <= `ZeroWord;
            wdata     <= `ZeroWord;
            we        <= `WriteDisable;
            rdata     <= `ZeroWord;
            bridge_oe <= `False;
            bridge_o  <= 16'h0;
        end else begin
            case (state)
                S_SEND_A: begin
                    rdata     <= `ZeroWord;
                    if (req_i == `True && addr_i[31:29] == 3'b0) begin
                        addr      <= addr_i;
                        wdata     <= data_i;
                        we        <= we_i;
                        bridge_o  <= {we_i, `MEM_Start, addr_i[28], addr_i[9:0]};
                        bridge_oe <= `True;
                    end else begin
                        addr      <= `ZeroWord;
                        wdata     <= `ZeroWord;
                        we        <= `WriteDisable;
                        bridge_o  <= 16'h0;
                        bridge_oe <= `False;
                    end
                end

                S_SEND_DH: begin
                    bridge_o  <= wdata[31:16];
                    bridge_oe <= `True;
                end

                S_SEND_DL: begin
                    bridge_o  <= wdata[15:0];
                end

                S_IDLE: begin
                    bridge_oe <= `False;
                end

                S_RECV_DH: begin
                    rdata[31:16] <= bridge_in;
                end

                S_RECV_DL: begin
                    rdata[15:0] <= bridge_in;
                end
            endcase
        end
    end

    assign data_o = (ack_o == `False) ? `ZeroWord : {rdata[31:16], bridge_in};

endmodule
