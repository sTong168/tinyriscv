`timescale 1 ns / 1 ps

`include "../../rtl/core/defines.v"


//`define TEST_PROG  1
//`define TEST_JTAG  1
//`define TEST_I2C   1
`define TEST_UART_DEBUG 1

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

    reg uart_debug_pin;
    reg uart_rx_reg;               // 驱动 uart_rx_pin 的寄存器
    wire uart_tx_pin;
    wire uart_rx_pin;
    assign uart_rx_pin = uart_rx_reg;

    wire over;
    wire succ;
    wire halted_ind;

    wire[`RegBus] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    wire[`RegBus] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    wire[`RegBus] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];

    wire[31:0] ex_end_flag = u_bridge_fpga.u_ram._ram[4];
    wire[31:0] begin_signature = u_bridge_fpga.u_ram._ram[2];
    wire[31:0] end_signature = u_bridge_fpga.u_ram._ram[3];

    integer r;
    integer fd;

    // ---- UART debug download simulation ----
    localparam UART_BIT_NS = 8820;  // 50MHz, BAUD=0x1B8, bit period = 441*20ns
    reg [7:0] test_packet [0:130];
    reg [31:0] prog_mem [0:`RomNum-1];  // temp storage for program data
    integer packet_idx, byte_idx, total_bytes, data_words, pkt_num, pi, pkt_total;
    reg [31:0] tmp_word;
    reg [15:0] crc_val;

    function [15:0] calc_crc16(input integer start_idx, end_idx);
        integer ci, cj;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            for (ci = start_idx; ci <= end_idx; ci = ci + 1) begin
                crc = crc ^ {8'h00, test_packet[ci]};
                for (cj = 0; cj < 8; cj = cj + 1) begin
                    if (crc[0])
                        crc = {1'b0, crc[15:1]} ^ 16'hA001;
                    else
                        crc = {1'b0, crc[15:1]};
                end
            end
            calc_crc16 = crc;
        end
    endfunction

    task uart_send_byte(input [7:0] data);
        integer si;
        begin
            uart_rx_reg = 1'b0;           // start bit
            #UART_BIT_NS;
            for (si = 0; si < 8; si = si + 1) begin
                uart_rx_reg = data[si];   // LSB first
                #UART_BIT_NS;
            end
            uart_rx_reg = 1'b1;           // stop bit
            #UART_BIT_NS;
        end
    endtask

    task uart_send_packet;
        integer pi;
        begin
            for (pi = 0; pi < 131; pi = pi + 1)
                uart_send_byte(test_packet[pi]);
        end
    endtask
    // ---- end UART debug simulation ----

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
        uart_debug_pin = 1'b0;
`ifdef TEST_UART_DEBUG
        uart_debug_pin = 1'b1;
        uart_rx_reg = 1'b1;
        #40
        rst = `RstDisable;       // release reset after 40ns pulse
        #200;                    // let uart_debug init UART baud rate

        // Read inst.data into temp memory (NOT into ROM, ROM is written by uart_debug)
        $readmemh("inst.data", prog_mem);
        // Count valid words
        data_words = 0;
        for (r = 0; r < `RomNum; r = r + 1) begin
            if (prog_mem[r] !== 32'bx)
                data_words = r + 1;
        end
        total_bytes = data_words * 4;

        // ==== Packet 0: filename + file size ====
        test_packet[0] = 0;  // packet number
        // filename: "inst.bin" (8 bytes), rest pad to 60 bytes
        test_packet[1]  = 8'h69; // 'i'
        test_packet[2]  = 8'h6e; // 'n'
        test_packet[3]  = 8'h73; // 's'
        test_packet[4]  = 8'h74; // 't'
        test_packet[5]  = 8'h2e; // '.'
        test_packet[6]  = 8'h62; // 'b'
        test_packet[7]  = 8'h69; // 'i'
        test_packet[8]  = 8'h6e; // 'n'
        for (byte_idx = 9; byte_idx < 61; byte_idx = byte_idx + 1)
            test_packet[byte_idx] = 8'h00;
        // file size at indices 61-64 (big-endian)
        test_packet[61] = (total_bytes >> 24) & 8'hff;
        test_packet[62] = (total_bytes >> 16) & 8'hff;
        test_packet[63] = (total_bytes >>  8) & 8'hff;
        test_packet[64] = (total_bytes >>  0) & 8'hff;
        for (byte_idx = 65; byte_idx < 129; byte_idx = byte_idx + 1)
            test_packet[byte_idx] = 8'h00;
        // CRC over data bytes (indices 1..128)
        crc_val = calc_crc16(1, 128);
        test_packet[129] = crc_val[7:0];
        test_packet[130] = crc_val[15:8];

        // Delay to let SoC initialize UART baud rate
        #100000;
        uart_send_packet;
        #500000;
        $display("Packet 0 sent (%0d bytes total)", total_bytes);

        // ==== Data packets ====
        pkt_num = 1;
        byte_idx = 0;
        // Number of data packets = fw_file_size/32 + 1 (matches uart_debug formula)
        pkt_total = (total_bytes >> 5) + 1;  // divide by 32, +1
        for (r = 0; r < data_words; r = r + 1) begin
            tmp_word = prog_mem[r];
            // Each word = 4 bytes, little-endian
            test_packet[byte_idx + 1] = tmp_word[7:0];
            test_packet[byte_idx + 2] = tmp_word[15:8];
            test_packet[byte_idx + 3] = tmp_word[23:16];
            test_packet[byte_idx + 4] = tmp_word[31:24];
            byte_idx = byte_idx + 4;

            if (byte_idx == 128 || r == data_words - 1) begin
                test_packet[0] = pkt_num[7:0];
                for (pi = byte_idx; pi < 128; pi = pi + 1)
                    test_packet[pi + 1] = 8'h00;
                crc_val = calc_crc16(1, 128);
                test_packet[129] = crc_val[7:0];
                test_packet[130] = crc_val[15:8];
                #50000;
                uart_send_packet;
                $display("Packet %0d sent (%0d data bytes)", pkt_num, byte_idx);
                #500000;
                pkt_num = pkt_num + 1;
                byte_idx = 0;
            end
        end
        // Send remaining empty packets to satisfy uart_debug's count
        while (pkt_num <= pkt_total) begin
            test_packet[0] = pkt_num[7:0];
            for (pi = 1; pi < 129; pi = pi + 1)
                test_packet[pi] = 8'h00;
            crc_val = calc_crc16(1, 128);
            test_packet[129] = crc_val[7:0];
            test_packet[130] = crc_val[15:8];
            #50000;
            uart_send_packet;
            $display("Empty packet %0d sent", pkt_num);
            #500000;
            pkt_num = pkt_num + 1;
        end

        // All packets sent, release uart_debug_pin
        #100000;
        uart_debug_pin = 1'b0;
        $display("All %0d packets sent, uart_debug_pin released", pkt_num - 1);
`endif
        $display("test running...");
`ifndef TEST_UART_DEBUG
        #40
        rst = `RstDisable;
        #200
`endif
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
`ifndef TEST_UART_DEBUG
    initial begin
        $readmemh ("inst.data", u_bridge_fpga.u_rom._rom);
    end
`endif

    // generate wave file, used by gtkwave
    initial begin
        $dumpfile("tinyriscv_soc_tb.vcd");
        $dumpvars(0, tinyriscv_soc_tb);
    end

`ifdef TEST_UART_DEBUG
    // ---- Debug monitor for uart_debug ----
    wire [13:0] dbg_state    = tinyriscv_soc_top_0.u_uart_debug.state;
    wire [7:0]  dbg_need_rec = tinyriscv_soc_top_0.u_uart_debug.need_to_rec_bytes;
    wire [15:0] dbg_rem_pkt  = tinyriscv_soc_top_0.u_uart_debug.remain_packet_count;
    wire [7:0]  dbg_byte_idx0= tinyriscv_soc_top_0.u_uart_debug.write_mem_byte_index0;
    wire [31:0] dbg_wr_addr  = tinyriscv_soc_top_0.u_uart_debug.write_mem_addr;
    wire [15:0] dbg_crc_res  = tinyriscv_soc_top_0.u_uart_debug.crc_result;
    wire [7:0]  dbg_rx_crc_h = tinyriscv_soc_top_0.u_uart_debug.rx_data[130];
    wire [7:0]  dbg_rx_crc_l = tinyriscv_soc_top_0.u_uart_debug.rx_data[129];
    wire [31:0] dbg_fw_size  = tinyriscv_soc_top_0.u_uart_debug.fw_file_size;
    wire        dbg_ack      = tinyriscv_soc_top_0.u_uart_debug.ack_i;
    wire        dbg_we       = tinyriscv_soc_top_0.u_uart_debug.mem_we_o;

    reg [13:0] dbg_state_prev;
    always @(posedge clk) begin
        dbg_state_prev <= dbg_state;
        if (dbg_state != dbg_state_prev) begin
            case (dbg_state)
                14'h1000: begin // S_CRC_END
                    $display("[%0t] S_CRC_END: need_rec=%0d rem_pkt=%0d crc_res=0x%h rx_crc=0x%h%h fw_size=%0d",
                             $time, dbg_need_rec, dbg_rem_pkt, dbg_crc_res, dbg_rx_crc_h, dbg_rx_crc_l, dbg_fw_size);
                end
                14'h2000: begin // S_WRITE_MEM
                    $display("[%0t] S_WRITE_MEM: byte_idx0=%0d need_rec=%0d wr_addr=0x%h ack=%0d we=%0d",
                             $time, dbg_byte_idx0, dbg_need_rec, dbg_wr_addr, dbg_ack, dbg_we);
                end
                14'h0100: begin // S_SEND_ACK
                    $display("[%0t] S_SEND_ACK: rem_pkt=%0d", $time, dbg_rem_pkt);
                end
                14'h0200: begin // S_SEND_NAK
                    $display("[%0t] S_SEND_NAK: rem_pkt=%0d", $time, dbg_rem_pkt);
                end
            endcase
        end
    end
`endif

    tinyriscv_soc_top tinyriscv_soc_top_0(
        .clk(clk),
        .rst(rst),
        .over(over),
        .succ(succ),
        .halted_ind(halted_ind),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
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
