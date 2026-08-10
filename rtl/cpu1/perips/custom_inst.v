// cpu1_custom_inst.v — 自定义指令执行单元
// 支持三条扩展指令:
//   sID (funct3=0): 通过UART发送学号 "2025270014\n"
//   rT  (funct3=1): 通过I2C读取LM75温度，stall CPU
//   if  (funct3=2): Integrate-and-Fire神经元模型
//       imm!=0: rd = rs1 + sign_ext(imm)  (纯组合，由cpu1_ex.v直接处理)
//       imm==0: if rs1 >= x31 → UART发送rs1[7:0], rd=0; else rd=rs1
`include "../core/defines.v"

module cpu1_custom_inst(
    input  wire        clk,
    input  wire        rst,

    // from cpu1_ex.v (combinational, held while instruction is in EX stage)
    input  wire        start_i,
    input  wire [2:0]  funct3_i,
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,   // x31 (threshold) for IF instruction
    input  wire [11:0] imm_i,
    input  wire [4:0]  rd_addr_i,  // rd register address (latched when rT starts)

    // to cpu1_ex.v
    output reg         busy_o,    // 1 = I2C running
    output reg         done_o,    // 1 = result ready (one-clock pulse)
    output reg  [31:0] result_o,  // temperature result
    output reg  [4:0]  rd_addr_o, // stored rd address for write-back

    // bit-bang UART TX (idle high, for sID/IF/rT-debug)
    output wire        uart_tx_o,
    output wire        uart_busy_o,

    // I2C master
    output wire        i2c_scl_o,
    output wire        i2c_sda_o,
    output wire        i2c_sda_oe_o,
    input  wire        i2c_sda_i
);

    // =========================================================
    // Parameters
    // =========================================================
    // 50MHz clock, 115200 baud → 434 cycles per bit
    localparam BAUD_DIV  = 32'd434;
    // 50MHz clock, I2C 100KHz → 250 cycles per half-period
    localparam SCL_HALF  = 9'd250;
    // Student ID: "2025270014\n" = 11 bytes
    localparam SID_LEN   = 4'd11;

    // =========================================================
    // Detect a NEW custom instruction entering EX
    // Simple rising-edge on start_i is not enough: consecutive
    // custom instructions (e.g., the five IF accumulate+fire
    // instructions) keep start_i=1 so start_posedge stays 0.
    // Fix: treat it as a new instruction whenever start_i rises
    // OR when any input operand changes (= different instruction).
    // =========================================================
    reg         start_r;
    reg  [2:0]  last_funct3_r;
    reg  [11:0] last_imm_r;
    reg  [31:0] last_rs1_r;

    wire instr_changed = (funct3_i != last_funct3_r) |
                         (imm_i    != last_imm_r)    |
                         (rs1_i    != last_rs1_r);
    wire start_posedge = start_i & (~start_r | instr_changed);

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            start_r       <= 1'b0;
            last_funct3_r <= 3'h7;    // invalid
            last_imm_r    <= 12'hFFF; // invalid
            last_rs1_r    <= 32'hFFFF_FFFF;
        end else begin
            start_r       <= start_i;
            last_funct3_r <= funct3_i;
            last_imm_r    <= imm_i;
            last_rs1_r    <= rs1_i;
        end
    end

    // =========================================================
    // UART TX bit-bang
    // =========================================================
    // State
    localparam UART_IDLE   = 2'd0;
    localparam UART_ACTIVE = 2'd1;

    reg [1:0]  uart_state;
    reg [3:0]  uart_bit_cnt;   // 0..9 (start + 8 data + stop)
    reg [9:0]  uart_shift_reg; // {stop=1, d7..d0, start=0}
    reg [3:0]  uart_byte_cnt;  // current byte index
    reg [3:0]  uart_total;     // total bytes to send
    reg [31:0] uart_baud_cnt;
    reg        uart_tx_r;
    reg [7:0]  uart_single_byte; // for IF-fire single byte
    reg        uart_mode;        // 0=sID, 1=IF single

    localparam UART_MODE_SID = 1'd0;
    localparam UART_MODE_IF  = 1'd1;

    // Student ID ROM
    reg [7:0] sid_rom [0:10];
    initial begin
        sid_rom[0]  = 8'h32; // '2'
        sid_rom[1]  = 8'h30; // '0'
        sid_rom[2]  = 8'h32; // '2'
        sid_rom[3]  = 8'h35; // '5'
        sid_rom[4]  = 8'h32; // '2'
        sid_rom[5]  = 8'h37; // '7'
        sid_rom[6]  = 8'h30; // '0'
        sid_rom[7]  = 8'h30; // '0'
        sid_rom[8]  = 8'h31; // '1'
        sid_rom[9]  = 8'h34; // '4'
        sid_rom[10] = 8'h0A; // '\n'
    end

    // Trigger signals
    reg uart_sid_trigger;
    reg uart_if_trigger;

    // Detect triggers from start_posedge
    always @ (posedge clk) begin
        uart_sid_trigger <= 1'b0;
        uart_if_trigger  <= 1'b0;
        if (start_posedge) begin
            if (funct3_i == `INST_CUSTOM_SID) begin
                uart_sid_trigger <= 1'b1;
            end else if (funct3_i == `INST_CUSTOM_IF && imm_i == 12'h0) begin
                // fire only when rs1 >= rs2 (x31)
                if ($signed(rs1_i) >= $signed(rs2_i)) begin
                    uart_if_trigger  <= 1'b1;
                    uart_single_byte <= rs1_i[7:0];
                end
            end
        end
    end

    // UART TX state machine
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            uart_state    <= UART_IDLE;
            uart_tx_r     <= 1'b1;
            uart_baud_cnt <= 32'h0;
            uart_bit_cnt  <= 4'h0;
            uart_byte_cnt <= 4'h0;
            uart_total    <= 4'h0;
            uart_mode     <= UART_MODE_SID;
        end else begin
            case (uart_state)
                UART_IDLE: begin
                    uart_tx_r <= 1'b1;
                    if (uart_sid_trigger) begin
                        uart_mode      <= UART_MODE_SID;
                        uart_total     <= SID_LEN;
                        uart_byte_cnt  <= 4'h0;
                        uart_shift_reg <= {1'b1, sid_rom[0], 1'b0};
                        uart_bit_cnt   <= 4'h0;
                        uart_baud_cnt  <= 32'h0;
                        uart_state     <= UART_ACTIVE;
                    end else if (uart_if_trigger) begin
                        uart_mode      <= UART_MODE_IF;
                        uart_total     <= 4'h1;
                        uart_byte_cnt  <= 4'h0;
                        uart_shift_reg <= {1'b1, uart_single_byte, 1'b0};
                        uart_bit_cnt   <= 4'h0;
                        uart_baud_cnt  <= 32'h0;
                        uart_state     <= UART_ACTIVE;
                    end
                end
                UART_ACTIVE: begin
                    uart_tx_r <= uart_shift_reg[0];
                    if (uart_baud_cnt >= BAUD_DIV - 1) begin
                        uart_baud_cnt <= 32'h0;
                        if (uart_bit_cnt == 4'd9) begin
                            // byte done
                            if (uart_byte_cnt >= uart_total - 1) begin
                                uart_state <= UART_IDLE;
                            end else begin
                                uart_byte_cnt  <= uart_byte_cnt + 1'b1;
                                if (uart_mode == UART_MODE_SID) begin
                                    uart_shift_reg <= {1'b1, sid_rom[uart_byte_cnt + 1], 1'b0};
                                end else begin
                                    uart_shift_reg <= {1'b1, uart_single_byte, 1'b0};
                                end
                                uart_bit_cnt   <= 4'h0;
                            end
                        end else begin
                            uart_shift_reg <= {1'b1, uart_shift_reg[9:1]};
                            uart_bit_cnt   <= uart_bit_cnt + 1'b1;
                        end
                    end else begin
                        uart_baud_cnt <= uart_baud_cnt + 1'b1;
                    end
                end
                default: uart_state <= UART_IDLE;
            endcase
        end
    end

    assign uart_tx_o = uart_tx_r;
    assign uart_busy_o = (uart_state != UART_IDLE);

    // =========================================================
    // I2C master — LM75 temperature read
    // LM75 I2C address: 0x48 (A0=A1=A2=GND)
    //   Write addr: 0x90   Read addr: 0x91
    //
    // Protocol (write-then-read, more robust):
    //   Phase 1 WRITE  – set pointer to temperature register 0x00
    //     START → 0x90 (write) → ACK → 0x00 (pointer) → ACK
    //   Phase 2 READ   – repeated START, read temperature MSB
    //     rSTART → 0x91 (read) → ACK → READ_BYTE → NACK → STOP
    //
    // Step map (each step = SCL_HALF clock cycles):
    //   0        PRE-START   (SCL=1, SDA=1)
    //   1        START       (SCL=1, SDA→0)
    //   2..17    WRITE 0x90  (16 steps, bit7→bit0, even=SCL_low odd=SCL_high)
    //   18-19    ACK_W_ADDR  (release SDA)
    //   20..35   WRITE 0x00  (16 steps, all zeros, oe=1)
    //   36-37    ACK_PTR     (release SDA)
    //   38       rSTART_PRE  (SCL=0, SDA=1, oe=1)
    //   39       rSTART_SCL  (SCL=1, SDA=1, oe=1)
    //   40       rSTART      (SCL=1, SDA→0, oe=1)
    //   41..56   WRITE 0x91  (16 steps, bit7→bit0, even=SCL_low odd=SCL_high)
    //   57-58    ACK_R_ADDR  (release SDA)
    //   59..74   READ byte   (16 steps, oe=0; sample at even steps 60,62,..74)
    //   75-76    NACK        (master drives SDA=1)
    //   77-78    STOP_PRE    (SCL=0→1, SDA=0)
    //   79       STOP        (SCL=1, SDA→1)
    //   80       done check fires
    // =========================================================
    localparam I2C_TOTAL_STEPS  = 7'd80;
    localparam I2C_WRITE_ADDR   = 8'h90;  // 0x48<<1 | write=0
    localparam I2C_READ_ADDR    = 8'h91;  // 0x48<<1 | read=1
    localparam I2C_PTR_BYTE     = 8'h00;  // pointer → temperature register

    reg [6:0]  i2c_step;
    reg [8:0]  i2c_ph_cnt;
    reg [7:0]  i2c_rx_byte;
    reg        i2c_active;
    reg [2:0]  i2c_ack_ok; // [0]=ACK write addr, [1]=ACK ptr, [2]=ACK read addr
    reg [2:0]  i2c_ack_raw; // raw SDA at ACK sample: 0=low, 1=high
    reg        i2c_read_any_high;
    reg        i2c_read_any_low;

    reg        i2c_scl_r, i2c_sda_r, i2c_sda_oe_r;

    always @ (*) begin
        case (i2c_step)
            // --- Phase 1 START ---
            7'd0:  begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end  // PRE-START
            7'd1:  begin i2c_scl_r=1; i2c_sda_r=0; i2c_sda_oe_r=1; end  // START
            // --- Send write address 0x90 (bit7→bit0, steps 2..17) ---
            7'd2:  begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[7]; i2c_sda_oe_r=1; end
            7'd3:  begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[7]; i2c_sda_oe_r=1; end
            7'd4:  begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[6]; i2c_sda_oe_r=1; end
            7'd5:  begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[6]; i2c_sda_oe_r=1; end
            7'd6:  begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[5]; i2c_sda_oe_r=1; end
            7'd7:  begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[5]; i2c_sda_oe_r=1; end
            7'd8:  begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[4]; i2c_sda_oe_r=1; end
            7'd9:  begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[4]; i2c_sda_oe_r=1; end
            7'd10: begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[3]; i2c_sda_oe_r=1; end
            7'd11: begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[3]; i2c_sda_oe_r=1; end
            7'd12: begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[2]; i2c_sda_oe_r=1; end
            7'd13: begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[2]; i2c_sda_oe_r=1; end
            7'd14: begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[1]; i2c_sda_oe_r=1; end
            7'd15: begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[1]; i2c_sda_oe_r=1; end
            7'd16: begin i2c_scl_r=0; i2c_sda_r=I2C_WRITE_ADDR[0]; i2c_sda_oe_r=1; end
            7'd17: begin i2c_scl_r=1; i2c_sda_r=I2C_WRITE_ADDR[0]; i2c_sda_oe_r=1; end
            // --- ACK from slave (write addr) ---
            7'd18: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd19: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            // --- Send pointer byte 0x00 (all zeros, steps 20..35) ---
            7'd20: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[7]; i2c_sda_oe_r=1; end
            7'd21: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[7]; i2c_sda_oe_r=1; end
            7'd22: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[6]; i2c_sda_oe_r=1; end
            7'd23: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[6]; i2c_sda_oe_r=1; end
            7'd24: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[5]; i2c_sda_oe_r=1; end
            7'd25: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[5]; i2c_sda_oe_r=1; end
            7'd26: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[4]; i2c_sda_oe_r=1; end
            7'd27: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[4]; i2c_sda_oe_r=1; end
            7'd28: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[3]; i2c_sda_oe_r=1; end
            7'd29: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[3]; i2c_sda_oe_r=1; end
            7'd30: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[2]; i2c_sda_oe_r=1; end
            7'd31: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[2]; i2c_sda_oe_r=1; end
            7'd32: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[1]; i2c_sda_oe_r=1; end
            7'd33: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[1]; i2c_sda_oe_r=1; end
            7'd34: begin i2c_scl_r=0; i2c_sda_r=I2C_PTR_BYTE[0]; i2c_sda_oe_r=1; end
            7'd35: begin i2c_scl_r=1; i2c_sda_r=I2C_PTR_BYTE[0]; i2c_sda_oe_r=1; end
            // --- ACK from slave (pointer byte) ---
            7'd36: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd37: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            // --- Repeated START ---
            7'd38: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=1; end  // SCL low, SDA high
            7'd39: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end  // SCL rises
            7'd40: begin i2c_scl_r=1; i2c_sda_r=0; i2c_sda_oe_r=1; end  // SDA falls = rSTART
            // --- Send read address 0x91 (bit7→bit0, steps 41..56) ---
            7'd41: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[7]; i2c_sda_oe_r=1; end
            7'd42: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[7]; i2c_sda_oe_r=1; end
            7'd43: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[6]; i2c_sda_oe_r=1; end
            7'd44: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[6]; i2c_sda_oe_r=1; end
            7'd45: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[5]; i2c_sda_oe_r=1; end
            7'd46: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[5]; i2c_sda_oe_r=1; end
            7'd47: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[4]; i2c_sda_oe_r=1; end
            7'd48: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[4]; i2c_sda_oe_r=1; end
            7'd49: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[3]; i2c_sda_oe_r=1; end
            7'd50: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[3]; i2c_sda_oe_r=1; end
            7'd51: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[2]; i2c_sda_oe_r=1; end
            7'd52: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[2]; i2c_sda_oe_r=1; end
            7'd53: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[1]; i2c_sda_oe_r=1; end
            7'd54: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[1]; i2c_sda_oe_r=1; end
            7'd55: begin i2c_scl_r=0; i2c_sda_r=I2C_READ_ADDR[0]; i2c_sda_oe_r=1; end
            7'd56: begin i2c_scl_r=1; i2c_sda_r=I2C_READ_ADDR[0]; i2c_sda_oe_r=1; end
            // --- ACK from slave (read addr) ---
            7'd57: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd58: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end
            // --- Receive data byte (oe=0; SCL high at even steps 60,62..74) ---
            7'd59: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd60: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit7 sample
            7'd61: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd62: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit6 sample
            7'd63: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd64: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit5 sample
            7'd65: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd66: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit4 sample
            7'd67: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd68: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit3 sample
            7'd69: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd70: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit2 sample
            7'd71: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd72: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit1 sample
            7'd73: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=0; end
            7'd74: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=0; end  // bit0 sample
            // --- NACK from master ---
            7'd75: begin i2c_scl_r=0; i2c_sda_r=1; i2c_sda_oe_r=1; end
            7'd76: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
            // --- STOP ---
            7'd77: begin i2c_scl_r=0; i2c_sda_r=0; i2c_sda_oe_r=1; end  // SCL low, SDA=0
            7'd78: begin i2c_scl_r=1; i2c_sda_r=0; i2c_sda_oe_r=1; end  // SCL high, SDA=0
            7'd79: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end  // SDA rises = STOP
            default: begin i2c_scl_r=1; i2c_sda_r=1; i2c_sda_oe_r=1; end
        endcase
    end

    assign i2c_scl_o    = i2c_active ? i2c_scl_r    : 1'b1;
    assign i2c_sda_o    = i2c_active ? i2c_sda_r    : 1'b1;
    assign i2c_sda_oe_o = i2c_active ? i2c_sda_oe_r : 1'b1;

    // I2C step / phase counter
    // (SDA data sampling merged here to avoid multi-driver synthesis conflict)
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            i2c_step    <= 7'h0;
            i2c_ph_cnt  <= 9'h0;
            i2c_active  <= 1'b0;
            i2c_rx_byte <= 8'h0;
            i2c_ack_ok  <= 3'b000;
            i2c_ack_raw <= 3'b111;
            i2c_read_any_high <= 1'b0;
            i2c_read_any_low  <= 1'b0;
            busy_o      <= 1'b0;
            done_o      <= 1'b0;
            result_o    <= 32'h0;
            rd_addr_o   <= 5'h0;
        end else begin
            done_o <= 1'b0;

            // ---- I2C temperature read (rT triggers this) ----
            if (!i2c_active) begin
                if (start_posedge && funct3_i == `INST_CUSTOM_RT) begin
                    i2c_active <= 1'b1;
                    busy_o     <= 1'b1;
                    i2c_step   <= 7'h0;
                    i2c_ph_cnt <= 9'h0;
                    i2c_ack_ok <= 3'b000;
                    i2c_ack_raw <= 3'b111;
                    i2c_read_any_high <= 1'b0;
                    i2c_read_any_low  <= 1'b0;
                    rd_addr_o  <= rd_addr_i;
                end
            end else begin
                    // Sample SDA at the middle of each SCL-high half-period
                    if (i2c_ph_cnt == (SCL_HALF >> 1)) begin
                        // ACK phases
                        if (i2c_step == 7'd19) begin
                            i2c_ack_raw[0] <= i2c_sda_i;
                            i2c_ack_ok[0]  <= ~i2c_sda_i;
                        end else if (i2c_step == 7'd37) begin
                            i2c_ack_raw[1] <= i2c_sda_i;
                            i2c_ack_ok[1]  <= ~i2c_sda_i;
                        end else if (i2c_step == 7'd58) begin
                            i2c_ack_raw[2] <= i2c_sda_i;
                            i2c_ack_ok[2]  <= ~i2c_sda_i;
                        end
                        // Data read phases: even steps 60,62,64,66,68,70,72,74
                        if (i2c_step[0] == 1'b0 &&
                            i2c_step >= 7'd60 && i2c_step <= 7'd74) begin
                            if (i2c_sda_i == 1'b1)
                                i2c_read_any_high <= 1'b1;
                            else
                                i2c_read_any_low  <= 1'b1;
                            case (i2c_step)
                                7'd60: i2c_rx_byte[7] <= i2c_sda_i;
                                7'd62: i2c_rx_byte[6] <= i2c_sda_i;
                                7'd64: i2c_rx_byte[5] <= i2c_sda_i;
                                7'd66: i2c_rx_byte[4] <= i2c_sda_i;
                                7'd68: i2c_rx_byte[3] <= i2c_sda_i;
                                7'd70: i2c_rx_byte[2] <= i2c_sda_i;
                                7'd72: i2c_rx_byte[1] <= i2c_sda_i;
                                7'd74: i2c_rx_byte[0] <= i2c_sda_i;
                                default: ;
                            endcase
                        end
                    end

                    if (i2c_ph_cnt >= SCL_HALF - 1) begin
                        i2c_ph_cnt <= 9'h0;
                        if (i2c_step >= I2C_TOTAL_STEPS) begin
                            i2c_active <= 1'b0;
                            busy_o     <= 1'b0;
                            done_o     <= 1'b1;
                            result_o   <= {24'h0, i2c_rx_byte};
                        end else begin
                            i2c_step <= i2c_step + 1'b1;
                        end
                    end else begin
                        i2c_ph_cnt <= i2c_ph_cnt + 1'b1;
                    end
            end
        end
    end

endmodule
