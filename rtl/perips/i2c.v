`include "../core/defines.v"


// I2C主机控制器 (轮询模式)
// 地址映射:
//   0x70010000: 从设备地址寄存器 (写), bit[7:1]=7bit地址
//   0x70020000: 输出/状态寄存器 (读), [15:0]=两字节数据, [31:30]=buzy
//   0x70030000: 发送触发寄存器 (写), 写入8位数据后触发完整I2C收发序列
//
// I2C序列 (写入0x70030000时触发):
//   START + 从设备地址[7:1]+W + ACK + 数据(写入的8位) + ACK +
//   RX byte1 + ACK + RX byte2 + NACK + STOP
//
// buzy[1:0]: 00=空闲, 01=正在收/发, 10=接收完毕等待读取
// CPU读取0x70020000且buzy=10时, 自动清零输出并复位

module i2c(

    input  wire        clk    ,
    input  wire        rst    ,

    // RIB slave interface (轮询, 无ack_o)
    input  wire        we_i   ,
    input  wire [31:0] addr_i ,
    input  wire [31:0] data_i ,
    output reg  [31:0] data_o ,
    input  wire        req_i  ,

    // I2C interface
    inout  wire        scl    ,
    inout  wire        sda

    );

    // ============================================================
    // 地址译码
    // ============================================================
    wire is_dev_addr = (addr_i[27:0] == 28'h10000);  // 0x70010000: 从设备地址写
    wire is_tx_data  = (addr_i[27:0] == 28'h20000);  // 0x70020000: 输出/状态读
    wire is_rx_data  = (addr_i[27:0] == 28'h30000);  // 0x70030000: 触发写

    // ============================================================
    // 寄存器
    // ============================================================
    reg [7:0]  dev_addr_reg;  // 从设备地址 bit[7:1]=地址
    reg [7:0]  tx_data_reg;   // 待发送数据
    reg [15:0] rx_data_reg;   // 已接收两字节数据
    reg [1:0]  buzy;          // 00=空闲, 01=忙, 10=完成待读取

    // ============================================================
    // I2C时钟分频
    // SCL频率 = sys_clk / (2 * SCL_DIV)
    // ============================================================
    parameter integer SCL_DIV = 250;

    // ============================================================
    // 状态机
    // ============================================================
    localparam S_IDLE       = 5'd0;
    localparam S_START_A    = 5'd1;   // SCL=1, SDA=1
    localparam S_START_B    = 5'd2;   // SCL=1, SDA=0
    localparam S_START_C    = 5'd3;   // SCL=0, SDA=0
    localparam S_TX_L       = 5'd4;   // SCL=0, 设置SDA
    localparam S_TX_H       = 5'd5;   // SCL=1, 从设备采样
    localparam S_ACK_L      = 5'd6;   // SCL=0, 释放SDA(收从设备ACK)
    localparam S_ACK_H      = 5'd7;   // SCL=1, 采样ACK
    localparam S_RX_L       = 5'd8;   // SCL=0, 释放SDA(从设备驱动)
    localparam S_RX_H       = 5'd9;   // SCL=1, 采样SDA
    localparam S_MACK_L     = 5'd10;  // SCL=0, 主机发ACK(SDA=0)
    localparam S_MACK_H     = 5'd11;  // SCL=1, 保持ACK
    localparam S_NACK_L     = 5'd12;  // SCL=0, 主机发NACK(SDA=1)
    localparam S_NACK_H     = 5'd13;  // SCL=1, 保持NACK
    localparam S_STOP_A     = 5'd14;  // SCL=0, SDA=0
    localparam S_STOP_B     = 5'd15;  // SCL=1, SDA=0
    localparam S_STOP_C     = 5'd16;  // SCL=1, SDA=1 (STOP)
    localparam S_DONE       = 5'd17;

    reg [4:0] state;

    // ============================================================
    // 半周期计数器
    // ============================================================
    reg [15:0] timer;
    wire timer_done = (timer == SCL_DIV - 1);

    // ============================================================
    // 位计数器 (0..7 数据位, 8 一帧结束)
    // ============================================================
    reg [3:0] bit_cnt;

    // ============================================================
    // 移位寄存器
    // ============================================================
    reg [7:0] shift_reg;

    // ============================================================
    // 序列阶段
    // ============================================================
    // 0=Addr+W, 1=Data, 2=Addr+R, 3=RX byte1, 4=RX byte2
    reg [2:0] seq_phase;

    // ============================================================
    // I2C IO
    // ============================================================
    reg scl_o;
    reg sda_o;
    reg scl_oe;
    reg sda_oe;
    reg sda_sync;

    assign scl = scl_oe ? scl_o : 1'bz;
    assign sda = sda_oe ? sda_o : 1'bz;

    // ============================================================
    // 读数据输出 (组合逻辑)
    //   读取0x70020000: 返回 {buzy, 14'd0, rx_data_reg}
    // ============================================================
    always @(*) begin
        if (req_i == `RIB_REQ && we_i == `WriteDisable && is_rx_data) begin
            if (buzy == `I2C_DONE) begin
                data_o = {buzy, 14'd0, rx_data_reg};
            end else begin
                data_o = {buzy, 30'd0};
            end
        end else begin
            data_o = `ZeroWord;
        end
    end

    // ============================================================
    // 主状态机
    // ============================================================
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state        <= S_IDLE;
            timer        <= 16'd0;
            bit_cnt      <= 4'd0;
            shift_reg    <= 8'd0;
            dev_addr_reg <= 8'd0;
            tx_data_reg  <= 8'd0;
            rx_data_reg  <= 16'd0;
            scl_o        <= 1'b1;
            sda_o        <= 1'b1;
            scl_oe       <= 1'b0;
            sda_oe       <= 1'b0;
            sda_sync     <= 1'b1;
            buzy         <= `I2C_FREE;
            seq_phase    <= 3'd0;
        end else begin
            // SDA同步 (用于采样)
            sda_sync <= sda;

            // ========== 读取输出寄存器清零逻辑 ==========
            // 当CPU读取0x70020000且buzy=DONE时, 清零并复位到IDLE
            if (req_i == `RIB_REQ && we_i == `WriteDisable && is_rx_data && buzy == `I2C_DONE) begin
                rx_data_reg <= 16'd0;
                buzy        <= `I2C_FREE;
                state       <= S_IDLE;
                seq_phase   <= 3'd0;
            end

            case (state)
                // =================== IDLE ===================
                S_IDLE: begin
                    scl_oe   <= 1'b0;  // 释放SCL
                    sda_oe   <= 1'b0;  // 释放SDA
                    timer    <= 16'd0;
                    bit_cnt  <= 4'd0;

                    if (req_i == `RIB_REQ) begin
                        if (we_i == `WriteEnable) begin
                            if (is_dev_addr) begin
                                // 写从设备地址
                                dev_addr_reg <= data_i[7:0];
                                buzy         <= `I2C_FREE;
                            end else if (is_tx_data) begin
                                // 写0x70030000: 触发完整I2C收发序列
                                tx_data_reg <= data_i[7:0];
                                // 加载Addr+W到移位寄存器
                                shift_reg   <= {dev_addr_reg[7:1], 1'b0};
                                seq_phase   <= 3'd0;
                                state       <= S_START_A;
                                buzy        <= `I2C_BUSY;
                            end else begin
                                buzy <= `I2C_FREE;
                            end
                        end else begin
                            buzy <= buzy;  // 读操作不影响buzy
                        end
                    end
                end

                // =================== START条件 ===================
                S_START_A: begin  // SCL=1, SDA=1 (准备)
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= 1'b1;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_START_B;
                    end
                end

                S_START_B: begin  // SCL=1, SDA=1->0 (START)
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= 1'b0;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_START_C;
                    end
                end

                S_START_C: begin  // SCL=1->0, SDA=0
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b0;
                    sda_o  <= 1'b0;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_TX_L;
                    end
                end

                // =================== 发送数据位 ===================
                S_TX_L: begin  // SCL=0, 设置SDA (MSB优先)
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b0;
                    sda_o  <= shift_reg[7];
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_TX_H;
                    end
                end

                S_TX_H: begin  // SCL=1, 从设备采样
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= shift_reg[7];
                    if (timer_done) begin
                        timer <= 16'd0;
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 4'd7) begin
                            state   <= S_ACK_L;
                            bit_cnt <= 4'd0;
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                            state   <= S_TX_L;
                        end
                    end
                end

                // =================== 接收ACK (从设备应答) ===================
                S_ACK_L: begin  // SCL=0, 释放SDA
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b0;  // 释放SDA
                    scl_o  <= 1'b0;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_ACK_H;
                    end
                end

                S_ACK_H: begin  // SCL=1, 采样ACK
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b0;
                    scl_o  <= 1'b1;
                    if (timer_done) begin
                        timer <= 16'd0;
                        // 根据序列阶段决定下一步
                        case (seq_phase)
                            3'd0: begin  // Addr+W完成 -> 发送数据
                                seq_phase <= 3'd1;
                                shift_reg <= tx_data_reg;
                                bit_cnt   <= 4'd0;
                                state     <= S_TX_L;
                            end
                            3'd1: begin  // 数据发送完成 -> 发送Addr+R (无重复START)
                                seq_phase <= 3'd2;
                                shift_reg <= {dev_addr_reg[7:1], 1'b1}; // Addr+R
                                bit_cnt   <= 4'd0;
                                state     <= S_TX_L;
                            end
                            3'd2: begin  // Addr+R完成 -> 开始接收byte1
                                seq_phase <= 3'd3;
                                bit_cnt   <= 4'd0;
                                state     <= S_RX_L;
                            end
                            default: begin
                                state <= S_STOP_A;
                            end
                        endcase
                    end
                end

                // =================== 接收数据位 ===================
                S_RX_L: begin  // SCL=0, 释放SDA (从设备驱动)
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b0;
                    scl_o  <= 1'b0;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_RX_H;
                    end
                end

                S_RX_H: begin  // SCL=1, 采样SDA
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b0;
                    scl_o  <= 1'b1;
                    // 在SCL高半周期中间采样
                    if (timer == (SCL_DIV >> 1)) begin
                        shift_reg <= {shift_reg[6:0], sda_sync};
                        if (seq_phase == 3'd3 || seq_phase == 3'd4) begin
                        //     $display("[MASTER] RX bit: t=%0d phase=%d bit_cnt=%d timer=%d sda_sync=%b shift_in=%b shift_reg_was=0x%02X",
                        //         $time, seq_phase, bit_cnt, timer, sda_sync, sda_sync, shift_reg);
                        end
                    end
                    if (timer_done) begin
                        timer <= 16'd0;
                        if (bit_cnt == 4'd7) begin
                            bit_cnt <= 4'd0;
                            if (seq_phase == 3'd3) begin
                                // byte1完成 -> 存入高8位, 主机发ACK
                                rx_data_reg[15:8] <= shift_reg;
                                // $display("[MASTER] RX byte1: t=%0d shift_reg=0x%02X (sda_sync=%b)", $time, shift_reg, sda_sync);
                                state     <= S_MACK_L;
                            end else begin
                                // byte2完成 -> 存入低8位, 主机发NACK
                                rx_data_reg[7:0] <= shift_reg;
                                // $display("[MASTER] RX byte2: shift_reg=0x%02X (sda_sync=%b)", shift_reg, sda_sync);
                                state     <= S_NACK_L;
                            end
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                            state   <= S_RX_L;
                        end
                    end
                end

                // =================== 主机发ACK (SDA=0) ===================
                S_MACK_L: begin
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b0;
                    sda_o  <= 1'b0;  // ACK
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_MACK_H;
                    end
                end

                S_MACK_H: begin
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= 1'b0;  // 保持ACK
                    if (timer_done) begin
                        timer     <= 16'd0;
                        seq_phase <= 3'd4;  // 进入byte2接收
                        bit_cnt   <= 4'd0;
                        state     <= S_RX_L;
                    end
                end

                // =================== 主机发NACK (SDA=1) ===================
                S_NACK_L: begin
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b0;
                    sda_o  <= 1'b1;  // NACK
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_NACK_H;
                    end
                end

                S_NACK_H: begin
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= 1'b1;  // 保持NACK
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_STOP_A;
                    end
                end

                // =================== STOP条件 ===================
                S_STOP_A: begin  // SCL=0, SDA=0
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b0;
                    sda_o  <= 1'b0;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_STOP_B;
                    end
                end

                S_STOP_B: begin  // SCL=0->1, SDA=0
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= 1'b0;
                    if (timer_done) begin
                        timer <= 16'd0;
                        state <= S_STOP_C;
                    end
                end

                S_STOP_C: begin  // SCL=1, SDA=0->1 (STOP)
                    timer  <= timer + 16'd1;
                    scl_oe <= 1'b1;
                    sda_oe <= 1'b1;
                    scl_o  <= 1'b1;
                    sda_o  <= 1'b1;
                    if (timer_done) begin
                        timer <= 16'd0;
                        buzy   <= `I2C_DONE;
                        state <= S_DONE;
                    end
                end

                // =================== DONE ===================
                S_DONE: begin
                    scl_oe <= 1'b0;  // 释放总线
                    sda_oe <= 1'b0;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
