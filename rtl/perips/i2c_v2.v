`include "../core/defines.v"

// I2C v2 — 接口与 i2c.v 兼容, 内部用 4-phase SCL 状态机
// 协议: START + Addr+R + ACK + RX byte1 + MACK + RX byte2 + NACK + STOP
// (跳过写寄存器阶段, 直接读)

module i2c_v2(

    input  wire        clk    ,
    input  wire        rst    ,

    // RIB slave interface
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
    // 地址译码 (与 i2c.v 一致)
    // ============================================================
    wire is_dev_addr = (addr_i[27:0] == 28'h10000);  // 0x70010000
    wire is_tx_data  = (addr_i[27:0] == 28'h20000);  // 0x70020000: 触发
    wire is_rx_data  = (addr_i[27:0] == 28'h30000);  // 0x70030000: 读数据

    // ============================================================
    // 寄存器
    // ============================================================
    reg [7:0]  dev_addr_reg;  // 从设备地址 bit[7:1]=7bit地址
    reg [15:0] rx_data_reg;   // 已接收两字节数据
    reg [1:0]  buzy;          // 00=空闲, 01=忙, 10=完成

    // ============================================================
    // SCL 分频参数
    // ============================================================
    parameter integer SCL_DIV = 250;        // 半周期 (同 i2c.v)
    localparam  SCL_FULL = 2 * SCL_DIV;     // 完整 SCL 周期
    localparam  SCL_Q1   = (SCL_DIV / 2) - 1;
    localparam  SCL_Q2   = SCL_DIV - 1;
    localparam  SCL_Q3   = SCL_DIV + SCL_Q1;
    localparam  SCL_Q4   = SCL_FULL - 1;

    // ============================================================
    // 4-phase SCL 时钟 (来自 i2c_modified)
    // ============================================================
    reg [15:0] cnt_delay;
    reg [2:0]  cnt;            // 0=pos, 1=hig, 2=neg, 3=low
    reg        scl_r;
    reg        timer_run;      // 1=SCL计时中, 0=暂停

    `define SCL_POS  (cnt == 3'd0)
    `define SCL_HIG  (cnt == 3'd1)
    `define SCL_NEG  (cnt == 3'd2)
    `define SCL_LOW  (cnt == 3'd3)

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            cnt_delay <= 16'd0;
        end else if (timer_run) begin
            if (cnt_delay == SCL_Q4)
                cnt_delay <= 16'd0;
            else
                cnt_delay <= cnt_delay + 1'b1;
        end else begin
            cnt_delay <= 16'd0;
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            cnt <= 3'd5;
        end else if (timer_run) begin
            case (cnt_delay)
                SCL_Q1: cnt <= 3'd1;
                SCL_Q2: cnt <= 3'd2;
                SCL_Q3: cnt <= 3'd3;
                SCL_Q4: cnt <= 3'd0;
                default: cnt <= 3'd5;
            endcase
        end else begin
            cnt <= 3'd5;
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            scl_r <= 1'b1;
        end else if (`SCL_POS) begin
            scl_r <= 1'b1;
        end else if (`SCL_NEG) begin
            scl_r <= 1'b0;
        end
    end

    // ============================================================
    // 状态机 (来自 i2c_modified, 简化)
    // ============================================================
    localparam ST_IDLE   = 4'd0;
    localparam ST_START  = 4'd1;
    localparam ST_ADDR   = 4'd2;
    localparam ST_ACK1   = 4'd3;
    localparam ST_DATA1  = 4'd4;
    localparam ST_ACK2   = 4'd5;
    localparam ST_DATA2  = 4'd6;
    localparam ST_NACK   = 4'd7;
    localparam ST_STOP   = 4'd8;

    reg [3:0]  cstate;
    reg        sda_link, sda_r;
    reg [3:0]  num;
    reg [7:0]  db_r;          // 要发送的地址字节

    // ============================================================
    // I2C IO
    // ============================================================
    assign scl = (cstate == ST_IDLE || cstate == ST_STOP) ? 1'b1 : scl_r;
    assign sda = sda_link ? sda_r : 1'bz;

    // ============================================================
    // 主状态机
    // ============================================================
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            cstate    <= ST_IDLE;
            sda_r     <= 1'b1;
            sda_link  <= 1'b0;
            num       <= 4'd0;
            buzy      <= `I2C_FREE;
            timer_run <= 1'b0;
            rx_data_reg <= 16'd0;
        end else begin

            if (req_i == `RIB_REQ && we_i == `WriteDisable && is_rx_data && buzy == `I2C_DONE) begin
                rx_data_reg <= 16'd0;
                buzy        <= `I2C_FREE;
                cstate      <= ST_IDLE;
            end
            case (cstate)

                // ---------- IDLE: 等触发 ----------
                ST_IDLE: begin
                    sda_link <= 1'b1;
                    sda_r    <= 1'b1;
                    if (req_i == `RIB_REQ) begin
                        if (we_i == `WriteEnable) begin
                            if (is_dev_addr) begin
                                // 写从设备地址
                                dev_addr_reg <= data_i[7:0];
                            end else if (is_tx_data) begin
                                // 触发: 发 Addr+R, 读温度
                                db_r      <= {dev_addr_reg[7:1], 1'b1};
                                cstate    <= ST_START;
                                buzy      <= `I2C_BUSY;
                                timer_run <= 1'b1;
                            end
                        end
                    end
                end

                // ---------- START: SDA↓ while SCL=1 ----------
                ST_START: begin
                    if (`SCL_HIG) begin
                        sda_link <= 1'b1;
                        sda_r    <= 1'b0;
                        cstate   <= ST_ADDR;
                        num      <= 4'd0;
                    end
                end

                // ---------- ADDR: 发送 Addr+R 字节 ----------
                ST_ADDR: begin
                    if (`SCL_LOW) begin
                        if (num == 4'd8) begin
                            num      <= 4'd0;
                            sda_r    <= 1'b1;
                            sda_link <= 1'b0;
                            cstate   <= ST_ACK1;
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
                                default: ;
                            endcase
                        end
                    end
                end

                // ---------- ACK1: 从设备应答 ----------
                ST_ACK1: begin
                    if (`SCL_NEG) begin
                        cstate <= ST_DATA1;
                    end
                end

                // ---------- DATA1: 读 byte1 ----------
                ST_DATA1: begin
                    if (`SCL_HIG) begin
                        num <= num + 1'b1;
                        case (num)
                            4'd0: rx_data_reg[15] <= sda;
                            4'd1: rx_data_reg[14] <= sda;
                            4'd2: rx_data_reg[13] <= sda;
                            4'd3: rx_data_reg[12] <= sda;
                            4'd4: rx_data_reg[11] <= sda;
                            4'd5: rx_data_reg[10] <= sda;
                            4'd6: rx_data_reg[9]  <= sda;
                            4'd7: rx_data_reg[8]  <= sda;
                            default: ;
                        endcase
                    end else if ((`SCL_NEG) && (num == 4'd8)) begin
                        num      <= 4'd0;
                        sda_link <= 1'b1;
                        sda_r    <= 1'b0;    // ACK
                        cstate   <= ST_ACK2;
                    end
                end

                // ---------- ACK2: 主设备发 ACK ----------
                ST_ACK2: begin
                    if (`SCL_LOW) begin
                        sda_r <= 1'b0;
                    end else if (`SCL_NEG) begin
                        cstate   <= ST_DATA2;
                        sda_link <= 1'b0;
                        sda_r    <= 1'b1;
                    end
                end

                // ---------- DATA2: 读 byte2 ----------
                ST_DATA2: begin
                    if (`SCL_HIG) begin
                        num <= num + 1'b1;
                        case (num)
                            4'd0: rx_data_reg[7] <= sda;
                            4'd1: rx_data_reg[6] <= sda;
                            4'd2: rx_data_reg[5] <= sda;
                            4'd3: rx_data_reg[4] <= sda;
                            4'd4: rx_data_reg[3] <= sda;
                            4'd5: rx_data_reg[2] <= sda;
                            4'd6: rx_data_reg[1] <= sda;
                            4'd7: rx_data_reg[0] <= sda;
                            default: ;
                        endcase
                    end else if ((`SCL_LOW) && (num == 4'd8)) begin
                        num      <= 4'd0;
                        sda_link <= 1'b1;
                        sda_r    <= 1'b1;    // NACK
                        cstate   <= ST_NACK;
                    end
                end

                // ---------- NACK + 写结果 → STOP ----------
                ST_NACK: begin
                    if (`SCL_LOW) begin
                        sda_r  <= 1'b0;
                        cstate <= ST_STOP;
                    end
                end

                // ---------- STOP: SDA↑ while SCL=1 ----------
                ST_STOP: begin
                    if (`SCL_HIG) begin
                        sda_r     <= 1'b1;
                        cstate    <= ST_IDLE;
                        buzy      <= `I2C_DONE;
                        timer_run <= 1'b0;
                    end
                end

                default: cstate <= ST_IDLE;
            endcase
        end
    end

    // ============================================================
    // 读数据输出 (组合逻辑, 与 i2c.v 一致)
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
    // 读清零逻辑 (与 i2c.v 一致)
    // ============================================================
    // always @(posedge clk) begin
    //     if (req_i == `RIB_REQ && we_i == `WriteDisable && is_rx_data && buzy == `I2C_DONE) begin
    //         rx_data_reg <= 16'd0;
    //         buzy        <= `I2C_FREE;
    //         cstate      <= ST_IDLE;
    //     end
    // end

    reg flag1, flag2, flag3, flag4;
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            flag1 <= 1'b0;
            flag2 <= 1'b0;
            flag3 <= 1'b0;
            flag4 <= 1'b0;
        end else begin
            // flag1 <= 1'b0;
            if (timer_run == 1) begin
                flag1 <= 1'b1;
            end 

            // flag2 <= 1'b0;
            if (is_tx_data == 1) begin
                flag2 <= (req_i == `RIB_REQ)&&(we_i == `WriteEnable);
            end

            // flag3 <= 1'b0;
            if (buzy == `I2C_BUSY) begin
                flag3 <= 1'b1;
            end

            // flag4 <= 1'b0;
            if (cstate != ST_IDLE) begin
                flag4 <= 1'b1;
            end
        end
    end

endmodule
