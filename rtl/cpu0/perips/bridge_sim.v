`include "../core/defines.v"

module bridge (

    input  wire        clk      ,
    input  wire        rst      ,

    // slave interface
    input  wire [31:0] addr_i   ,
    input  wire [31:0] data_i   ,
    output wire [31:0] data_o   ,
    input  wire        we_i     ,

    input  wire        req_i  ,
    output reg         ack_o  ,

    // interface to Bridge_FPGA
    inout       [15:0] bridge_io
    );


    // State machine
    localparam S_IDLE    = 3'd0;
    localparam S_SEND_A  = 3'd1;
    localparam S_SEND_DH = 3'd2;
    localparam S_SEND_DL = 3'd3;
    localparam S_RECV_DH = 3'd4;
    localparam S_RECV_DL = 3'd5;

    reg  [2:0] state     ;
    reg  [2:0] next_state;

    // Transaction capture registers
    reg [31:0] addr      ;
    reg [31:0] wdata     ;
    reg        we        ; // 1 = write, 0 = read
    reg [31:0] rdata     ; // assembled read data
    reg        mem_sel   ; // 0 = rom, 1 = ram

    // Trigate
    reg [15:0] bridge_in ;
    reg        bridge_oe ;

    assign bridge_io = bridge_oe ? bridge_in : 16'bz;
    
    // State machine
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            state   <= S_SEND_A;
        end else begin
            state   <= next_state;
        end
    end

    // State machine
    always @ (*) begin
        mem_sel = addr[28];
        // ack_o = `False;
        case (state)
            // S_IDLE: begin
            //     if (req_i == `True && addr_i[31:29] == 3'b0) begin // ROM or RAM
            //         next_state = S_SEND_A;
            //     end else next_state = S_IDLE;
            // end

            // S_SEND_A: begin
            //     next_state = (we == `WriteEnable) ? S_SEND_DH : S_RECV_DH;
            // end

            S_SEND_A: begin
                if (req_i == `True && addr_i[31:29] == 3'b0) begin // ROM or RAM
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
            // ack_o   <= `False   ;
            bridge_oe <= `False;
            bridge_in <= `ZeroWord;
        end else begin
            case (state)
                // S_IDLE: begin
                //     bridge_in <= `ZeroWord;
                //     rdata     <= `ZeroWord;
                //     ack_o   <= `False   ;
                //     if (req_i == `True && addr_i[31:29] == 3'b0) begin // ROM or RAM
                //         addr      <= addr_i;
                //         wdata     <= data_i;
                //         we        <= we_i;
                //         bridge_oe <= `True;
                //     end else begin
                //         addr      <= `ZeroWord;
                //         wdata     <= `ZeroWord;
                //         we        <= `WriteDisable;
                //         bridge_oe <= `False;
                //     end
                // end

                // S_SEND_A: begin
                //     bridge_in <= {`MEM_START, we, mem_sel, addr[7:0]};
                //     bridge_oe <= (we == `WriteEnable) ? `True : `False;
                // end

                S_SEND_A: begin
                    rdata     <= `ZeroWord;
                    // ack_o   <= `False   ;
                    if (req_i == `True && addr_i[31:29] == 3'b0) begin // ROM or RAM
                        addr      <= addr_i;
                        wdata     <= data_i;
                        we        <= we_i;
                        bridge_in <= {we_i, `MEM_Start, addr_i[28], addr_i[9:0]};
                        // bridge_oe <= (we_i == `WriteEnable) ? `True : `False;
                        bridge_oe <= `True;
                    end else begin
                        addr      <= `ZeroWord;
                        wdata     <= `ZeroWord;
                        we        <= `WriteDisable;
                        bridge_in <= `ZeroWord;
                        bridge_oe <= `False;
                    end
                end

                S_SEND_DH: begin
                    bridge_in <= wdata[31:16];
                    bridge_oe <= `True;
                end

                S_SEND_DL: begin
                    bridge_in <= wdata[15:0];
                    // ack_o <= `True;
                end

                S_IDLE: begin
                    bridge_oe <= `False;
                end

                S_RECV_DH: begin
                    rdata[31:16] <= bridge_io;
                end

                S_RECV_DL: begin
                    rdata[15:0] <= bridge_io;
                    // ack_o <= `True;
                end
            endcase
        end
    end

    // assign data_o = (ack_o == `False) ? `ZeroWord : rdata;

    assign data_o = (ack_o == `False) ? `ZeroWord : {rdata[31:16], bridge_io};

    // always @(posedge clk) begin
    //     if (rst == `RstEnable) begin
    //         data_o <= `ZeroWord;
    //     end else if (ack_o == `False) begin
    //         data_o <= data_o;
    //     end else begin
    //         data_o <= {rdata[31:16], bridge_io};
    //     end
    // end

    //     always @(posedge clk) begin
    //     if (rst == `RstEnable) begin
    //         data_o <= `ZeroWord;
    //         ack_o <= `False;
    //     end else begin
    //         data_o <= ready ? {rdata[31:16], bridge_io} : data_o;
    //         ack_o <= ready;
    //         // if (ready == `False) begin
    //         //     data_o <= data_o;
    //         // end else begin
    //         //     data_o <= {rdata[31:16], bridge_io};
    //         // end
    //     end
    // end
    
endmodule
