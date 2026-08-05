// Simple I2C master peripheral (slave7 = 0x7000_0000)
//
// Address map (addr_i lower 28 bits):
//   0x0010_0000 : slave address register [6:0], default 0x48
//   0x0020_0000 : output data register [7:0] (write also starts one read transaction)
//   0x0030_0000 : input  data register [7:0] (last received byte)
//   0x0000_0000 : status register
//                 bit0 busy, bit1 done, bit2 ack_write_addr, bit3 ack_ptr, bit4 ack_read_addr
//
// Transaction started by writing OUTPUT register:
//   START -> (slave_addr<<1|0) -> ACK -> 0x00(pointer) -> ACK ->
//   repeated START -> (slave_addr<<1|1) -> ACK -> read 1 byte -> NACK -> STOP
`include "../core/defines.v"

module cpu1_i2c(
    input  wire        clk,
    input  wire        rst,
    input  wire        we_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] data_i,
    output reg  [31:0] data_o,
    output wire        scl_o,
    output wire        sda_o,
    output wire        sda_oe_o,
    input  wire        sda_i
);

    localparam REG_STATUS = 8'h00;
    localparam REG_ADDR   = 8'h10;
    localparam REG_OUT    = 8'h20;
    localparam REG_IN     = 8'h30;

    localparam SCL_HALF = 9'd250;  // 50MHz -> 100kHz
    localparam I2C_TOTAL_STEPS = 7'd80;

    reg [6:0] reg_slave_addr;
    reg [7:0] reg_out_data;
    reg [7:0] reg_in_data;
    reg [4:0] reg_status;
    reg       start_req;

    reg [6:0] i2c_step;
    reg [8:0] i2c_ph_cnt;
    reg [7:0] i2c_rx_byte;
    reg       i2c_active;
    reg       i2c_scl_r, i2c_sda_r, i2c_sda_oe_r;

    wire [7:0] reg_sel = addr_i[23:16];
    wire [7:0] wr_addr = {reg_slave_addr, 1'b0};
    wire [7:0] rd_addr = {reg_slave_addr, 1'b1};

    always @ (*) begin
        case (i2c_step)
            7'd0:  begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
            7'd1:  begin i2c_scl_r=1; i2c_sda_r=0; i2c_sda_oe_r=1; end
            7'd2:  begin i2c_scl_r=0; i2c_sda_r=wr_addr[7]; i2c_sda_oe_r=1; end
            7'd3:  begin i2c_scl_r=1; i2c_sda_r=wr_addr[7]; i2c_sda_oe_r=1; end
            7'd4:  begin i2c_scl_r=0; i2c_sda_r=wr_addr[6]; i2c_sda_oe_r=1; end
            7'd5:  begin i2c_scl_r=1; i2c_sda_r=wr_addr[6]; i2c_sda_oe_r=1; end
            7'd6:  begin i2c_scl_r=0; i2c_sda_r=wr_addr[5]; i2c_sda_oe_r=1; end
            7'd7:  begin i2c_scl_r=1; i2c_sda_r=wr_addr[5]; i2c_sda_oe_r=1; end
            7'd8:  begin i2c_scl_r=0; i2c_sda_r=wr_addr[4]; i2c_sda_oe_r=1; end
            7'd9:  begin i2c_scl_r=1; i2c_sda_r=wr_addr[4]; i2c_sda_oe_r=1; end
            7'd10: begin i2c_scl_r=0; i2c_sda_r=wr_addr[3]; i2c_sda_oe_r=1; end
            7'd11: begin i2c_scl_r=1; i2c_sda_r=wr_addr[3]; i2c_sda_oe_r=1; end
            7'd12: begin i2c_scl_r=0; i2c_sda_r=wr_addr[2]; i2c_sda_oe_r=1; end
            7'd13: begin i2c_scl_r=1; i2c_sda_r=wr_addr[2]; i2c_sda_oe_r=1; end
            7'd14: begin i2c_scl_r=0; i2c_sda_r=wr_addr[1]; i2c_sda_oe_r=1; end
            7'd15: begin i2c_scl_r=1; i2c_sda_r=wr_addr[1]; i2c_sda_oe_r=1; end
            7'd16: begin i2c_scl_r=0; i2c_sda_r=wr_addr[0]; i2c_sda_oe_r=1; end
            7'd17: begin i2c_scl_r=1; i2c_sda_r=wr_addr[0]; i2c_sda_oe_r=1; end
            7'd18: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd19: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd20: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd21: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd22: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd23: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd24: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd25: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd26: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd27: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd28: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd29: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd30: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd31: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd32: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd33: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd34: begin i2c_scl_r=0; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd35: begin i2c_scl_r=1; i2c_sda_r=1'b0; i2c_sda_oe_r=1; end
            7'd36: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd37: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd38: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=1; end
            7'd39: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
            7'd40: begin i2c_scl_r=1; i2c_sda_r=0; i2c_sda_oe_r=1; end
            7'd41: begin i2c_scl_r=0; i2c_sda_r=rd_addr[7]; i2c_sda_oe_r=1; end
            7'd42: begin i2c_scl_r=1; i2c_sda_r=rd_addr[7]; i2c_sda_oe_r=1; end
            7'd43: begin i2c_scl_r=0; i2c_sda_r=rd_addr[6]; i2c_sda_oe_r=1; end
            7'd44: begin i2c_scl_r=1; i2c_sda_r=rd_addr[6]; i2c_sda_oe_r=1; end
            7'd45: begin i2c_scl_r=0; i2c_sda_r=rd_addr[5]; i2c_sda_oe_r=1; end
            7'd46: begin i2c_scl_r=1; i2c_sda_r=rd_addr[5]; i2c_sda_oe_r=1; end
            7'd47: begin i2c_scl_r=0; i2c_sda_r=rd_addr[4]; i2c_sda_oe_r=1; end
            7'd48: begin i2c_scl_r=1; i2c_sda_r=rd_addr[4]; i2c_sda_oe_r=1; end
            7'd49: begin i2c_scl_r=0; i2c_sda_r=rd_addr[3]; i2c_sda_oe_r=1; end
            7'd50: begin i2c_scl_r=1; i2c_sda_r=rd_addr[3]; i2c_sda_oe_r=1; end
            7'd51: begin i2c_scl_r=0; i2c_sda_r=rd_addr[2]; i2c_sda_oe_r=1; end
            7'd52: begin i2c_scl_r=1; i2c_sda_r=rd_addr[2]; i2c_sda_oe_r=1; end
            7'd53: begin i2c_scl_r=0; i2c_sda_r=rd_addr[1]; i2c_sda_oe_r=1; end
            7'd54: begin i2c_scl_r=1; i2c_sda_r=rd_addr[1]; i2c_sda_oe_r=1; end
            7'd55: begin i2c_scl_r=0; i2c_sda_r=rd_addr[0]; i2c_sda_oe_r=1; end
            7'd56: begin i2c_scl_r=1; i2c_sda_r=rd_addr[0]; i2c_sda_oe_r=1; end
            7'd57: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd58: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd59: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd60: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd61: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd62: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd63: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd64: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd65: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd66: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd67: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd68: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd69: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd70: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd71: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd72: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd73: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd74: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd75: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=1; end
            7'd76: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
            7'd77: begin i2c_scl_r=0; i2c_sda_r=0; i2c_sda_oe_r=1; end
            7'd78: begin i2c_scl_r=1; i2c_sda_r=0; i2c_sda_oe_r=1; end
            7'd79: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
            default: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
        endcase
    end

    assign scl_o    = i2c_active ? i2c_scl_r : 1'b1;
    assign sda_o    = i2c_active ? i2c_sda_r : 1'b1;
    assign sda_oe_o = i2c_active ? i2c_sda_oe_r : 1'b0;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            reg_slave_addr <= 7'h48;
            reg_out_data   <= 8'h00;
            reg_in_data    <= 8'h00;
            reg_status     <= 5'b0;
            start_req      <= 1'b0;
            i2c_step       <= 7'h0;
            i2c_ph_cnt     <= 9'h0;
            i2c_rx_byte    <= 8'h0;
            i2c_active     <= 1'b0;
        end else begin
            start_req <= 1'b0;
            reg_status[1] <= 1'b0; // done pulse

            if (we_i == `WriteEnable) begin
                case (reg_sel)
                    REG_ADDR: begin
                        reg_slave_addr <= data_i[6:0];
                    end
                    REG_OUT: begin
                        reg_out_data <= data_i[7:0];
                        start_req    <= 1'b1;
                    end
                    REG_STATUS: begin
                        if (data_i[1]) begin
                            reg_status[4:2] <= 3'b000;
                        end
                    end
                    default: ;
                endcase
            end

            if (!i2c_active) begin
                if (start_req) begin
                    i2c_active <= 1'b1;
                    i2c_step   <= 7'h0;
                    i2c_ph_cnt <= 9'h0;
                    i2c_rx_byte <= 8'h0;
                    reg_status[0] <= 1'b1; // busy
                    reg_status[4:2] <= 3'b000;
                end
            end else begin
                if (i2c_active && i2c_step[0] == 1'b0 &&
                    i2c_step >= 7'd60 && i2c_step <= 7'd74 &&
                    i2c_ph_cnt == (SCL_HALF >> 1)) begin
                    case (i2c_step)
                        7'd60: i2c_rx_byte[7] <= sda_i;
                        7'd62: i2c_rx_byte[6] <= sda_i;
                        7'd64: i2c_rx_byte[5] <= sda_i;
                        7'd66: i2c_rx_byte[4] <= sda_i;
                        7'd68: i2c_rx_byte[3] <= sda_i;
                        7'd70: i2c_rx_byte[2] <= sda_i;
                        7'd72: i2c_rx_byte[1] <= sda_i;
                        7'd74: i2c_rx_byte[0] <= sda_i;
                        default: ;
                    endcase
                end

                if (i2c_ph_cnt == (SCL_HALF >> 1)) begin
                    if (i2c_step == 7'd19) begin
                        reg_status[2] <= ~sda_i;
                    end else if (i2c_step == 7'd37) begin
                        reg_status[3] <= ~sda_i;
                    end else if (i2c_step == 7'd58) begin
                        reg_status[4] <= ~sda_i;
                    end
                end

                if (i2c_ph_cnt >= SCL_HALF - 1) begin
                    i2c_ph_cnt <= 9'h0;
                    if (i2c_step >= I2C_TOTAL_STEPS) begin
                        i2c_active   <= 1'b0;
                        reg_status[0] <= 1'b0;
                        reg_status[1] <= 1'b1;
                        reg_in_data   <= i2c_rx_byte;
                    end else begin
                        i2c_step <= i2c_step + 1'b1;
                    end
                end else begin
                    i2c_ph_cnt <= i2c_ph_cnt + 1'b1;
                end
            end
        end
    end

    always @ (*) begin
        case (reg_sel)
            REG_STATUS: data_o = {27'h0, reg_status};
            REG_ADDR:   data_o = {25'h0, reg_slave_addr};
            REG_OUT:    data_o = {24'h0, reg_out_data};
            REG_IN:     data_o = {24'h0, reg_in_data};
            default:    data_o = 32'h0;
        endcase
    end

endmodule
