// =============================================================================
// cpu1_i2c - improved MMIO I2C master (drop-in ports / module name)
// Desktop preview only; does NOT replace project RTL until you choose to.
//
// Address map (CPU view, slave7 @ 0x7xxx_xxxx; decode uses addr[23:16]):
//   0x7000_0000  STATUS  RO
//                  [0] busy
//                  [1] done   (1-cycle pulse when a command finishes)
//                  [2] ack_aw   (saw ACK after Addr+W)
//                  [3] ack_byte (saw ACK after TX data / pointer)
//                  [4] ack_ar   (saw ACK after Addr+R)
//                  [5] err      (NACK seen on an expected ACK slot)
//   0x7010_0000  ADDR    RW  slave address [6:0], reset = 0x48
//   0x7020_0000  TX      RW  outbound data byte (pointer or write payload)
//                            writing TX alone does NOT start a transfer
//   0x7030_0000  RX0     RO  first received byte (LM75 Temp MSB / integer C)
//   0x7040_0000  CMD     WO  write starts one command (see below)
//   0x7050_0000  RX1     RO  second received byte (LM75 Temp LSB / fraction)
//
// CMD values (data_i[7:0]):
//   0  WRITE1   START + AW + TX + STOP
//   1  READ1    START + AR + RX0 + NACK + STOP
//   2  READ2    START + AR + RX0 + ACK + RX1 + NACK + STOP
//   3  WR_RD2   START + AW + TX + Sr + AR + RX0 + ACK + RX1 + NACK + STOP
//               (recommended LM75 Temp / multi-byte register read)
//   4  WR_RD1   START + AW + TX + Sr + AR + RX0 + NACK + STOP
//               (old cpu1 behavior: pointer then 1-byte read)
//
// Software examples (after programming):
//   // LM75 read temperature (integer in RX0)
//   sw  ADDR, 0x48
//   sw  TX,   0x00          // pointer = Temp
//   sw  CMD,  3             // WR_RD2
//   poll STATUS until !busy; then lw RX0 / RX1
//
//   // LM75 write Config (example)
//   sw  TX,   0x01          // need 2-byte write: use WRITE1 twice or extend later
//   // For single-byte write to a device that only needs AW+data:
//   sw  TX,   <byte>
//   sw  CMD,  0             // WRITE1
//
// Pin contract matches current SoC OD remap:
//   scl_o high = release SCL, low = drive SCL low
//   sda: oe=1 & sda=0 drives low; oe=0 releases
// =============================================================================
`include "../../shared/defines.v"

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
    localparam REG_TX     = 8'h20;
    localparam REG_RX0    = 8'h30;
    localparam REG_CMD    = 8'h40;
    localparam REG_RX1    = 8'h50;

    localparam CMD_WRITE1 = 8'd0;
    localparam CMD_READ1  = 8'd1;
    localparam CMD_READ2  = 8'd2;
    localparam CMD_WR_RD2 = 8'd3;
    localparam CMD_WR_RD1 = 8'd4;

    // 50MHz -> ~100kHz (half period = 250 cycles)
    localparam HALF_DIV = 16'd250;

    localparam S_IDLE      = 5'd0;
    localparam S_START     = 5'd1;
    localparam S_SEND_AW   = 5'd2;
    localparam S_ACK_AW    = 5'd3;
    localparam S_SEND_TX   = 5'd4;
    localparam S_ACK_TX    = 5'd5;
    localparam S_SR_PREP   = 5'd6;
    localparam S_SR        = 5'd7;
    localparam S_SEND_AR   = 5'd8;
    localparam S_ACK_AR    = 5'd9;
    localparam S_RECV0     = 5'd10;
    localparam S_ACK_RX0   = 5'd11;
    localparam S_RECV1     = 5'd12;
    localparam S_NACK      = 5'd13;
    localparam S_STOP1     = 5'd14;
    localparam S_STOP2     = 5'd15;
    localparam S_STOP3     = 5'd16;
    localparam S_DONE      = 5'd17;

    wire [7:0] reg_sel = addr_i[23:16];

    reg [6:0]  reg_slave_addr;
    reg [7:0]  reg_tx;
    reg [7:0]  reg_rx0;
    reg [7:0]  reg_rx1;
    reg        busy;
    reg        done_pulse;
    reg        ack_aw;
    reg        ack_byte;
    reg        ack_ar;
    reg        err;
    reg [7:0]  cmd_latched;
    reg        start_req;

    reg [4:0]  state;
    reg [15:0] tick_cnt;
    wire       tick = (tick_cnt == HALF_DIV);

    reg        scl_r;
    reg        sda_r;
    reg        sda_oe_r;
    reg [3:0]  bit_cnt;
    reg [7:0]  shift;
    reg [7:0]  rx_shift;
    reg        want_read;
    reg        want_tx;
    reg        want_sr;
    reg        want_rx1;
    reg        phase_low;   // 1 = drive/setup on low half, 0 = sample on high half

    wire [7:0] aw_byte = {reg_slave_addr, 1'b0};
    wire [7:0] ar_byte = {reg_slave_addr, 1'b1};

    assign scl_o    = scl_r;
    assign sda_o    = sda_r;
    assign sda_oe_o = sda_oe_r;

    // tick generator
    always @(posedge clk) begin
        if (rst == `RstEnable)
            tick_cnt <= 16'd0;
        else if (tick)
            tick_cnt <= 16'd0;
        else
            tick_cnt <= tick_cnt + 16'd1;
    end

    // register writes + command latch
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            reg_slave_addr <= 7'h48;
            reg_tx         <= 8'h00;
            start_req      <= 1'b0;
            cmd_latched    <= CMD_WR_RD2;
        end else begin
            start_req <= 1'b0;
            if (we_i == `WriteEnable && !busy) begin
                case (reg_sel)
                    REG_ADDR: reg_slave_addr <= data_i[6:0];
                    REG_TX:   reg_tx         <= data_i[7:0];
                    REG_CMD: begin
                        cmd_latched <= data_i[7:0];
                        start_req   <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // MMIO read mux
    always @(*) begin
        case (reg_sel)
            REG_STATUS: data_o = {26'h0, err, ack_ar, ack_byte, ack_aw, done_pulse, busy};
            REG_ADDR:   data_o = {25'h0, reg_slave_addr};
            REG_TX:     data_o = {24'h0, reg_tx};
            REG_RX0:    data_o = {24'h0, reg_rx0};
            REG_CMD:    data_o = {24'h0, cmd_latched};
            REG_RX1:    data_o = {24'h0, reg_rx1};
            default:    data_o = 32'h0;
        endcase
    end

    // main bit-bang FSM (advances on tick)
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            done_pulse <= 1'b0;
            ack_aw     <= 1'b0;
            ack_byte   <= 1'b0;
            ack_ar     <= 1'b0;
            err        <= 1'b0;
            reg_rx0    <= 8'h00;
            reg_rx1    <= 8'h00;
            scl_r      <= 1'b1;
            sda_r      <= 1'b1;
            sda_oe_r   <= 1'b0;
            bit_cnt    <= 4'd0;
            shift      <= 8'h00;
            rx_shift   <= 8'h00;
            want_read  <= 1'b0;
            want_tx    <= 1'b0;
            want_sr    <= 1'b0;
            want_rx1   <= 1'b0;
            phase_low  <= 1'b1;
        end else begin
            done_pulse <= 1'b0;

            if (state == S_IDLE) begin
                scl_r    <= 1'b1;
                sda_r    <= 1'b1;
                sda_oe_r <= 1'b0;
                if (start_req) begin
                    busy     <= 1'b1;
                    ack_aw   <= 1'b0;
                    ack_byte <= 1'b0;
                    ack_ar   <= 1'b0;
                    err      <= 1'b0;
                    reg_rx0  <= 8'h00;
                    reg_rx1  <= 8'h00;
                    bit_cnt  <= 4'd0;
                    phase_low<= 1'b1;

                    case (cmd_latched)
                        CMD_WRITE1: begin
                            want_tx   <= 1'b1;
                            want_sr   <= 1'b0;
                            want_read <= 1'b0;
                            want_rx1  <= 1'b0;
                        end
                        CMD_READ1: begin
                            want_tx   <= 1'b0;
                            want_sr   <= 1'b0;
                            want_read <= 1'b1;
                            want_rx1  <= 1'b0;
                        end
                        CMD_READ2: begin
                            want_tx   <= 1'b0;
                            want_sr   <= 1'b0;
                            want_read <= 1'b1;
                            want_rx1  <= 1'b1;
                        end
                        CMD_WR_RD1: begin
                            want_tx   <= 1'b1;
                            want_sr   <= 1'b1;
                            want_read <= 1'b1;
                            want_rx1  <= 1'b0;
                        end
                        default: begin // CMD_WR_RD2
                            want_tx   <= 1'b1;
                            want_sr   <= 1'b1;
                            want_read <= 1'b1;
                            want_rx1  <= 1'b1;
                        end
                    endcase
                    state <= S_START;
                end
            end else if (tick) begin
                case (state)
                    // START: SDA falls while SCL high
                    S_START: begin
                        if (phase_low) begin
                            // ensure bus free then pull SDA
                            scl_r    <= 1'b1;
                            sda_r    <= 1'b0;
                            sda_oe_r <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r     <= 1'b0; // pull clock for first bit
                            phase_low <= 1'b1;
                            if (want_tx || want_sr) begin
                                shift   <= aw_byte;
                                bit_cnt <= 4'd0;
                                state   <= S_SEND_AW;
                            end else begin
                                shift   <= ar_byte;
                                bit_cnt <= 4'd0;
                                state   <= S_SEND_AR;
                            end
                        end
                    end

                    // send 8 bits MSB first (setup on SCL low, hold on SCL high)
                    S_SEND_AW, S_SEND_TX, S_SEND_AR: begin
                        if (phase_low) begin
                            scl_r    <= 1'b0;
                            sda_r    <= shift[7];
                            sda_oe_r <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r <= 1'b1;
                            if (bit_cnt == 4'd7) begin
                                bit_cnt   <= 4'd0;
                                phase_low <= 1'b1;
                                if (state == S_SEND_AW)
                                    state <= S_ACK_AW;
                                else if (state == S_SEND_TX)
                                    state <= S_ACK_TX;
                                else
                                    state <= S_ACK_AR;
                            end else begin
                                shift     <= {shift[6:0], 1'b0};
                                bit_cnt   <= bit_cnt + 4'd1;
                                phase_low <= 1'b1;
                            end
                        end
                    end

                    S_ACK_AW, S_ACK_TX, S_ACK_AR: begin
                        if (phase_low) begin
                            scl_r     <= 1'b0;
                            sda_oe_r  <= 1'b0; // release for slave ACK
                            sda_r     <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r <= 1'b1;
                            if (sda_i != 1'b0)
                                err <= 1'b1;
                            if (state == S_ACK_AW)
                                ack_aw <= ~sda_i;
                            else if (state == S_ACK_TX)
                                ack_byte <= ~sda_i;
                            else
                                ack_ar <= ~sda_i;

                            phase_low <= 1'b1;
                            if (state == S_ACK_AW) begin
                                if (want_tx) begin
                                    shift   <= reg_tx;
                                    bit_cnt <= 4'd0;
                                    state   <= S_SEND_TX;
                                end else begin
                                    // should not happen
                                    state <= S_STOP1;
                                end
                            end else if (state == S_ACK_TX) begin
                                if (want_sr) begin
                                    state <= S_SR_PREP;
                                end else begin
                                    // WRITE1 done
                                    state <= S_STOP1;
                                end
                            end else begin // ACK_AR
                                bit_cnt  <= 4'd0;
                                rx_shift <= 8'h00;
                                state    <= S_RECV0;
                            end
                        end
                    end

                    // prepare Sr: SCL low, SDA high, then SCL high, then SDA low
                    S_SR_PREP: begin
                        if (phase_low) begin
                            scl_r     <= 1'b0;
                            sda_r     <= 1'b1;
                            sda_oe_r  <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r     <= 1'b1;
                            phase_low <= 1'b1;
                            state     <= S_SR;
                        end
                    end

                    S_SR: begin
                        if (phase_low) begin
                            scl_r     <= 1'b1;
                            sda_r     <= 1'b0;
                            sda_oe_r  <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r     <= 1'b0;
                            shift     <= ar_byte;
                            bit_cnt   <= 4'd0;
                            phase_low <= 1'b1;
                            state     <= S_SEND_AR;
                        end
                    end

                    S_RECV0, S_RECV1: begin
                        if (phase_low) begin
                            scl_r     <= 1'b0;
                            sda_oe_r  <= 1'b0; // master releases
                            sda_r     <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r    <= 1'b1;
                            rx_shift <= {rx_shift[6:0], sda_i};
                            if (bit_cnt == 4'd7) begin
                                bit_cnt   <= 4'd0;
                                phase_low <= 1'b1;
                                if (state == S_RECV0) begin
                                    reg_rx0 <= {rx_shift[6:0], sda_i};
                                    if (want_rx1)
                                        state <= S_ACK_RX0;
                                    else
                                        state <= S_NACK;
                                end else begin
                                    reg_rx1 <= {rx_shift[6:0], sda_i};
                                    state   <= S_NACK;
                                end
                            end else begin
                                bit_cnt   <= bit_cnt + 4'd1;
                                phase_low <= 1'b1;
                            end
                        end
                    end

                    // master ACK after RX0 when a second byte follows
                    S_ACK_RX0: begin
                        if (phase_low) begin
                            scl_r     <= 1'b0;
                            sda_r     <= 1'b0;
                            sda_oe_r  <= 1'b1;
                            phase_low <= 1'b0;
                        end else begin
                            scl_r     <= 1'b1;
                            bit_cnt   <= 4'd0;
                            rx_shift  <= 8'h00;
                            phase_low <= 1'b1;
                            state     <= S_RECV1;
                        end
                    end

                    // master NACK before STOP
                    S_NACK: begin
                        if (phase_low) begin
                            scl_r     <= 1'b0;
                            sda_r     <= 1'b1;
                            sda_oe_r  <= 1'b1; // drive NACK = high while OE on
                            // OD remap: oe & ~sda = 0 when sda=1 -> released high via pull-up
                            phase_low <= 1'b0;
                        end else begin
                            scl_r     <= 1'b1;
                            phase_low <= 1'b1;
                            state     <= S_STOP1;
                        end
                    end

                    // STOP: SDA low, SCL high, then SDA high
                    S_STOP1: begin
                        scl_r     <= 1'b0;
                        sda_r     <= 1'b0;
                        sda_oe_r  <= 1'b1;
                        state     <= S_STOP2;
                    end
                    S_STOP2: begin
                        scl_r    <= 1'b1;
                        sda_r    <= 1'b0;
                        sda_oe_r <= 1'b1;
                        state    <= S_STOP3;
                    end
                    S_STOP3: begin
                        scl_r    <= 1'b1;
                        sda_r    <= 1'b1;
                        sda_oe_r <= 1'b1;
                        state    <= S_DONE;
                    end

                    S_DONE: begin
                        sda_oe_r   <= 1'b0;
                        busy       <= 1'b0;
                        done_pulse <= 1'b1;
                        state      <= S_IDLE;
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end

endmodule
