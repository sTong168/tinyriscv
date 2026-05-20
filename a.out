`timescale 1 ns / 1 ps

 /*                                                                      
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
 Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */




















































// I type inst










// L type inst







// S type inst





// R and M type inst

// R type inst








// M type inst









// J type inst














// J type inst








// CSR inst








// CSR reg addr









// Custom SID instruction (opcode 0x2f = custom-0)





// I2C read base address


// Student ID digits (ASCII) — 学号: 2025210875






















// common regs







// I2C controller macros





//`define TEST_PROG  1
//`define TEST_JTAG  1
//`define TEST_I2C   1
//`define TEST_UART_DEBUG 1











    
        
    
    
        
    



// testbench module
module tinyriscv_soc_tb;

    reg clk;
    reg rst;


    always #10 clk = ~clk;     // 50MHz

    wire [15:0] bridge;
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

    wire[31:0] x3 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[3];
    wire[31:0] x26 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[26];
    wire[31:0] x27 = tinyriscv_soc_top_0.u_tinyriscv.u_regs.regs[27];

    wire[31:0] ex_end_flag = u_bridge_fpga.u_ram._ram[4];
    wire[31:0] begin_signature = u_bridge_fpga.u_ram._ram[2];
    wire[31:0] end_signature = u_bridge_fpga.u_ram._ram[3];

    integer r;
    integer fd;

    // ---- UART debug download simulation ----
    localparam UART_BIT_NS = 8820;  // 50MHz, BAUD=0x1B8, bit period = 441*20ns
    reg [7:0] test_packet [0:130];
    reg [31:0] prog_mem [0:256-1];  // temp storage for program data
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
        rst = 1'b0;

        scl_oe=0; scl_o=0; sda_oe=0; sda_o=0;





        uart_debug_pin = 1'b0;


































































































        $display("test running...");

        #40
        rst = 1'b1;
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









































































































































































// ============================================================
// I2C V2 Slave — 只接收 Addr+R, 发两字节数据
// 协议: START + Addr+R(0x91) + ACK + byte0 + MACK + byte1 + MNACK + STOP
// ============================================================

// SCL/SDA 同步
reg  v2_sda_s1, v2_sda_s2;
reg  v2_scl_s1, v2_scl_s2;

always @(posedge clk) begin
    v2_sda_s1 <= sda; v2_sda_s2 <= v2_sda_s1;
    v2_scl_s1 <= scl; v2_scl_s2 <= v2_scl_s1;
end

wire v2_scl_rise = ~v2_scl_s2 &  v2_scl_s1;
wire v2_scl_fall =  v2_scl_s2 & ~v2_scl_s1;
wire v2_sda_fall =  v2_sda_s2 & ~v2_sda_s1;
wire v2_start    = v2_sda_fall & v2_scl_s1;

localparam V2_IDLE=0, V2_RECV=1, V2_SACK=2, V2_SEND=3, V2_MACK=4;

localparam V2_DATA0 = 8'hAA;
localparam V2_DATA1 = 8'h55;

reg [2:0] v2_state;
reg [3:0] v2_bcnt;
reg [7:0] v2_sreg;
reg [1:0] v2_rcnt;
reg [7:0] v2_txbuf;

