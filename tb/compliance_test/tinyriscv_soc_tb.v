`timescale 1 ns / 1 ps

`include "../../rtl/core/defines.v"


//`define TEST_PROG  1
//`define TEST_JTAG  1
`define TEST_I2C   1

`ifdef TEST_I2C
    // I2C test data bytes sent by slave
    `ifndef I2C_TEST_DATA0
        `define I2C_TEST_DATA0  8'hAA
    `endif
    `ifndef I2C_TEST_DATA1
        `define I2C_TEST_DATA1  8'h55
    `endif
`endif


// testbench module
module tinyriscv_soc_tb;

    reg clk;
    reg rst;


    always #10 clk = ~clk;     // 50MHz

    wire [`BridgeBus] bridge;
    wire [3:0] pwm;
    wire scl;
    wire sda;

    reg scl_oe, scl_o, sda_oe, sda_o;

    assign scl = scl_oe?scl_o:1'bz;
    assign sda = sda_oe?sda_o:1'bz;

    wire[`RegBus] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    wire[`RegBus] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    wire[`RegBus] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];

    wire[31:0] ex_end_flag = u_bridge_fpga.u_ram._ram[4];
    wire[31:0] begin_signature = u_bridge_fpga.u_ram._ram[2];
    wire[31:0] end_signature = u_bridge_fpga.u_ram._ram[3];

    integer r;
    integer fd;

`ifdef TEST_JTAG
    reg TCK;
    reg TMS;
    reg TDI;
    wire TDO;

    integer i;
    reg[39:0] shift_reg;
    reg in;
    wire[39:0] req_data = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.dtm_req_data;
    wire[4:0] ir_reg = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.ir_reg;
    wire dtm_req_valid = tinyriscv_soc_top_0.u_jtag_top.u_jtag_driver.dtm_req_valid;
    wire[31:0] dmstatus = tinyriscv_soc_top_0.u_jtag_top.u_jtag_dm.dmstatus;
`endif

    initial begin
        clk = 0;
        rst = `RstEnable;

        scl_oe=0; scl_o=0; sda_oe=0; sda_o=0;
`ifdef TEST_JTAG
        TCK = 1;
        TMS = 1;
        TDI = 1;
`endif
        $display("test running...");
        #40
        rst = `RstDisable;
        #200
/*
`ifdef TEST_PROG
        wait(x26 == 32'b1)   // wait sim end, when x26 == 1
        #100
        if (x27 == 32'b1) begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
            $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("fail testnum = %2d", x3);
            for (r = 0; r < 32; r = r + 1)
                $display("x%2d = 0x%x", r, tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[r]);
        end
`endif
*/

        wait(ex_end_flag == 32'h1);  // wait sim end

        // fd = $fopen(`OUTPUT);   // OUTPUT的�?�在命令行里定义
        // for (r = begin_signature; r < end_signature; r = r + 4) begin
        //     $fdisplay(fd, "%x", u_bridge_fpga.u_rom._rom[r[31:2]]);
        // end
        // $fclose(fd);

`ifdef TEST_JTAG
        // reset
        for (i = 0; i < 8; i++) begin
            TMS = 1;
            TCK = 0;
            #100
            TCK = 1;
            #100
            TCK = 0;
        end

        // IR
        shift_reg = 40'b10001;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SELECT-IR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // CAPTURE-IR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-IR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-IR & EXIT1-IR
        for (i = 5; i > 0; i--) begin
            if (shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;

            if (i == 1)
                TMS = 1;

            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;

            shift_reg = {{(35){1'b0}}, in, shift_reg[4:1]};
        end

        // PAUSE-IR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // EXIT2-IR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // UPDATE-IR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // dmi write
        shift_reg = {6'h10, {(32){1'b0}}, 2'b10};

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;

            if (i == 1)
                TMS = 1;

            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;

            shift_reg = {in, shift_reg[39:1]};
        end

        // PAUSE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // EXIT2-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // UPDATE-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        $display("ir_reg = 0x%x", ir_reg);
        $display("dtm_req_valid = %d", dtm_req_valid);
        $display("req_data = 0x%x", req_data);

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        $display("dmstatus = 0x%x", dmstatus);

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // dmi read
        shift_reg = {6'h11, {(32){1'b0}}, 2'b01};

        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;

            if (i == 1)
                TMS = 1;

            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;

            shift_reg = {in, shift_reg[39:1]};
        end

        // PAUSE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // EXIT2-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // UPDATE-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // IDLE
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SELECT-DR
        TMS = 1;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // dmi read
        shift_reg = {6'h11, {(32){1'b0}}, 2'b00};

        // CAPTURE-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-DR
        TMS = 0;
        TCK = 0;
        #100
        TCK = 1;
        #100
        TCK = 0;

        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0] == 1'b1)
                TDI = 1'b1;
            else
                TDI = 1'b0;

            if (i == 1)
                TMS = 1;

            TCK = 0;
            #100
            in = TDO;
            TCK = 1;
            #100
            TCK = 0;

            shift_reg = {in, shift_reg[39:1]};
        end

        #100

        $display("shift_reg = 0x%x", shift_reg[33:2]);
`endif

        $finish;
    end

    // sim timeout
//   initial begin
//       #500000
//       $display("Time Out.");
//       $finish;
//   end

    // read mem data
    initial begin
        $readmemh ("inst.data", u_bridge_fpga.u_rom._rom);
    end

    // generate wave file, used by gtkwave
    initial begin
        $dumpfile("tinyriscv_soc_tb.vcd");
        $dumpvars(0, tinyriscv_soc_tb);
    end

    tinyriscv_soc_top tinyriscv_soc_top_0(
        .clk(clk),
        .rst(rst),
        .uart_debug_pin(1'b0),
        .bridge(bridge),
        .pwm(pwm),
        .scl(scl),
        .sda(sda)/*
        .jtag_TCK(TCK),
        .jtag_TMS(TMS),
        .jtag_TDI(TDI),
        .jtag_TDO(TDO)*/
    );

    bridge_fpga u_bridge_fpga(
        .clk(clk),
        .rst(rst),
        .bridge_io(bridge)
    );

`ifdef TEST_I2C

// ============================================================
// I2C Slave Emulation for Testbench
// ============================================================
// 时序: START + addr[7:1]+W + ACK + addr[7:1]+R + ACK +
//       data0[7:0] + MACK + data1[7:0] + MNACK + STOP
// ============================================================

// --- SDA/SCL同步到系统时钟 ---
reg sda_s1, sda_s2;
reg scl_s1, scl_s2;

always @(posedge clk) begin
    sda_s1 <= sda;
    sda_s2 <= sda_s1;
    scl_s1 <= scl;
    scl_s2 <= scl_s1;
end

// --- 边沿检测 ---
wire sda_fall =  sda_s2 && ~sda_s1;
wire sda_rise = ~sda_s2 &&  sda_s1;
wire scl_rise = ~scl_s2 &&  scl_s1;
wire scl_fall =  scl_s2 && ~scl_s1;

// START condition: SDA下降沿 & SCL高电平
wire i2c_start = sda_fall && scl_s1;
// STOP  condition: SDA上升沿 & SCL高电平
wire i2c_stop  = sda_rise && scl_s1;

// --- 状态编码 ---
localparam I2C_IDLE = 3'd0;
localparam I2C_RECV = 3'd1;  // 接收主机数据
localparam I2C_SACK = 3'd2;  // 从机应答(拉低SDA)
localparam I2C_SEND = 3'd3;  // 从机发送数据给主机
localparam I2C_MACK = 3'd4;  // 检测主机应答/非应答

localparam I2C_TEST_DATA0 = `I2C_TEST_DATA0;
localparam I2C_TEST_DATA1 = `I2C_TEST_DATA1;

reg [2:0] i2c_state;
reg [7:0] i2c_sreg;       // 移位寄存器
reg [3:0] i2c_bcnt;       // 位计数器
reg [7:0] i2c_txbuf;      // 发送缓冲
reg       i2c_dir;         // 0=W(写), 1=R(读)
reg       i2c_phase;       // 0=第一次发送, 1=第二次发送
reg [1:0] i2c_rcnt;        // recv byte counter (0~2 -> 3 frames)

initial begin
    i2c_txbuf = I2C_TEST_DATA0;
end

always @(posedge clk or posedge rst) begin
    if (rst == `RstEnable) begin
        i2c_state <= I2C_IDLE;
        i2c_bcnt  <= 0;
        i2c_sreg  <= 0;
        i2c_phase <= 0;
        i2c_rcnt  <= 0;
        sda_oe    <= 0;
        sda_o     <= 0;
    end else begin
        // 任何状态下检测到START/STOP则跳转
        if (i2c_start) begin
            i2c_state <= I2C_RECV;
            i2c_bcnt  <= 0;
            i2c_sreg  <= 0;
            // NOTE: 不在此处复位i2c_rcnt, 以支持重复START
            sda_oe    <= 0;
        end else if (i2c_stop) begin
            i2c_state <= I2C_IDLE;
            i2c_bcnt  <= 0;
            i2c_rcnt  <= 0;
            sda_oe    <= 0;
        end else begin
            case (i2c_state)
                // --- 空闲 ---
                I2C_IDLE: begin
                    sda_oe <= 0;
                    i2c_bcnt <= 0;
                    i2c_phase <= 0;
                    i2c_rcnt <= 0;
                end

                // --- 从主机接收字节 ---
                I2C_RECV: begin
                    // SCL上升沿采样SDA
                    if (scl_rise && i2c_bcnt < 8) begin
                        i2c_sreg <= {i2c_sreg[6:0], sda_s1};
                        i2c_bcnt <= i2c_bcnt + 1;
                    end
                    // 收满8位后转入应答
                    if (i2c_bcnt == 8 && scl_fall) begin
                        i2c_dir   <= i2c_sreg[0];  // bit0 = R/W
                        i2c_state <= I2C_SACK;
                    end
                end

                // --- 从机应答: 拉低SDA ---
                I2C_SACK: begin
                    sda_oe <= 1;
                    sda_o  <= 0;                // ACK
                    if (scl_fall) begin
                        i2c_bcnt <= 0;
                        i2c_rcnt <= i2c_rcnt + 1;
                        if (i2c_rcnt == 2'd2) begin
                            // 已收满3帧, 直接驱动第一bit数据(不释放SDA)
                            i2c_state <= I2C_SEND;
                            i2c_txbuf <= {I2C_TEST_DATA0[6:0], 1'b0};
                            sda_oe <= 1;
                            sda_o  <= I2C_TEST_DATA0[7];
                            // i2c_txbuf <= {i2c_txbuf[6:0], 1'b0};
                        end else begin
                            sda_oe <= 0;        // 释放SDA
                            i2c_state <= I2C_RECV;
                            i2c_sreg  <= 0;
                        end
                    end
                end

                // --- 从机发送数据给主机 ---
                I2C_SEND: begin
                    // SCL下降沿驱动数据
                    if (scl_fall && i2c_bcnt < 7) begin
                        sda_oe <= 1;
                        sda_o  <= i2c_txbuf[7];
                        i2c_txbuf <= {i2c_txbuf[6:0], 1'b0};
                        i2c_bcnt  <= i2c_bcnt + 1;
                    end
                    if (i2c_bcnt == 7 && scl_fall) begin
                        sda_oe    <= 0;          // 释放SDA给主机应答
                        i2c_state <= I2C_MACK;
                    end
                end

                // --- 检测主机应答/非应答 ---
                I2C_MACK: begin
                    // SCL上升沿采样SDA
                    if (scl_fall) begin
                        if (sda_s2 == 0) begin
                            // 主机应答(ACK): 继续发送下一字节
                            i2c_state <= I2C_SEND;
                            i2c_bcnt  <= 0;
                            i2c_txbuf <= {I2C_TEST_DATA1[6:0], 1'b0};
                            sda_o  <= I2C_TEST_DATA1[7];
                            sda_oe <= 1;
                        end else begin
                            // 主机非应答(NACK): 传输结束
                            i2c_state <= I2C_IDLE;
                            i2c_bcnt  <= 0;
                            sda_oe <= 0;
                            sda_o <= 0;
                        end
                    end
                end

                default: begin
                    i2c_state <= I2C_IDLE;
                    sda_oe <= 0;
                end
            endcase
        end
    end
end

`endif

endmodule
