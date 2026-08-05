 /*
 Copyright 2020 Blue Liang, liangkangnan@163.com

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

`include "../core/defines.v"

// tinyriscv soc顶层模块
module cpu2_tinyriscv_soc_top(

    input wire clk,
    input wire rst,

    output wire over,
    output wire succ,

    input wire uart_debug_pin,

    output wire uart_tx_pin,
    input wire uart_rx_pin,

    input  wire [7:0] bridge_i,
    output wire [7:0] bridge_o,

    output wire [3:0] pwm,

    input  wire scl_in,
    output wire scl_o,
    output wire scl_oe,
    input  wire sda_in,
    output wire sda_o,
    output wire sda_oe
    );


    // master 0 interface (CPU data access)
    wire[`MemAddrBus] m0_addr_i;
    wire[`MemBus] m0_data_i;
    wire[`MemBus] m0_data_o;
    wire m0_req_i;
    wire m0_we_i;

    // master 1 interface (CPU instruction fetch)
    wire[`MemAddrBus] m1_addr_i;
    wire[`MemBus] m1_data_i;
    wire[`MemBus] m1_data_o;
    wire m1_req_i;
    wire m1_we_i;

    // master 3 interface (uart_debug)
    wire[`MemAddrBus] m3_addr_i;
    wire[`MemBus] m3_data_i;
    wire[`MemBus] m3_data_o;
    wire m3_req_i;
    wire m3_we_i;

    // slave 0 interface (ROM via mem_bridge)
    wire[`MemAddrBus] s0_addr_o;
    wire[`MemBus] s0_data_o;
    wire[`MemBus] s0_data_i;
    wire s0_we_o;

    // slave 1 interface (RAM via mem_bridge)
    wire[`MemAddrBus] s1_addr_o;
    wire[`MemBus] s1_data_o;
    wire[`MemBus] s1_data_i;
    wire s1_we_o;

    // slave 3 interface (UART)
    wire[`MemAddrBus] s3_addr_o;
    wire[`MemBus] s3_data_o;
    wire[`MemBus] s3_data_i;
    wire s3_we_o;

    // slave 6 interface (PWM)
    wire[`MemAddrBus] s6_addr_o;
    wire[`MemBus] s6_data_o;
    wire[`MemBus] s6_data_i;
    wire s6_we_o;

    // slave 7 interface (I2C)
    wire[`MemAddrBus] s7_addr_o;
    wire[`MemBus] s7_data_o;
    wire[`MemBus] s7_data_i;
    wire s7_we_o;

    // ============================================================
    // 同步器：uart_debug_pin 是外部异步信号
    // ============================================================
    reg uart_debug_sync0;
    reg uart_debug_sync1;
    wire uart_debug_synced;

    always @(posedge clk) begin
        uart_debug_sync0 <= uart_debug_pin;
        uart_debug_sync1 <= uart_debug_sync0;
    end

    assign uart_debug_synced = uart_debug_sync1;

    // rib hold flag
    wire rib_hold_flag_o;

    // mem_bridge req signals
    wire s0_req_i = m0_req_i | m3_req_i;
    wire s1_req_i = m0_req_i | m3_req_i;

    // tinyriscv处理器核模块例化
    cpu2_tinyriscv u_tinyriscv(
        .clk(clk),
        .rst(rst),
        .over(over),
        .succ(succ),
        .rib_ex_addr_o(m0_addr_i),
        .rib_ex_data_i(m0_data_o),
        .rib_ex_data_o(m0_data_i),
        .rib_ex_req_o(m0_req_i),
        .rib_ex_we_o(m0_we_i),

        .rib_pc_addr_o(m1_addr_i),
        .rib_pc_data_i(m1_data_o),

        .rib_hold_flag_i(rib_hold_flag_o)
    );

    // 外部内存桥接 (slave_0 -> external ROM, slave_1 -> external RAM)
    cpu2_mem_bridge u_mem_bridge(
        .clk(clk),
        .rst(rst),
        .s0_req_i(s0_req_i),
        .s0_we_i(s0_we_o),
        .s0_addr_i(s0_addr_o),
        .s0_data_i(s0_data_o),
        .s0_data_o(s0_data_i),

        .s1_req_i(s1_req_i),
        .s1_we_i(s1_we_o),
        .s1_addr_i(s1_addr_o),
        .s1_data_i(s1_data_o),
        .s1_data_o(s1_data_i),

        .ext_data_i(bridge_i),
        .ext_data_o(bridge_o),
        .hold_flag_o()
    );

    // uart模块例化
    cpu2_uart uart_0(
        .clk(clk),
        .rst(rst),
        .we_i(s3_we_o),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .tx_pin(uart_tx_pin),
        .rx_pin(uart_rx_pin)
    );

    // PWM模块实例化 (挂在slave_6)
    cpu2_pwm u_pwm(
        .clk(clk),
        .rst(rst),
        .we_i(s6_we_o),
        .addr_i(s6_addr_o),
        .data_i(s6_data_o),
        .pwm_o(pwm)
    );

    // I2C Master模块例化 (挂在slave_7, 三态门pad接口)
    cpu2_i2c u_i2c_master(
        .clk(clk),
        .rst(rst),
        .addr_i(s7_addr_o),
        .data_i(s7_data_o),
        .data_o(s7_data_i),
        .we_i(s7_we_o),
        .scl_o(scl_o),
        .scl_oe(scl_oe),
        .sda_o(sda_o),
        .sda_oe(sda_oe),
        .sda_in(sda_in)
    );

    // rib模块例化
    cpu2_rib u_rib(
        .clk(clk),
        .rst(rst),

        // master 0 interface
        .m0_addr_i(m0_addr_i),
        .m0_data_i(m0_data_i),
        .m0_data_o(m0_data_o),
        .m0_req_i(m0_req_i),
        .m0_we_i(m0_we_i),

        // master 1 interface
        .m1_addr_i(m1_addr_i),
        .m1_data_i(`ZeroWord),
        .m1_data_o(m1_data_o),
        .m1_req_i(`RIB_REQ),
        .m1_we_i(`WriteDisable),

        // master 3 interface
        .m3_addr_i(m3_addr_i),
        .m3_data_i(m3_data_i),
        .m3_data_o(m3_data_o),
        .m3_req_i(m3_req_i),
        .m3_we_i(m3_we_i),

        // slave 0 interface
        .s0_addr_o(s0_addr_o),
        .s0_data_o(s0_data_o),
        .s0_data_i(s0_data_i),
        .s0_we_o(s0_we_o),

        // slave 1 interface
        .s1_addr_o(s1_addr_o),
        .s1_data_o(s1_data_o),
        .s1_data_i(s1_data_i),
        .s1_we_o(s1_we_o),

        // slave 3 interface
        .s3_addr_o(s3_addr_o),
        .s3_data_o(s3_data_o),
        .s3_data_i(s3_data_i),
        .s3_we_o(s3_we_o),

        // slave 6 interface (PWM)
        .s6_addr_o(s6_addr_o),
        .s6_data_o(s6_data_o),
        .s6_data_i(s6_data_i),
        .s6_we_o(s6_we_o),

        // slave 7 interface (I2C)
        .s7_addr_o(s7_addr_o),
        .s7_data_o(s7_data_o),
        .s7_data_i(s7_data_i),
        .s7_we_o(s7_we_o),

        .hold_flag_o(rib_hold_flag_o)
    );

    // PWM不再输出读数据，s6_data_i直接接地
    assign s6_data_i = `ZeroWord;

    // 串口下载模块例化
    cpu2_uart_debug u_uart_debug(
        .clk(clk),
        .rst(rst),
        .debug_en_i(uart_debug_synced),
        .req_o(m3_req_i),
        .mem_we_o(m3_we_i),
        .mem_addr_o(m3_addr_i),
        .mem_wdata_o(m3_data_i),
        .mem_rdata_i(m3_data_o),
        .ack_i(1'b1)
    );

endmodule
