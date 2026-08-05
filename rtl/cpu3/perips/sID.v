`include "../core/defines.v"

// sID custom instruction peripheral.
// It sends the student ID as ASCII characters through UART TXDATA.
module cpu3_sID(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output reg         done,
    output reg         req,
    output reg         we,
    output reg [31:0]  addr,
    output reg [31:0]  wdata,
    input  wire [31:0] rdata,
    input  wire        ack_i
    );

    // Student ID from the migrated new design: 2024211095.
    wire [7:0] ascii [0:9];
    assign ascii[0] = 8'h32;
    assign ascii[1] = 8'h30;
    assign ascii[2] = 8'h32;
    assign ascii[3] = 8'h34;
    assign ascii[4] = 8'h32;
    assign ascii[5] = 8'h31;
    assign ascii[6] = 8'h31;
    assign ascii[7] = 8'h30;
    assign ascii[8] = 8'h39;
    assign ascii[9] = 8'h35;

    localparam [2:0] IDLE      = 3'd0;
    localparam [2:0] SEND_BYTE = 3'd1;
    localparam [2:0] SEND_WAIT = 3'd2;
    localparam [2:0] DELAY     = 3'd3;
    localparam [2:0] LOCKED    = 3'd4;

    reg [2:0]  state;
    reg [3:0]  byte_cnt;
    reg [15:0] delay_cnt;
    reg        started;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state     <= IDLE;
            byte_cnt  <= 4'd0;
            delay_cnt <= 16'd0;
            req       <= 1'b0;
            we        <= 1'b0;
            addr      <= 32'd0;
            wdata     <= 32'd0;
            done      <= 1'b0;
            started   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    req <= 1'b0;
                    we  <= 1'b0;
                    if (!started && start) begin
                        started   <= 1'b1;
                        state     <= SEND_BYTE;
                        delay_cnt <= 16'd0;
                    end
                    if (!start)
                        started <= 1'b0;
                end

                SEND_BYTE: begin
                    req       <= 1'b1;
                    we        <= 1'b1;
                    // initial UART TXDATA is at offset 0x0c; new uses 0x04.
                    addr      <= 32'h3000_000c;
                    wdata     <= {24'h0, ascii[byte_cnt]};
                    delay_cnt <= 16'd0;
                    state     <= SEND_WAIT;
                end

                SEND_WAIT: begin
                    // Hold the transaction until RIB actually accepts it.
                    // An external ROM/RAM access may occupy the arbiter for
                    // several cycles when this request is first presented.
                    if (ack_i) begin
                        req       <= 1'b0;
                        we        <= 1'b0;
                        delay_cnt <= 16'd0;
                        state     <= DELAY;
                    end else begin
                        req <= 1'b1;
                        we  <= 1'b1;
                    end
                end

                DELAY: begin
                    req       <= 1'b0;
                    we        <= 1'b0;
                    delay_cnt <= delay_cnt + 1'b1;
                    if (delay_cnt == 16'd5000) begin
                        if (byte_cnt == 4'd9) begin
                            state <= LOCKED;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                            state    <= SEND_BYTE;
                        end
                    end
                end

                LOCKED: begin
                    req  <= 1'b0;
                    we   <= 1'b0;
                    done <= 1'b1;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