always @(posedge clk or posedge rst) begin
    if (rst == 1'b0) begin
        v2_state <= V2_IDLE; v2_bcnt <= 0; v2_sreg <= 0; v2_rcnt <= 0;
        sda_oe <= 0; sda_o <= 0; v2_txbuf <= V2_DATA0;
    end else begin
        // START 复位
        if (v2_start) begin
            v2_state <= V2_RECV; v2_bcnt <= 0; v2_sreg <= 0; sda_oe <= 0;
        end

        case (v2_state)
            V2_IDLE: begin sda_oe <= 0; v2_bcnt <= 0; v2_rcnt <= 0; end

            V2_RECV: begin
                // SCL上升沿采样
                if (v2_scl_rise && v2_bcnt < 8) begin
                    v2_sreg <= {v2_sreg[6:0], v2_sda_s1};
                    v2_bcnt <= v2_bcnt + 1;
                end
                // 收完1字节 → 应答
                if (v2_bcnt == 8 && v2_scl_fall) begin
                    v2_state <= V2_SACK;
                end
            end

            V2_SACK: begin
                sda_oe <= 1; sda_o <= 0;  // ACK
                if (v2_scl_fall) begin
                    v2_bcnt <= 0;
                    v2_rcnt <= v2_rcnt + 1;
                    if (v2_rcnt == 2'd1) begin  // 第一个ACK后发数据
                        v2_state <= V2_SEND;
                        v2_txbuf <= {V2_DATA0[6:0], 1'b0};
                        sda_oe <= 1; sda_o <= V2_DATA0[7];
                    end else begin
                        sda_oe <= 0;
                        v2_state <= V2_RECV;
                    end
                end
            end

            V2_SEND: begin
                if (v2_scl_fall && v2_bcnt < 7) begin
                    sda_oe <= 1; sda_o <= v2_txbuf[7];
                    v2_txbuf <= {v2_txbuf[6:0], 1'b0};
                    v2_bcnt <= v2_bcnt + 1;
                end
                if (v2_bcnt == 7 && v2_scl_fall) begin
                    sda_oe <= 0;  // 释放SDA
                    v2_state <= V2_MACK;
                end
            end

            V2_MACK: begin
                if (v2_scl_fall) begin
                    if (v2_rcnt < 2'd2) begin
                        // 主机ACK → 发下一个字节
                        v2_state <= V2_SEND;
                        v2_bcnt <= 0;
                        v2_rcnt <= v2_rcnt + 1;
                        v2_txbuf <= {V2_DATA1[6:0], 1'b0};
                        sda_oe <= 1; sda_o <= V2_DATA1[7];
                    end else begin
                        // 主机NACK → 结束
                        v2_state <= V2_IDLE;
                        sda_oe <= 0;
                    end
                end
            end

            default: begin v2_state <= V2_IDLE; sda_oe <= 0; end
        endcase
    end
end

// ============================================================
// V2 测试序列 — force I2C 寄存器 (绕过RIB)
// ============================================================
reg [31:0] v2_result;
integer    v2_err;

initial begin
    v2_err = 0;

    // 等 soc 初始化 + CPU 程序跑完
    wait(ex_end_flag == 32'h1);
    #5000;

    $display("");
    $display("=== TEST_I2C_V2 ===");
    $display("  Expecting DATA0=0x%02X DATA1=0x%02X", V2_DATA0, V2_DATA1);

    // ---- 写从设备地址 (0x48 → 0x90) ----
    force tinyriscv_soc_top_0.i2c_0.we_i   = 1'b1;
    force tinyriscv_soc_top_0.i2c_0.addr_i = 32'h70010000;
    force tinyriscv_soc_top_0.i2c_0.data_i = 32'h00000090;
    force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b1;
    @(posedge clk);
    force tinyriscv_soc_top_0.i2c_0.we_i   = 1'b0;
    force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b0;

    // ---- 触发 (值随意) ----
    @(posedge clk);
    force tinyriscv_soc_top_0.i2c_0.we_i   = 1'b1;
    force tinyriscv_soc_top_0.i2c_0.addr_i = 32'h70020000;
    force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b1;
    @(posedge clk);
    force tinyriscv_soc_top_0.i2c_0.we_i   = 1'b0;
    force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b0;

    // ---- 轮询等待完成 ----
    repeat(50000) @(posedge clk);
    forever begin
        force tinyriscv_soc_top_0.i2c_0.we_i   = 1'b0;
        force tinyriscv_soc_top_0.i2c_0.addr_i = 32'h70030000;
        force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b1;
        @(posedge clk);
        v2_result = tinyriscv_soc_top_0.i2c_0.data_o;
        force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b0;

        if (v2_result[31:30] == 2'b10) begin
            $display("  Readback: 0x%08X", v2_result);
            $display("  RX data:  0x%04X (expected: 0x%02X%02X)",
                     v2_result[15:0], V2_DATA0, V2_DATA1);

            if (v2_result[15:0] !== {V2_DATA0, V2_DATA1}) begin
                $display("  *** FAIL: data mismatch! ***");
                v2_err = v2_err + 1;
            end else
                $display("  PASS");

            // 验证清零
            @(posedge clk);
            force tinyriscv_soc_top_0.i2c_0.addr_i = 32'h70030000;
            force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b1;
            @(posedge clk);
            v2_result = tinyriscv_soc_top_0.i2c_0.data_o;
            force tinyriscv_soc_top_0.i2c_0.req_i  = 1'b0;

            if (v2_result[31:30] !== 2'd0) begin
                $display("  *** FAIL: buzy not cleared! ***");
                v2_err = v2_err + 1;
            end else
                $display("  Clear-on-read OK");

            // 释放所有 force
            release tinyriscv_soc_top_0.i2c_0.we_i;
            release tinyriscv_soc_top_0.i2c_0.addr_i;
            release tinyriscv_soc_top_0.i2c_0.data_i;
            release tinyriscv_soc_top_0.i2c_0.req_i;

            if (v2_err == 0)
                $display("=== TEST_I2C_V2 PASS ===");
            else
                $display("=== TEST_I2C_V2 FAIL (%0d errors) ===", v2_err);

            disable V2_DONE;
        end
        @(posedge clk);
    end
    begin V2_DONE:; end
end

  // TEST_I2C_V2

endmodule
