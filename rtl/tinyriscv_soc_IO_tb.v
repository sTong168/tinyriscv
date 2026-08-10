`timescale 1 ns / 1 ps

`include "core/defines.v"

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

    wire [31:0] ex_end_flag    = u_bf01.u_ram._ram[4];
    wire [31:0] begin_signature = u_bf01.u_ram._ram[2];
    wire [31:0] end_signature   = u_bf01.u_ram._ram[3];

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

    initial begin
        clk = 0;
        rst = `RstEnable;

        chip_sel = 2'b00;
        scl_oe = 0; scl_o = 0; sda_oe = 0; sda_o = 0;

        uart_de = 1'b0;
        uart_rx_reg = 1'b1;

        $display("test running...");

        #40
        rst = `RstDisable;
        #200

        wait(ex_end_flag == 32'h1);  // wait sim end

        $finish;
    end

    // sim timeout
    initial begin
        #5000000
        $display("Time Out.");
        $finish;
    end

    // read mem data
    initial begin
        $readmemh ("inst.data", u_bf01.u_rom._rom);
    end

    // generate wave file
    initial begin
        $fsdbDumpfile("tb.fsdb");
        $fsdbDumpvars(0, riscv_soc_IO_tb);
        $fsdbDumpMDA(0, riscv_soc_IO_tb);
    end

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
    //  Bridge FPGA models (one per CPU family)
    //  cpu0/cpu1: 16-bit bridge_fpga (rtl/fpga/cpu0/)
    //  cpu2:      8-bit cpu2_bridge_fpga (rtl/fpga/cpu2/)
    //  cpu3:      8-bit fpga_bridge_top (rtl/fpga/cpu3/)
    //
    //  bridge_io[7:0]  = mfpga_mem_out (chip -> FPGA)
    //  bridge_io[15:8] = mfpga_mem_in  (FPGA -> chip)
    // =============================

    wire [7:0]  bf2_data_o;
    wire [7:0]  bf3_bridge_o;

    // 16-bit bridge for cpu0 & cpu1 (identical interface, shared instance)
    bridge_fpga u_bf01(
        .clk(clk),
        .rst(rst),
        .bridge_io({mfpga_mem_in, mfpga_mem_out})
    );

    // 8-bit bridge for cpu2
    cpu2_bridge_fpga u_bf2(
        .clk(clk),
        .rst(rst),
        .chip_data_i(mfpga_mem_out),
        .chip_data_o(bf2_data_o)
    );

    // 8-bit bridge for cpu3 (includes external_rom + external_ram internally)
    fpga_bridge_top u_bf3(
        .clk(clk),
        .rst(rst),
        .bridge_i(mfpga_mem_out),
        .bridge_o(bf3_bridge_o)
    );

endmodule
