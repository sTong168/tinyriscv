`timescale 1 ns / 1 ps

`include "cpu0/core/defines.v"

//`define TEST_PROG  1
//`define TEST_JTAG  1
//`define TEST_I2C   1
////`define TEST_UART_DEBUG 1
//`define TEST_I2C_V2   1

`ifdef TEST_I2C
    `ifndef I2C_TEST_DATA0
        `define I2C_TEST_DATA0  8'hAA
    `endif
    `ifndef I2C_TEST_DATA1
        `define I2C_TEST_DATA1  8'h55
    `endif
`endif

`ifdef TEST_I2C_V2
    `ifndef V2_TEST_DATA0
        `define V2_TEST_DATA0  8'hAA
    `endif
    `ifndef V2_TEST_DATA1
        `define V2_TEST_DATA1  8'h55
    `endif
`endif

// testbench module for tinyriscv_top_IO
module riscv_soc_IO_tb;

    // ---- Input PADs ----
    reg         clk;
    reg         rst;
    reg  [1:0]  chip_sel;
    reg         uart_de;

    always #10 clk = ~clk;     // 50MHz

    // ---- Output PADs ----
    wire        over;
    wire        succ;
    wire        uart_tx;
    reg         uart_rx_reg;
    wire        uart_rx;
    assign uart_rx = uart_rx_reg;
    wire [3:0]  pwm;

    // ---- Bidirectional PADs: Bridge ----
    wire [7:0]  mfpga_mem_out;
    wire [7:0]  mfpga_mem_in;

    // ---- Bidirectional PADs: I2C ----
    wire        msda;
    wire        mscl;

    // I2C slave model tri-state (scl/sda driven by slave or released)
    reg         scl_oe, scl_o, sda_oe, sda_o;
    assign mscl = scl_oe ? scl_o : 1'bz;
    assign msda = sda_oe ? sda_o : 1'bz;

    // ---- Internal probe wires (shared regs) ----
    wire [`RegBus] x3  = tinyriscv_top_IO_0.u_soc.u_regs.regs[3];
    wire [`RegBus] x26 = tinyriscv_top_IO_0.u_soc.u_regs.regs[26];
    wire [`RegBus] x27 = tinyriscv_top_IO_0.u_soc.u_regs.regs[27];

    wire [31:0] ex_end_flag    = u_bridge_fpga.u_ram._ram[4];
    wire [31:0] begin_signature = u_bridge_fpga.u_ram._ram[2];
    wire [31:0] end_signature   = u_bridge_fpga.u_ram._ram[3];

    integer r;
    integer fd;

    // ---- UART debug download simulation ----
    localparam UART_BIT_NS = 8820;  // 50MHz, BAUD=0x1B8, bit period = 441*20ns
    reg [7:0] test_packet [0:130];
    reg [31:0] prog_mem [0:`RomNum-1];
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

    task uart_send_packet(input integer len);
        integer pi;
        begin
            for (pi = 0; pi < len; pi = pi + 1)
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
    wire[39:0] req_data = tinyriscv_top_IO_0.u_soc.u_jtag_top.u_jtag_driver.dtm_req_data;
    wire[4:0] ir_reg = tinyriscv_top_IO_0.u_soc.u_jtag_top.u_jtag_driver.ir_reg;
    wire dtm_req_valid = tinyriscv_top_IO_0.u_soc.u_jtag_top.u_jtag_driver.dtm_req_valid;
    wire[31:0] dmstatus = tinyriscv_top_IO_0.u_soc.u_jtag_dm.dmstatus;
`endif

    initial begin
        clk = 0;
        rst = `RstEnable;

        chip_sel = 2'b00;
        scl_oe = 0; scl_o = 0; sda_oe = 0; sda_o = 0;
`ifdef TEST_JTAG
        TCK = 1;
        TMS = 1;
        TDI = 1;
`endif
        uart_de = 1'b0;
        uart_rx_reg = 1'b1;
