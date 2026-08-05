`include "../core/defines.v"

// LM75 I2C master. A high-level rT request starts one complete read and
// remains active until done_o is asserted. The latest byte is also exposed
// through RIB address offset 0x20 at the 0x4... address region.
module cpu3_i2c_master(
    input wire clk,
    input wire rst,
    input wire we_i,
    input wire[`MemAddrBus] addr_i,
    input wire[`MemBus] data_i,
    output reg[`MemBus] data_o,
    input wire scl_in,
    output wire scl_o,
    output wire scl_oe,
    input wire sda_in,
    output wire sda_o,
    output wire sda_oe,
    input wire start_i,
    output wire done_o,
    output wire busy_o,
    output wire[7:0] temp_data_o
    );

    localparam [7:0] DEVICE_READ = 8'b1001_0001;
    localparam [3:0] IDLE  = 4'd0;
    localparam [3:0] START = 4'd1;
    localparam [3:0] ADDR  = 4'd2;
    localparam [3:0] ACK1  = 4'd3;
    localparam [3:0] DATA1 = 4'd4;
    localparam [3:0] ACK2  = 4'd5;
    localparam [3:0] DATA2 = 4'd6;
    localparam [3:0] NACK  = 4'd7;
    localparam [3:0] STOP  = 4'd8;

    reg [7:0] cnt_delay;
    reg [2:0] cnt;
    reg scl_r;
    reg [3:0] cstate;
    reg [7:0] db_r;
    reg [7:0] read_data;
    reg [7:0] latched_temp;
    reg sda_r;
    reg sda_link;
    reg [3:0] num;
    reg start_seen;
    reg done_r;

    wire scl_pos = (cnt == 3'd0);
    wire scl_high = (cnt == 3'd1);
    wire scl_neg = (cnt == 3'd2);
    wire scl_low = (cnt == 3'd3);

    // The current controller drives SCL continuously; scl_in is provided for
    // pad-ring compatibility without changing the existing clock behavior.
    assign scl_o = scl_r;
    assign scl_oe = 1'b1;
    assign sda_o = sda_r;
    assign sda_oe = sda_link;
    assign done_o = done_r;
    assign busy_o = (cstate != IDLE);
    assign temp_data_o = latched_temp;

    always @(posedge clk or negedge rst) begin
        if (!rst)
            cnt_delay <= 8'd0;
        else if (cnt_delay == 8'd199)
            cnt_delay <= 8'd0;
        else
            cnt_delay <= cnt_delay + 1'b1;
    end

    always @(posedge clk or negedge rst) begin
        if (!rst)
            cnt <= 3'd5;
        else begin
            case (cnt_delay)
                8'd49:  cnt <= 3'd1;
                8'd99:  cnt <= 3'd2;
                8'd149: cnt <= 3'd3;
                8'd199: cnt <= 3'd0;
                default: cnt <= 3'd5;
            endcase
        end
    end

    always @(posedge clk or negedge rst) begin
        if (!rst)
            scl_r <= 1'b0;
        else if (scl_pos)
            scl_r <= 1'b1;
        else if (scl_neg)
            scl_r <= 1'b0;
    end

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            cstate <= IDLE;
            db_r <= 8'h00;
            read_data <= 8'h00;
            latched_temp <= 8'h00;
            sda_r <= 1'b1;
            sda_link <= 1'b0;
            num <= 4'd0;
            start_seen <= 1'b0;
            done_r <= 1'b0;
        end else begin
            case (cstate)
                IDLE: begin
                    sda_link <= 1'b1;
                    sda_r <= 1'b1;
                    if (!start_i) begin
                        start_seen <= 1'b0;
                    end else if (!start_seen) begin
                        start_seen <= 1'b1;
                        done_r <= 1'b0;
                        db_r <= DEVICE_READ;
                        read_data <= 8'h00;
                        num <= 4'd0;
                        cstate <= START;
                    end
                end

                START: begin
                    if (scl_high) begin
                        sda_link <= 1'b1;
                        sda_r <= 1'b0;
                        cstate <= ADDR;
                        num <= 4'd0;
                    end
                end

                ADDR: begin
                    if (scl_low) begin
                        if (num == 4'd8) begin
                            num <= 4'd0;
                            sda_r <= 1'b1;
                            sda_link <= 1'b0;
                            cstate <= ACK1;
                        end else begin
                            num <= num + 1'b1;
                            case (num)
                                4'd0: sda_r <= db_r[7];
                                4'd1: sda_r <= db_r[6];
                                4'd2: sda_r <= db_r[5];
                                4'd3: sda_r <= db_r[4];
                                4'd4: sda_r <= db_r[3];
                                4'd5: sda_r <= db_r[2];
                                4'd6: sda_r <= db_r[1];
                                4'd7: sda_r <= db_r[0];
                                default: sda_r <= 1'b1;
                            endcase
                        end
                    end
                end

                ACK1: begin
                    if (scl_neg)
                        cstate <= DATA1;
                end

                DATA1: begin
                    if (scl_high) begin
                        num <= num + 1'b1;
                        case (num)
                            // LM75 data is sign/integer/fraction. Drop
                            // bit 15 and keep bits 14:8 here.
                            4'd1: read_data[7] <= sda_in;
                            4'd2: read_data[6] <= sda_in;
                            4'd3: read_data[5] <= sda_in;
                            4'd4: read_data[4] <= sda_in;
                            4'd5: read_data[3] <= sda_in;
                            4'd6: read_data[2] <= sda_in;
                            4'd7: read_data[1] <= sda_in;
                            default: begin end
                        endcase
                    end else if (scl_neg && (num == 4'd8)) begin
                        num <= 4'd0;
                        sda_link <= 1'b1;
                        sda_r <= 1'b1;
                        cstate <= ACK2;
                    end
                end

                ACK2: begin
                    if (scl_low) begin
                        sda_r <= 1'b0;
                    end else if (scl_neg) begin
                        cstate <= DATA2;
                        sda_link <= 1'b0;
                        sda_r <= 1'b1;
                    end
                end

                DATA2: begin
                    if (scl_high) begin
                        num <= num + 1'b1;
                        if (num == 4'd0)
                            // The next bit is bit 7 of the 16-bit LM75 word.
                            read_data[0] <= sda_in;
                    end else if (scl_low && (num == 4'd8)) begin
                        num <= 4'd0;
                        sda_link <= 1'b1;
                        sda_r <= 1'b1;
                        cstate <= NACK;
                    end
                end

                NACK: begin
                    if (scl_low) begin
                        // NACK the second byte by releasing SDA before STOP.
                        sda_link <= 1'b0;
                        sda_r <= 1'b1;
                        latched_temp <= read_data;
                        cstate <= STOP;
                    end
                end

                STOP: begin
                    if (scl_high) begin
                        sda_r <= 1'b1;
                        cstate <= IDLE;
                        done_r <= 1'b1;
                    end
                end

                default: cstate <= IDLE;
            endcase
        end
    end

    always @(*) begin
        data_o = `ZeroWord;
        if (addr_i[7:0] == 8'h20)
            data_o = {24'h0, latched_temp};
    end

endmodule
