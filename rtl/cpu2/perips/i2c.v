// 地址映射:
//   0x7001_0000: 从设备地址寄存器 (SLAVE_ADDR) [6:0]
//   0x7002_0000: 发送数据寄存器 (TX_DATA) [7:0]
//   0x7003_0000: 接收数据寄存器高字节 (RX_DATA) [7:0]
//   0x7003_0004: 接收数据寄存器低字节 (RX_DATA_LOW) [7:0]
//   0x7003_0008: 接收数据寄存器高字节(无触发) (RX_DATA_RO) [7:0]
//   0x7005_0000: STATUS (RO) [7:0] = {done, busy, err, state[4:0]}

`include "../../shared/defines.v"

module cpu2_i2c (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] addr_i,
    input  wire [31:0] data_i,
    output reg  [31:0] data_o,
    input  wire        we_i,
    output wire        scl_o,
    output wire        scl_oe,
    output wire        sda_o,
    output wire        sda_oe,
    input  wire        sda_in
);

    // 地址定义
    // RIB总线将addr[31:28]用于从机路由, 截掉高4位后传给外设
    // 例如CPU访问0x7001_0000时, 本模块实际收到addr_i=0x0001_0000
    localparam ADDR_SLAVE  = 32'h0001_0000;
    localparam ADDR_TX     = 32'h0002_0000;
    localparam ADDR_RX     = 32'h0003_0000;
    localparam ADDR_RX_LOW = 32'h0003_0004;
    localparam ADDR_RX_DATA = 32'h0003_0008;  // RO, 读rx_high但不触发新事务
    localparam ADDR_STATUS = 32'h0005_0000;

    // I2C状态机定义 (全tick同步, 每状态维持一个tick周期)
    localparam S_IDLE        = 5'd0;
    localparam S_START_1     = 5'd1;
    localparam S_START_2     = 5'd2;
    localparam S_SEND_LOW    = 5'd3;
    localparam S_SEND_HIGH   = 5'd4;
    localparam S_WAIT_ACK_LOW  = 5'd5;
    localparam S_WAIT_ACK_HIGH = 5'd6;
    localparam S_RECV_LOW    = 5'd7;
    localparam S_RECV_HIGH   = 5'd8;
    localparam S_SEND_NACK_LOW  = 5'd9;
    localparam S_SEND_NACK_HIGH = 5'd10;
    localparam S_SEND_ACK_LOW   = 5'd11;
    localparam S_SEND_ACK_HIGH  = 5'd12;
    localparam S_STOP_1       = 5'd13;
    localparam S_STOP_2       = 5'd14;
    localparam S_STOP_3       = 5'd15;
    localparam S_DONE         = 5'd16;
    localparam S_RECOV_LOW    = 5'd17;
    localparam S_RECOV_HIGH   = 5'd18;
    localparam S_RECOV_STOP1  = 5'd19;
    localparam S_RECOV_STOP2  = 5'd20;
    localparam S_RECOV_STOP3  = 5'd21;

    // 时钟分频参数 (50MHz -> 100KHz)
    // tick周期 = (HALF_DIV+1) * 20ns ≈ 5.02μs (SCL半周期)
    // SCL周期 = 2 * tick ≈ 10μs → 100kHz
    localparam HALF_DIV = 16'd250;

    // I2C IO控制 (SCL 推挽驱动, 与 cpu0/cpu1/cpu3 一致; SDA 保持开漏)
    // 原实现 SCL 开漏: 高电平依赖外部上拉爬升, 上拉弱/总线电容大时
    // SCL 高电平被压缩, LM75 采样失败 → 读回 0x00. 推挽后与其余三核相同.
    reg        scl_drive_low;
    reg        sda_drive_low;

    assign scl_o  = ~scl_drive_low;
    assign scl_oe = 1'b1;
    assign sda_o  = 1'b0;
    assign sda_oe = sda_drive_low;

    // tick生成 (所有状态转移的时钟节拍)
    reg [15:0] tick_cnt;
    wire       tick;
    assign tick = (tick_cnt == HALF_DIV);

    // 内部寄存器
    reg [4:0]  state;
    reg [3:0]  bit_cnt;
    reg [7:0]  shift_reg;
    reg [7:0]  rx_shift;

    // 用户寄存器
    reg [6:0]  slave_addr;
    reg [7:0]  tx_data;
    reg [7:0]  rx_high;
    reg [7:0]  rx_low;
    reg        busy;
    reg        done;
    reg        err;

    // SCL 高电平中段采样值 (参考 cpu1: SCL 释放后等 SCL_HALF>>1 拍再锁存,
    // 留出 SDA RC 爬升/LM75 t_AA 时间, 避免在 SCL 上升沿零裕量采样)
    reg        sda_sample;

    // 传输控制
    reg        trans_rw;      // 0=写, 1=读
    reg [1:0]  trans_stage;   // 0=地址阶段, 1=数据阶段, 2=第2字节
    reg [3:0]  recovery_cnt;

    // 触发锁存 (避免丢失单周期脉冲)
    reg        cmd_latched;
    reg        cmd_rw;

    wire write_trig = we_i && (addr_i == ADDR_TX);
    wire read_trig  = !we_i && (addr_i == ADDR_RX);

    // SDA输入 (从pad读取)

    // tick计数器 (无条件运行)
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            tick_cnt <= 16'h0;
        end else if (tick) begin
            tick_cnt <= 16'h0;
        end else begin
            tick_cnt <= tick_cnt + 1'b1;
        end
    end

    // 寄存器写操作（busy时锁定）
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            slave_addr <= 7'h48;
            tx_data <= 8'b0;
        end else if (we_i && !busy) begin
            case (addr_i)
                ADDR_SLAVE: slave_addr <= data_i[6:0];
                ADDR_TX:    tx_data <= data_i[7:0];
                default:    ;
            endcase
        end
    end

    // 寄存器读操作
    always @(*) begin
        case (addr_i)
            ADDR_SLAVE:  data_o = {25'b0, slave_addr};
            ADDR_TX:     data_o = {24'b0, tx_data};
            ADDR_RX:     data_o = {24'b0, rx_high};
            ADDR_RX_LOW: data_o = {24'b0, rx_low};
            ADDR_RX_DATA: data_o = {24'b0, rx_high};
            ADDR_STATUS: data_o = {24'b0, done, busy, err, state};
            default:     data_o = 32'b0;
        endcase
    end

    // 触发锁存 (捕捉单周期脉冲, busy时忽略新请求)
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            cmd_latched <= 1'b0;
            cmd_rw <= 1'b0;
        end else begin
            if (tick && state == S_IDLE && cmd_latched) begin
                cmd_latched <= 1'b0;
            end
            if ((write_trig || read_trig) && !busy && !cmd_latched) begin
                cmd_latched <= 1'b1;
                cmd_rw <= read_trig;
            end
        end
    end

    // SCL 高电平中段锁存 sda_in: SCL 在 tick 边界释放, 等 HALF_DIV>>1 拍
    // (2.5μs @50MHz) 后采样, 位于 SCL 高电平正中, 与 cpu1/cpu0/cpu3 同级裕量
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            sda_sample <= 1'b1;
        end else if ((tick_cnt == (HALF_DIV >> 1)) &&
                     (state == S_WAIT_ACK_HIGH || state == S_RECV_HIGH)) begin
            sda_sample <= sda_in;
        end
    end

    // I2C主状态机 (所有转移在tick边界)
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state <= S_RECOV_LOW;
            bit_cnt <= 4'd0;
            shift_reg <= 8'b0;
            rx_shift <= 8'b0;
            rx_high <= 8'b0;
            rx_low <= 8'b0;
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            busy <= 1'b1;
            done <= 1'b0;
            err <= 1'b0;
            trans_rw <= 1'b0;
            trans_stage <= 2'd0;
            recovery_cnt <= 4'h0;
        end else if (tick) begin
            case (state)
                // ============================================
                // 空闲: 等待触发
                // ============================================
                S_IDLE: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    done <= 1'b0;
                    if (cmd_latched && !busy) begin
                        busy <= 1'b1;
                        done <= 1'b0;
                        err <= 1'b0;
                        trans_rw <= cmd_rw;
                        trans_stage <= 2'd0;
                        state <= S_START_1;
                    end
                end

                // ============================================
                // START条件: SCL高电平时SDA下降
                // S_START_1: 总线空闲 (SCL=H, SDA=H)
                // S_START_2: START (SDA拉低, SCL保持高)
                // ============================================
                S_START_1: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state <= S_START_2;
                end

                S_START_2: begin
                    scl_drive_low <= 1'b0;       // SCL保持高
                    sda_drive_low <= 1'b1;       // SDA拉低 → START
                    shift_reg <= {slave_addr, trans_rw};
                    bit_cnt <= 4'd0;
                    state <= S_SEND_LOW;
                end

                // ============================================
                // 发送一个字节 (8 bits)
                // S_SEND_LOW:  SCL低, 设置数据位
                // S_SEND_HIGH: SCL高, 数据保持
                // ============================================
                S_SEND_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= ~shift_reg[7];
                    state <= S_SEND_HIGH;
                end

                S_SEND_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= ~shift_reg[7];
                    shift_reg <= {shift_reg[6:0], 1'b0};
                    if (bit_cnt == 4'd7) begin
                        state <= S_WAIT_ACK_LOW;
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                        state <= S_SEND_LOW;
                    end
                end

                // ============================================
                // 检查从机ACK
                // S_WAIT_ACK_LOW:  SCL低, 释放SDA
                // S_WAIT_ACK_HIGH: SCL高, 采样SDA
                // ============================================
                S_WAIT_ACK_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b0;
                    state <= S_WAIT_ACK_HIGH;
                end

                S_WAIT_ACK_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    // NACK 只记录 err, 不终止事务 (与 cpu1 一致):
                    // ACK 采样误判时仍继续读数据位, 避免温度被固定读成 0x00
                    if (sda_sample == 1'b1) begin
                        err <= 1'b1;
                    end
                    if (trans_rw == 1'b0) begin
                        // ========== 写事务 ==========
                        if (trans_stage == 2'd0) begin
                            // 地址阶段完成, 进入数据阶段
                            trans_stage <= 2'd1;
                            shift_reg <= tx_data;
                            bit_cnt <= 4'd0;
                            state <= S_SEND_LOW;
                        end else begin
                            // 数据已发送, 结束
                            state <= S_STOP_1;
                        end
                    end else begin
                        // ========== 读事务 ==========
                        if (trans_stage == 2'd0) begin
                            trans_stage <= 2'd1;
                            bit_cnt <= 4'd0;
                            rx_shift <= 8'h00;
                            state <= S_RECV_LOW;
                        end else begin
                            state <= S_STOP_1;
                        end
                    end
                end

                // ============================================
                // 接收字节
                // S_RECV_LOW:  SCL低
                // S_RECV_HIGH: SCL高, 采样SDA
                // ============================================
                S_RECV_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b0;
                    state <= S_RECV_HIGH;
                end

                S_RECV_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    rx_shift <= {rx_shift[6:0], sda_sample};
                    if (bit_cnt == 4'd7) begin
                        if (trans_rw == 1'b1 && trans_stage == 2'd1) begin
                            // 第一个字节 (MSB) → ACK
                            rx_high <= {rx_shift[6:0], sda_sample};
                            state <= S_SEND_ACK_LOW;
                        end else begin
                            // 第二个字节 (LSB) → NACK
                            rx_low <= {rx_shift[6:0], sda_sample};
                            state <= S_SEND_NACK_LOW;
                        end
                    end else begin
                        bit_cnt <= bit_cnt + 1'b1;
                        state <= S_RECV_LOW;
                    end
                end

                // ============================================
                // 主机发送ACK
                // ============================================
                S_SEND_ACK_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b1;   // 驱动SDA低 = ACK
                    state <= S_SEND_ACK_HIGH;
                end

                S_SEND_ACK_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b1;
                    trans_stage <= 2'd2;
                    bit_cnt <= 4'd0;
                    rx_shift <= 8'h00;
                    state <= S_RECV_LOW;
                end

                // ============================================
                // 主机发送NACK
                // ============================================
                S_SEND_NACK_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b0;   // 释放SDA = NACK
                    state <= S_SEND_NACK_HIGH;
                end

                S_SEND_NACK_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state <= S_STOP_1;
                end

                // ============================================
                // STOP条件: SCL高电平时SDA上升
                // S_STOP_1: SCL低, SDA低
                // S_STOP_2: SCL高, SDA低
                // S_STOP_3: SCL高, SDA释放 → STOP
                // ============================================
                S_STOP_1: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b1;
                    state <= S_STOP_2;
                end

                S_STOP_2: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b1;
                    state <= S_STOP_3;
                end

                S_STOP_3: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    state <= S_DONE;
                end

                // ============================================
                // 事务完成
                // ============================================
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                // ============================================
                // 总线恢复 (复位后执行, 解除从设备死锁)
                // ============================================
                S_RECOV_LOW: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b0;
                    busy <= 1'b1;
                    state <= S_RECOV_HIGH;
                end

                S_RECOV_HIGH: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    if (recovery_cnt == 4'd8) begin
                        recovery_cnt <= 4'h0;
                        state <= S_RECOV_STOP1;
                    end else begin
                        recovery_cnt <= recovery_cnt + 1'b1;
                        state <= S_RECOV_LOW;
                    end
                end

                S_RECOV_STOP1: begin
                    scl_drive_low <= 1'b1;
                    sda_drive_low <= 1'b1;
                    state <= S_RECOV_STOP2;
                end

                S_RECOV_STOP2: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b1;
                    state <= S_RECOV_STOP3;
                end

                S_RECOV_STOP3: begin
                    scl_drive_low <= 1'b0;
                    sda_drive_low <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
