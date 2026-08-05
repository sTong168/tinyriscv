`timescale 1ns / 1ps

// Submit the low byte of an IF operand through UART TXDATA. The SoC selects
// UART hex mode for this master, so the byte is transmitted as two ASCII
// hexadecimal characters, matching the RT/Temp output format.
module cpu3_send_if(
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire       ack_i,
    input  wire [7:0] byte_data,
    output reg        done,
    output reg        req,
    output reg        we,
    output reg [31:0] addr,
    output reg [31:0] wdata
    );

    localparam [2:0] IDLE       = 3'd0;
    localparam [2:0] SEND_BYTE  = 3'd1;
    localparam [2:0] SEND_WAIT  = 3'd2;
    localparam [2:0] SEND_DELAY = 3'd3;
    localparam [2:0] LOCKED     = 3'd4;

    reg [2:0]  state;
    reg [15:0] delay_cnt;
    reg        started;
    reg [7:0]  latched_byte;

    always @(posedge clk) begin
        if (!rst) begin
            state        <= IDLE;
            delay_cnt    <= 16'd0;
            req          <= 1'b0;
            we           <= 1'b0;
            addr         <= 32'd0;
            wdata        <= 32'd0;
            done         <= 1'b0;
            started      <= 1'b0;
            latched_byte <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    req <= 1'b0;
                    we  <= 1'b0;
                    if (!started && start) begin
                        started      <= 1'b1;
                        state        <= SEND_BYTE;
                        delay_cnt    <= 16'd0;
                        latched_byte <= byte_data;
                    end
                end

                SEND_BYTE: begin
                    req       <= 1'b1;
                    we        <= 1'b1;
                    // initial UART TXDATA is mapped at offset 0x0c. The SoC
                    // enables UART hex mode for this write.
                    addr      <= 32'h3000_000c;
                    wdata     <= {24'h0, latched_byte};
                    delay_cnt <= 16'd0;
                    state     <= SEND_WAIT;
                end

                SEND_WAIT: begin
                    // The RIB can be busy with an external fetch. Keep the
                    // write asserted until the selected slave acknowledges it.
                    req       <= 1'b1;
                    we        <= 1'b1;
                    if (ack_i) begin
                        req       <= 1'b0;
                        we        <= 1'b0;
                        delay_cnt <= 16'd0;
                        state     <= SEND_DELAY;
                    end
                end

                SEND_DELAY: begin
                    req       <= 1'b0;
                    we        <= 1'b0;
                    delay_cnt <= delay_cnt + 1'b1;
                    // Hex mode emits two UART bytes; allow both to finish.
                    if (delay_cnt == 16'd10000) begin
                        state <= LOCKED;
                    end
                end

                LOCKED: begin
                    req  <= 1'b0;
                    we   <= 1'b0;
                    done <= 1'b1;
                    // Hold completion until reset. The CPU may only assert
                    // start for a few cycles while waiting in the IF EX
                    // stage, so clearing done based on start can lose the
                    // completion handshake.
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
