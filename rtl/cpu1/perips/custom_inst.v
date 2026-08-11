// cpu1_custom_inst.v — 自定义指令执行单元
// 支持三条扩展指令:
//   sID (funct3=0): 通过UART发送学号 "2025270014\n"
//   rT  (funct3=1): 已改由 cpu1_inst_rt_ctrl + cpu1_i2c 外设完成
//   if  (funct3=2): Integrate-and-Fire神经元模型
//       imm!=0: rd = rs1 + sign_ext(imm)  (纯组合，由cpu1_ex.v直接处理)
//       imm==0: if rs1 >= x31 → UART发送rs1[7:0], rd=0; else rd=rs1
`include "../../shared/defines.v"

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

    // to cpu1_ex.v (rT 不再使用；保留端口以免改动过大)
    output wire        busy_o,
    output wire        done_o,
    output wire [31:0] result_o,
    output wire [4:0]  rd_addr_o,

    // bit-bang UART TX (sID / IF-fire)
    output wire        uart_tx_o,
    output wire        uart_busy_o
);

    // =========================================================
    // Parameters
    // =========================================================
    // 50MHz clock, 115200 baud → 434 cycles per bit
    localparam BAUD_DIV  = 32'd434;
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


    // rT 已外置到 I2C 外设；这些输出恒定无效
    assign busy_o    = 1'b0;
    assign done_o    = 1'b0;
    assign result_o  = 32'h0;
    assign rd_addr_o = 5'h0;

endmodule