`ifdef TEST_UART_DEBUG
        uart_de = 1'b1;
        uart_rx_reg = 1'b1;
        #40
        rst = `RstDisable;       // release reset after 40ns pulse
        #200;                    // let uart_debug init UART baud rate

        $readmemh("inst.data", prog_mem);
        data_words = 0;
        for (r = 0; r < `RomNum; r = r + 1) begin
            if (prog_mem[r] !== 32'bx)
                data_words = r + 1;
        end
        total_bytes = data_words * 4;

        // ==== Packet 0: filename + file size (35 bytes) ====
        test_packet[0] = 0;
        test_packet[1]  = 8'h69; test_packet[2]  = 8'h6e; test_packet[3]  = 8'h73;
        test_packet[4]  = 8'h74; test_packet[5]  = 8'h2e; test_packet[6]  = 8'h62;
        test_packet[7]  = 8'h69; test_packet[8]  = 8'h6e;
        for (byte_idx = 9; byte_idx < 25; byte_idx = byte_idx + 1)
            test_packet[byte_idx] = 8'h00;
        test_packet[25] = (total_bytes >> 24) & 8'hff;
        test_packet[26] = (total_bytes >> 16) & 8'hff;
        test_packet[27] = (total_bytes >>  8) & 8'hff;
        test_packet[28] = (total_bytes >>  0) & 8'hff;
        for (byte_idx = 29; byte_idx < 33; byte_idx = byte_idx + 1)
            test_packet[byte_idx] = 8'h00;
        crc_val = calc_crc16(1, 32);
        test_packet[33] = crc_val[7:0];
        test_packet[34] = crc_val[15:8];

        #100000;
        uart_send_packet(35);
        #50000;
        $display("Packet 0 sent (%0d bytes total)", total_bytes);

        pkt_num = 1;
        byte_idx = 0;
        pkt_total = (total_bytes >> 5) + 1;
        for (r = 0; r < data_words; r = r + 1) begin
            tmp_word = prog_mem[r];
            test_packet[byte_idx + 1] = tmp_word[7:0];
            test_packet[byte_idx + 2] = tmp_word[15:8];
            test_packet[byte_idx + 3] = tmp_word[23:16];
            test_packet[byte_idx + 4] = tmp_word[31:24];
            byte_idx = byte_idx + 4;

            if (byte_idx == 32 || r == data_words - 1) begin
                test_packet[0] = pkt_num[7:0];
                for (pi = byte_idx; pi < 32; pi = pi + 1)
                    test_packet[pi + 1] = 8'h00;
                crc_val = calc_crc16(1, 32);
                test_packet[33] = crc_val[7:0];
                test_packet[34] = crc_val[15:8];
                #50000;
                uart_send_packet(35);
                $display("Packet %0d sent (%0d data bytes)", pkt_num, byte_idx);
                #50000;
                pkt_num = pkt_num + 1;
                byte_idx = 0;
            end
        end
        while (pkt_num <= pkt_total) begin
            test_packet[0] = pkt_num[7:0];
            for (pi = 1; pi < 33; pi = pi + 1)
                test_packet[pi] = 8'h00;
            crc_val = calc_crc16(1, 32);
            test_packet[33] = crc_val[7:0];
            test_packet[34] = crc_val[15:8];
            #50000;
            uart_send_packet(35);
            $display("Empty packet %0d sent", pkt_num);
            #50000;
            pkt_num = pkt_num + 1;
        end

        #100000;
        uart_de = 1'b0;
        $display("All %0d packets sent, uart_de released", pkt_num - 1);
`endif
        $display("test running...");
`ifndef TEST_UART_DEBUG
        #40
        rst = `RstDisable;
        #200
`endif

        wait(ex_end_flag == 32'h1);  // wait sim end

`ifdef TEST_JTAG
        // reset
        for (i = 0; i < 8; i++) begin
            TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        end

        // IR
        shift_reg = 40'b10001;

        // IDLE
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SELECT-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SELECT-IR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // CAPTURE-IR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-IR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-IR & EXIT1-IR
        for (i = 5; i > 0; i--) begin
            if (shift_reg[0]) TDI = 1'b1; else TDI = 1'b0;
            if (i == 1) TMS = 1;
            TCK = 0; #100; in = TDO; TCK = 1; #100; TCK = 0;
            shift_reg = {{(35){1'b0}}, in, shift_reg[4:1]};
        end
        // PAUSE-IR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // EXIT2-IR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // UPDATE-IR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // IDLE x4
        repeat(4) begin TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0; end

        // dmi write
        shift_reg = {6'h10, {(32){1'b0}}, 2'b10};
        // SELECT-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // CAPTURE-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0]) TDI = 1'b1; else TDI = 1'b0;
            if (i == 1) TMS = 1;
            TCK = 0; #100; in = TDO; TCK = 1; #100; TCK = 0;
            shift_reg = {in, shift_reg[39:1]};
        end
        // PAUSE-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // EXIT2-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // UPDATE-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // IDLE x4
        repeat(4) begin TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0; end

        $display("ir_reg = 0x%x", ir_reg);
        $display("dtm_req_valid = %d", dtm_req_valid);
        $display("req_data = 0x%x", req_data);

        // IDLE x3
        repeat(3) begin TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0; end

        $display("dmstatus = 0x%x", dmstatus);

        // SELECT-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // dmi read
        shift_reg = {6'h11, {(32){1'b0}}, 2'b01};
        // CAPTURE-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0]) TDI = 1'b1; else TDI = 1'b0;
            if (i == 1) TMS = 1;
            TCK = 0; #100; in = TDO; TCK = 1; #100; TCK = 0;
            shift_reg = {in, shift_reg[39:1]};
        end
        // PAUSE-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // EXIT2-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // UPDATE-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // IDLE x4
        repeat(4) begin TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0; end;

        // SELECT-DR
        TMS = 1; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // dmi read
        shift_reg = {6'h11, {(32){1'b0}}, 2'b00};
        // CAPTURE-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-DR
        TMS = 0; TCK = 0; #100; TCK = 1; #100; TCK = 0;
        // SHIFT-DR & EXIT1-DR
        for (i = 40; i > 0; i--) begin
            if (shift_reg[0]) TDI = 1'b1; else TDI = 1'b0;
            if (i == 1) TMS = 1;
            TCK = 0; #100; in = TDO; TCK = 1; #100; TCK = 0;
            shift_reg = {in, shift_reg[39:1]};
        end

        #100;
        $display("shift_reg = 0x%x", shift_reg[33:2]);
`endif

        $finish;
    end

    // sim timeout
    initial begin
        #5000000
        $display("Time Out.");
        $finish;
    end

    // read mem data
`ifndef TEST_UART_DEBUG
    initial begin
        $readmemh ("inst.data", u_bridge_fpga.u_rom._rom);
    end
`endif

    // generate wave file
    initial begin
        $fsdbDumpfile("tb.fsdb");
        $fsdbDumpvars(0, riscv_soc_IO_tb);
        $fsdbDumpMDA(0, riscv_soc_IO_tb);
    end

`ifdef TEST_UART_DEBUG
    // ---- Debug monitor for shared uart_debug ----
    wire [13:0] dbg_state    = tinyriscv_top_IO_0.u_soc.u_uart_debug.state;
    wire [7:0]  dbg_need_rec = tinyriscv_top_IO_0.u_soc.u_uart_debug.need_to_rec_bytes;
    wire [15:0] dbg_rem_pkt  = tinyriscv_top_IO_0.u_soc.u_uart_debug.remain_packet_count;
    wire [7:0]  dbg_byte_idx0= tinyriscv_top_IO_0.u_soc.u_uart_debug.write_mem_byte_index0;
    wire [31:0] dbg_wr_addr  = tinyriscv_top_IO_0.u_soc.u_uart_debug.write_mem_addr;
    wire [15:0] dbg_crc_res  = tinyriscv_top_IO_0.u_soc.u_uart_debug.crc_result;
    wire [7:0]  dbg_rx_crc_h = tinyriscv_top_IO_0.u_soc.u_uart_debug.rx_data[130];
    wire [7:0]  dbg_rx_crc_l = tinyriscv_top_IO_0.u_soc.u_uart_debug.rx_data[129];
    wire [31:0] dbg_fw_size  = tinyriscv_top_IO_0.u_soc.u_uart_debug.fw_file_size;
    wire        dbg_ack      = tinyriscv_top_IO_0.u_soc.u_uart_debug.ack_i;
    wire        dbg_we       = tinyriscv_top_IO_0.u_soc.u_uart_debug.mem_we_o;

    reg [13:0] dbg_state_prev;
    always @(posedge clk) begin
        dbg_state_prev <= dbg_state;
        if (dbg_state != dbg_state_prev) begin
            case (dbg_state)
                14'h1000: begin
                    $display("[%0t] S_CRC_END: need_rec=%0d rem_pkt=%0d crc_res=0x%h rx_crc=0x%h%h fw_size=%0d",
                             $time, dbg_need_rec, dbg_rem_pkt, dbg_crc_res, dbg_rx_crc_h, dbg_rx_crc_l, dbg_fw_size);
                end
                14'h2000: begin
                    $display("[%0t] S_WRITE_MEM: byte_idx0=%0d need_rec=%0d wr_addr=0x%h ack=%0d we=%0d",
                             $time, dbg_byte_idx0, dbg_need_rec, dbg_wr_addr, dbg_ack, dbg_we);
                end
                14'h0100: begin
                    $display("[%0t] S_SEND_ACK: rem_pkt=%0d", $time, dbg_rem_pkt);
                end
                14'h0200: begin
                    $display("[%0t] S_SEND_NACK: rem_pkt=%0d", $time, dbg_rem_pkt);
                end
            endcase
        end
    end
`endif

    // =============================
    //  DUT: tinyriscv_top_IO
    // =============================
    tinyriscv_top_IO tinyriscv_top_IO_0(
        .clk          (clk),
        .rst          (rst),
        .chip_sel     (chip_sel),
        .uart_de      (uart_de),
        .over         (over),
        .succ         (succ),
        .uart_tx      (uart_tx),
        .uart_rx      (uart_rx),
        .pwm          (pwm),
        .mfpga_mem_out(mfpga_mem_out),
        .mfpga_mem_in (mfpga_mem_in),
        .msda         (msda),
        .mscl         (mscl)
    );

    // =============================
    //  Bridge FPGA model
    //  bridge_io[7:0]  = mfpga_mem_out
    //  bridge_io[15:8] = mfpga_mem_in
    // =============================
    bridge_fpga u_bridge_fpga(
        .clk(clk),
        .rst(rst),
        .bridge_io({mfpga_mem_in, mfpga_mem_out})
    );

    // =============================
    //  I2C Slave model (TEST_I2C)
    // =============================
`ifdef TEST_I2C

    reg sda_s1, sda_s2;
    reg scl_s1, scl_s2;

    always @(posedge clk) begin
        sda_s1 <= msda; sda_s2 <= sda_s1;
        scl_s1 <= mscl; scl_s2 <= scl_s1;
    end

    wire sda_fall =  sda_s2 && ~sda_s1;
    wire sda_rise = ~sda_s2 &&  sda_s1;
    wire scl_rise = ~scl_s2 &&  scl_s1;
    wire scl_fall =  scl_s2 && ~scl_s1;
    wire i2c_start = sda_fall && scl_s1;
    wire i2c_stop  = sda_rise && scl_s1;

    localparam I2C_IDLE = 3'd0;
    localparam I2C_RECV = 3'd1;
    localparam I2C_SACK = 3'd2;
    localparam I2C_SEND = 3'd3;
    localparam I2C_MACK = 3'd4;

    localparam I2C_TEST_DATA0 = `I2C_TEST_DATA0;
    localparam I2C_TEST_DATA1 = `I2C_TEST_DATA1;

    reg [2:0] i2c_state;
    reg [7:0] i2c_sreg;
    reg [3:0] i2c_bcnt;
    reg [7:0] i2c_txbuf;
    reg       i2c_dir;
    reg       i2c_phase;
    reg [1:0] i2c_rcnt;

    initial begin
        i2c_txbuf = I2C_TEST_DATA0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst == `RstEnable) begin
            i2c_state <= I2C_IDLE; i2c_bcnt <= 0; i2c_sreg <= 0;
            i2c_phase <= 0; i2c_rcnt <= 0;
            sda_oe <= 0; sda_o <= 0;
        end else begin
            if (i2c_start) begin
                if (i2c_state == I2C_SACK) i2c_rcnt <= i2c_rcnt + 1;
                i2c_state <= I2C_RECV; i2c_bcnt <= 0; i2c_sreg <= 0; sda_oe <= 0;
            end else if (i2c_stop) begin
                i2c_state <= I2C_IDLE; i2c_bcnt <= 0; i2c_rcnt <= 0; sda_oe <= 0;
            end else begin
                case (i2c_state)
                    I2C_IDLE: begin sda_oe <= 0; i2c_bcnt <= 0; i2c_phase <= 0; i2c_rcnt <= 0; end
                    I2C_RECV: begin
                        if (scl_rise && i2c_bcnt < 8) begin
                            i2c_sreg <= {i2c_sreg[6:0], sda_s1};
                            i2c_bcnt <= i2c_bcnt + 1;
                        end
                        if (i2c_bcnt == 8 && scl_fall) begin
                            i2c_dir <= i2c_sreg[0]; i2c_state <= I2C_SACK;
                        end
                    end
                    I2C_SACK: begin
                        sda_oe <= 1; sda_o <= 0;
                        if (scl_fall) begin
                            i2c_bcnt <= 0; i2c_rcnt <= i2c_rcnt + 1;
                            if (i2c_rcnt == 2'd2) begin
                                i2c_state <= I2C_SEND;
                                i2c_txbuf <= {I2C_TEST_DATA0[6:0], 1'b0};
                                sda_oe <= 1; sda_o <= I2C_TEST_DATA0[7];
                            end else begin
                                sda_oe <= 0; i2c_state <= I2C_RECV; i2c_sreg <= 0;
                            end
                        end
                    end
                    I2C_SEND: begin
                        if (scl_fall && i2c_bcnt < 7) begin
                            sda_oe <= 1; sda_o <= i2c_txbuf[7];
                            i2c_txbuf <= {i2c_txbuf[6:0], 1'b0};
                            i2c_bcnt <= i2c_bcnt + 1;
                        end
                        if (i2c_bcnt == 7 && scl_fall) begin
                            sda_oe <= 0; i2c_state <= I2C_MACK;
                        end
                    end
                    I2C_MACK: begin
                        if (scl_fall) begin
                            if (sda_s2 == 0) begin
                                i2c_state <= I2C_SEND; i2c_bcnt <= 0;
                                i2c_txbuf <= {I2C_TEST_DATA1[6:0], 1'b0};
                                sda_o <= I2C_TEST_DATA1[7]; sda_oe <= 1;
                            end else begin
                                i2c_state <= I2C_IDLE; i2c_bcnt <= 0;
                                sda_oe <= 0; sda_o <= 0;
                            end
                        end
                    end
                    default: begin i2c_state <= I2C_IDLE; sda_oe <= 0; end
                endcase
            end
        end
    end

`elsif TEST_I2C_V2

    reg v2_s1, v2_s2, v2_d1, v2_d2;

    always @(posedge clk) begin
        v2_s1 <= mscl; v2_s2 <= v2_s1;
        v2_d1 <= msda; v2_d2 <= v2_d1;
    end

    wire v2_sre  = ~v2_s2 &  v2_s1;
    wire v2_sfe  =  v2_s2 & ~v2_s1;
    wire v2_dfe  =  v2_d2 & ~v2_d1;
    wire v2_start = v2_dfe & v2_s1;

    localparam V2_IDLE=0, V2_RECV=1, V2_SACK=2, V2_SEND0=3, V2_MACK=4, V2_SEND1=5;

    localparam V2_DATA0 = `V2_TEST_DATA0;
    localparam V2_DATA1 = `V2_TEST_DATA1;

    reg [2:0] vs;
    reg [3:0] vb;
    reg [7:0] vr;
    reg [7:0] vt;

    always @(posedge clk or posedge rst) begin
        if (rst == `RstEnable) begin
            vs <= V2_IDLE; vb <= 0; vr <= 0;
            sda_oe <= 0; sda_o <= 0; vt <= V2_DATA0;
        end else begin
            if (v2_start) begin
                vs <= V2_RECV; vb <= 0; vr <= 0; sda_oe <= 0;
            end

            case (vs)
                V2_IDLE: begin sda_oe <= 0; vb <= 0; end
                V2_RECV: begin
                    if (v2_sre && vb < 8) begin
                        vr <= {vr[6:0], v2_d1};
                        vb <= vb + 1;
                    end
                    if (vb == 8 && v2_sfe) begin
                        vs <= V2_SACK; vb <= 0;
                        sda_oe <= 1; sda_o <= 0;
                    end
                end
                V2_SACK: begin
                    sda_oe <= 1; sda_o <= 0;
                    if (v2_sfe) begin
                        vs <= V2_SEND0; vb <= 0;
                        vt <= {V2_DATA0[6:0], 1'b0};
                        sda_oe <= 1; sda_o <= V2_DATA0[7];
                    end
                end
                V2_SEND0: begin
                    if (v2_sfe && vb < 7) begin
                        sda_oe <= 1; sda_o <= vt[7];
                        vt <= {vt[6:0], 1'b0};
                        vb <= vb + 1;
                    end
                    if (vb == 7 && v2_sfe) begin
                        sda_oe <= 0; vs <= V2_MACK;
                    end
                end
                V2_MACK: begin
                    if (v2_sfe) begin
                        vs <= V2_SEND1; vb <= 0;
                        vt <= {V2_DATA1[6:0], 1'b0};
                        sda_oe <= 1; sda_o <= V2_DATA1[7];
                    end
                end
                V2_SEND1: begin
                    if (v2_sfe && vb < 7) begin
                        sda_oe <= 1; sda_o <= vt[7];
                        vt <= {vt[6:0], 1'b0};
                        vb <= vb + 1;
                    end
                    if (vb == 7 && v2_sfe) begin
                        sda_oe <= 0; vs <= V2_IDLE;
                    end
                end
                default: begin vs <= V2_IDLE; sda_oe <= 0; end
            endcase
        end
    end

`endif

endmodule
