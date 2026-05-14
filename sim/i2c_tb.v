`timescale 1ns / 1ps

`include "../rtl/core/defines.v"

// ============================================================
// I2C 主机控制器 测试平台 (轮询模式)
// 从设备发送两字节: TX_BYTE1=0xA5, TX_BYTE2=0x5A
// ============================================================
module i2c_tb();

    reg         clk;
    reg         rst;

    // RIB slave interface (master side)
    reg  [31:0] addr;
    reg  [31:0] wdata;
    wire [31:0] rdata;
    reg         we;
    reg         req;

    // I2C bus (with pull-up)
    wire        scl;
    wire        sda;
    pullup(scl);
    pullup(sda);

    // ============================================================
    // 时钟: 50MHz (20ns)
    // ============================================================
    always #10 clk = ~clk;

    // ============================================================
    // DUT: I2C 主机控制器 (SCL_DIV=4 加速仿真)
    // ============================================================
    i2c #(
        .SCL_DIV(4)
    ) u_i2c (
        .clk   (clk  ),
        .rst   (rst  ),
        .we_i  (we   ),
        .addr_i(addr ),
        .data_i(wdata),
        .data_o(rdata),
        .req_i (req  ),
        .scl   (scl  ),
        .sda   (sda  )
    );

    // ============================================================
    // I2C 从设备模型
    //
    //  从设备地址: I2C_ADDR (7'h28, 写入0x70010000的值为0x50)
    //  主机读取时返回: TX_BYTE1=0xA5, TX_BYTE2=0x5A
    //
    //  处理完整的 I2C 序列:
    //    START + Addr+W + data + Addr+R + byte1 + byte2 + STOP
    // ============================================================
    localparam I2C_ADDR  = 7'h28;
    localparam TX_BYTE1  = 8'hA5;
    localparam TX_BYTE2  = 8'h5A;

    // SCL/SDA 同步 (消抖)
    reg scl_s0, scl_s1;
    reg sda_s0, sda_s1;
    wire scl_rise =  scl_s0 & ~scl_s1;
    wire scl_fall = ~scl_s0 &  scl_s1;
    wire sda_rise =  sda_s0 & ~sda_s1;
    wire sda_fall = ~sda_s0 &  sda_s1;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            scl_s0 <= 1'b1;
            scl_s1 <= 1'b1;
            sda_s0 <= 1'b1;
            sda_s1 <= 1'b1;
        end else begin
            scl_s0 <= scl;
            scl_s1 <= scl_s0;
            sda_s0 <= sda;
            sda_s1 <= sda_s0;
        end
    end

    // 从设备 SDA 驱动 (三态)
    reg slave_sda_drive;
    reg slave_sda_val;
    assign sda = slave_sda_drive ? slave_sda_val : 1'bz;

    // ============================================================
    // START / STOP 检测
    // ============================================================
    reg start_seen;
    reg stop_seen;
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            start_seen <= 1'b0;
            stop_seen  <= 1'b0;
        end else begin
            if (scl_s1 && scl_s0 && sda_fall) start_seen <= 1'b1;
            if (scl_s1 && scl_s0 && sda_rise) stop_seen  <= 1'b1;
            if (scl_fall && start_seen) start_seen <= 1'b0;
            if (start_seen)              stop_seen  <= 1'b0;
        end
    end

    // ============================================================
    // 从设备状态
    // ============================================================
    // slave_state:
    //   0 = IDLE (等待START)
    //   1 = 接收 Addr+W
    //   2 = 接收 Data byte
    //   3 = 接收 Addr+R (重复START后)
    //   4 = 发送 byte1
    //   5 = 发送 byte2
    reg [2:0] slave_state;
    reg [3:0] bit_pos;       // 0..7=数据位, 8=ACK位 (SCL上升沿计数)
    reg [7:0] recv_shift;    // 接收移位寄存器
    reg [6:0] rcvd_addr;     // 收到的地址
    reg       rcvd_rw;       // 收到的 R/W 位
    reg       addr_hit;      // 地址匹配
    reg [7:0] rcvd_data;     // 收到的数据字节
    reg [1:0] ack_count;     // 2=ACK phase (suppress scl_fall+ scl_rise), counts down each edge
    reg [7:0] tx_shift;      // TX发送移位寄存器,byte完成时加载,每个数据scl_fall左移

    localparam SS_IDLE      = 3'd0;
    localparam SS_ADDR_W    = 3'd1;
    localparam SS_DATA      = 3'd2;
    localparam SS_ADDR_R    = 3'd3;
    localparam SS_TX_BYTE1  = 3'd4;
    localparam SS_TX_BYTE2  = 3'd5;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            slave_state     <= SS_IDLE;
            bit_pos         <= 4'd0;
            recv_shift      <= 8'd0;
            rcvd_addr       <= 7'd0;
            rcvd_rw         <= 1'b0;
            addr_hit        <= 1'b0;
            rcvd_data       <= 8'd0;
            tx_shift        <= 8'd0;
            slave_sda_drive <= 1'b0;
            slave_sda_val   <= 1'b0;
            ack_count       <= 2'd0;
        end else begin

            // ----- START 检测: 复位位计数, 切换状态 -----
            if (start_seen) begin
                bit_pos <= 4'd0;
                if (slave_state == SS_IDLE || slave_state == SS_DATA) begin
                    // 第一次 START (IDLE→ADDR_W) 或 重复START (DATA→ADDR_R)
                    if (slave_state == SS_IDLE) begin
                        slave_state <= SS_ADDR_W;
                        addr_hit    <= 1'b0;
                    end else begin
                        slave_state <= SS_ADDR_R;
                    end
                end
                // 释放SDA
                slave_sda_drive <= 1'b0;
                ack_count       <= 2'd0;
            end

            // ----- STOP 检测: 回到 IDLE -----
            if (stop_seen) begin
                slave_state <= SS_IDLE;
                slave_sda_drive <= 1'b0;
                ack_count       <= 2'd0;
            end

            // ----- SCL 下降沿: 从设备驱动 SDA -----
            if (scl_fall) begin
                if (slave_state == SS_TX_BYTE1 || slave_state == SS_TX_BYTE2) begin
                    // TX模式: 由ack_count抑制ACK周期的scl_fall(与master ACK/NACK竞争)
                    if (ack_count > 2'd0) begin
                        slave_sda_drive <= 1'b0;  // 释放SDA避免竞争
                        ack_count       <= ack_count - 2'd1;
                    end else begin
                        slave_sda_drive <= 1'b1;  // 驱动TX数据
                        slave_sda_val   <= tx_shift[7];
                        tx_shift        <= {tx_shift[6:0], 1'b0};
                    end
                end else if (bit_pos < 4'd8) begin
                    // 接收模式: 释放SDA (从设备不驱动)
                    slave_sda_drive <= 1'b0;
                end else begin
                    // bit_pos == 8: ACK位置 (从设备应答)
                    if ((slave_state == SS_ADDR_W || slave_state == SS_DATA || slave_state == SS_ADDR_R) && addr_hit) begin
                        slave_sda_drive <= 1'b1;
                        slave_sda_val   <= 1'b0;  // ACK
                    end else begin
                        slave_sda_drive <= 1'b0;  // NACK/释放
                    end
                end
            end

            // ----- SCL 上升沿: 从设备采样 SDA, 管理位/字节位置 -----
            if (scl_rise) begin
                if (ack_count > 2'd0) begin
                    // ACK周期的scl_rise: 不推进bit_pos, 递减ack_count
                    ack_count <= ack_count - 2'd1;
                end else if (bit_pos < 4'd8) begin
                    // 数据位: 采样
                    if (slave_state == SS_ADDR_W || slave_state == SS_DATA || slave_state == SS_ADDR_R) begin
                        recv_shift <= {recv_shift[6:0], sda_s1};
                    end
                    bit_pos <= bit_pos + 4'd1;
                end else begin
                    // bit_pos == 8: ACK位置 (一字节完成)

                    case (slave_state)
                        SS_ADDR_W: begin
                            // 地址+R/W接收完成
                            // 注意: 经过8次 MSB-first 移位后,
                            // recv_shift[7:1]=7位地址, recv_shift[0]=R/W位
                            rcvd_addr <= recv_shift[7:1];
                            rcvd_rw   <= recv_shift[0];
                            if (recv_shift[7:1] == I2C_ADDR && recv_shift[0] == 1'b0) begin
                                addr_hit <= 1'b1;
                                slave_state <= SS_DATA;
                            end else begin
                                addr_hit <= 1'b0;
                            end
                        end
                        SS_DATA: begin
                            // 数据字节接收完成 → 下一字节是Addr+R
                            rcvd_data   <= recv_shift;
                            slave_state <= SS_ADDR_R;
                            addr_hit    <= 1'b0;  // 重新检查地址
                        end
                        SS_ADDR_R: begin
                            // 地址+R接收完成 (重复START后)
                            rcvd_addr <= recv_shift[7:1];
                            rcvd_rw   <= recv_shift[0];
                            if (recv_shift[7:1] == I2C_ADDR && recv_shift[0] == 1'b1) begin
                                addr_hit    <= 1'b1;
                                slave_state <= SS_TX_BYTE1;
                                // Note: ack_count=0 so slave drives on 1st scl_fall
                                // (the ACK cycle's falling edge). ack_count=2 would
                                // skip 2 edges (the ACK fall+rise), delaying data
                                // drive by one full bit and corrupting RX.
                                ack_count   <= 2'd0;
                                tx_shift    <= TX_BYTE1;
                            end else begin
                                addr_hit <= 1'b0;
                            end
                        end
                        SS_TX_BYTE1: begin
                            // byte1发送完成, 加载byte2, 进入TX_BYTE2
                            // ack_count=0: slave drives on the first scl_fall after entering
                            // TX2 (which is S_MACK_H→S_RX_L). Master releases SDA when
                            // entering S_RX_L (sda_oe=0), so no bus contention.
                            // ack_count>0 would skip the first scl_fall, delaying data
                            // drive past the master's sample point.
                            slave_state <= SS_TX_BYTE2;
                            ack_count   <= 2'd0;
                            tx_shift    <= TX_BYTE2;
                        end
                        SS_TX_BYTE2: begin
                            // byte2发送完成, 等待主机NACK+STOP
                            slave_state <= SS_IDLE;
                            // 不设ack_count — master驱动NACK, slave已释放
                        end
                        default: begin
                            slave_state <= SS_IDLE;
                        end
                    endcase

                    bit_pos <= 4'd0;
                end
            end
        end
    end

    // ============================================================
    // CPU 仿真任务 (轮询模式, 无 ack 信号)
    // ============================================================
    reg [31:0] readback;

    // DEBUG: trace slave state transitions
    always @(posedge clk) begin
        if (rst == `RstDisable) begin
            if (start_seen) $display("[DEBUG] t=%0d START seen, slave_state=%d -> %s",
                $time, slave_state,
                (slave_state==SS_IDLE) ? "SS_ADDR_W" :
                (slave_state==SS_DATA) ? "SS_ADDR_R" : "no_change");
            if (stop_seen) $display("[DEBUG] t=%0d STOP seen, slave_state=%d -> SS_IDLE", $time, slave_state);
            if (scl_fall && (slave_state == SS_TX_BYTE1 || slave_state == SS_TX_BYTE2) && bit_pos < 8)
                $display("[DEBUG] t=%0d TX bit: state=%s bit_pos=%d sda_val=%b tx_shift=%02x ack=%d drive=%b",
                    $time, (slave_state==SS_TX_BYTE1)?"TX1":"TX2", bit_pos, slave_sda_val,
                    tx_shift, ack_count, slave_sda_drive);
            if (scl_rise && bit_pos == 4'd8) begin
                $display("[DEBUG] t=%0d BYTE done: state=%d recv_shift=0x%02X addr_hit=%d sda=%b",
                    $time, slave_state, recv_shift, addr_hit, sda);
            end
        end
    end

    // CPU 写 (单周期)
    task cpu_write;
        input [31:0] taddr;
        input [31:0] tdata;
        begin
            @(posedge clk);
            addr  <= taddr;
            wdata <= tdata;
            we    <= `WriteEnable;
            req   <= `RIB_REQ;
            @(posedge clk);
            addr  <= `ZeroWord;
            wdata <= `ZeroWord;
            we    <= `WriteDisable;
            req   <= `RIB_NREQ;
            @(posedge clk);
        end
    endtask

    // CPU 读 (单周期, 轮询)
    task cpu_read;
        input  [31:0] taddr;
        output [31:0] tdata;
        begin
            @(posedge clk);
            addr  <= taddr;
            we    <= `WriteDisable;
            req   <= `RIB_REQ;
            @(posedge clk);
            tdata <= rdata;  // 捕获数据
            addr  <= `ZeroWord;
            we    <= `WriteDisable;
            req   <= `RIB_NREQ;
            @(posedge clk);
        end
    endtask

    // 轮询等待 I2C 完成 (buzy==10)
    task poll_i2c_done;
        output [31:0] result;
        begin
            // 先等一段时间让 I2C 开始工作
            repeat (20) @(posedge clk);
            // 轮询 0x70020000 直到 buzy[17:16] == 10
            forever begin
                cpu_read(32'h70020000, result);
                if (result[31:30] == `I2C_DONE) begin
                    // 读取返回的数据, 同时自动清零
                    // 注意: 这次读取已经清零了 buzy 和 rx_data
                    disable poll_i2c_done;
                end
                @(posedge clk);
            end
        end
    endtask

    // ============================================================
    // 主测试序列
    // ============================================================
    integer error_cnt;

    initial begin
        $dumpfile("i2c_tb.vcd");
        $dumpvars(0, i2c_tb);

        // 初始化
        clk   <= 1'b0;
        rst   <= `RstEnable;
        addr  <= `ZeroWord;
        wdata <= `ZeroWord;
        we    <= `WriteDisable;
        req   <= `RIB_NREQ;
        error_cnt <= 0;

        // 复位 (100ns)
        #100;
        rst <= `RstDisable;
        #40;

        // ============================
        // Test 1: 设置从设备地址
        // ============================
        $display("=== Test 1: Set slave address (0x50 -> 7'h28) ===");
        cpu_write(32'h70010000, 32'h00000050);
        $display("  OK");

        // ============================
        // Test 2: 完整I2C收发序列
        //   写入 0x70030000(data=0xAB) -> 触发:
        //     START + Addr+W + 0xAB + Addr+R + RX 0xA5 + ACK + RX 0x5A + NACK + STOP
        //   然后轮询等待 buzy=DONE, 读取 rx_data=0xA55A
        // ============================
        $display("");
        $display("=== Test 2: Full I2C transaction (trigger data=0xAB) ===");
        $display("  Expect slave to return: TX_BYTE1=0x%02X, TX_BYTE2=0x%02X", TX_BYTE1, TX_BYTE2);

        // 触发序列
        cpu_write(32'h70030000, 32'h000000AB);

        // 轮询等待完成, 读取结果 (自动清零)
        poll_i2c_done(readback);
        $display("  Readback: 0x%08X", readback);
        $display("  Buzy: 0x%X (expected: 0x2 -> DONE, but cleared by read)", readback[17:16]);
        $display("  RX data: 0x%04X (expected: 0x%02X%02X)", readback[15:0], TX_BYTE1, TX_BYTE2);

        if (readback[15:0] !== {TX_BYTE1, TX_BYTE2}) begin
            $display("  *** FAIL: data mismatch! Expected 0x%04X, got 0x%04X",
                     {TX_BYTE1, TX_BYTE2}, readback[15:0]);
            error_cnt = error_cnt + 1;
        end else begin
            $display("  PASS");
        end

        // ============================
        // Test 3: 验证读取后自动清零
        // ============================
        $display("");
        $display("=== Test 3: Verify clear-on-read ===");
        cpu_read(32'h70020000, readback);
        $display("  Readback after clear: 0x%08X", readback);
        $display("  Buzy: 0x%X (expected: 0x0 -> FREE)", readback[17:16]);

        if (readback[17:16] !== `I2C_FREE) begin
            $display("  *** FAIL: buzy should be FREE after clear! ***");
            error_cnt = error_cnt + 1;
        end else if (readback[15:0] !== 16'd0) begin
            $display("  *** FAIL: data should be 0 after clear! ***");
            error_cnt = error_cnt + 1;
        end else begin
            $display("  PASS");
        end

        // ============================
        // Test 4: 第二次收发序列 (验证可重用)
        // ============================
        $display("");
        $display("=== Test 4: Second transaction (data=0x77) ===");

        cpu_write(32'h70030000, 32'h00000077);

        poll_i2c_done(readback);
        $display("  Readback: 0x%08X (expected data: 0x%04X)",
                 readback, {TX_BYTE1, TX_BYTE2});

        if (readback[15:0] !== {TX_BYTE1, TX_BYTE2}) begin
            $display("  *** FAIL: data mismatch! ***");
            error_cnt = error_cnt + 1;
        end else begin
            $display("  PASS");
        end

        // ============================
        // Test 5: 验证读取清零后buzy轮询可重触发
        // ============================
        $display("");
        $display("=== Test 5: Trigger while idle, verify buzy polling ===");

        // 先确保空闲
        cpu_read(32'h70020000, readback);
        $display("  Initial buzy: 0x%X (expected: 0x0)", readback[17:16]);

        // 触发
        cpu_write(32'h70030000, 32'h00000042);

        // 轮询直到buzy变成DONE
        poll_i2c_done(readback);
        $display("  After trigger, readback: 0x%08X", readback);
        $display("  RX data: 0x%04X (expected: 0x%04X)",
                 readback[15:0], {TX_BYTE1, TX_BYTE2});

        if (readback[15:0] !== {TX_BYTE1, TX_BYTE2}) begin
            $display("  *** FAIL: data mismatch! ***");
            error_cnt = error_cnt + 1;
        end else begin
            $display("  PASS");
        end

        // ============================
        // 结果汇总
        // ============================
        $display("");
        $display("=================================");
        if (error_cnt == 0) begin
            $display("  ALL TESTS PASSED!");
        end else begin
            $display("  %0d TEST(S) FAILED!", error_cnt);
        end
        $display("=================================");
        $dumpoff;
        #100;
        $finish;
    end

endmodule
