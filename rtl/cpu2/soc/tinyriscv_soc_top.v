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

`include "../../shared/defines.v"

// tinyriscv soc顶层模块
module cpu2_tinyriscv_soc_top(

    input wire clk,
    input wire rst,

    output wire uart_tx_pin,
    input wire uart_rx_pin,

    input  wire [7:0] bridge_i,
    output wire [7:0] bridge_o,

    input  wire scl_in,
    output wire scl_o,
    output wire scl_oe,
    input  wire sda_in,
    output wire sda_o,
    output wire sda_oe,

    // shared regs interface (pass-through)
    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input wire[`RegBus]      reg_rdata1_i,
    input wire[`RegBus]      reg_rdata2_i,

    // shared uart_debug bus
    input wire              dbg_req_i,
    input wire              dbg_we_i,
    input wire[`MemAddrBus] dbg_addr_i,
    input wire[`MemBus]     dbg_wdata_i,
    output wire[`MemBus]    dbg_rdata_o,
    output wire             dbg_ack_o,

    // shared PWM bus
    output wire              pwm_we_o,
    output wire[`MemAddrBus] pwm_addr_o,
    output wire[`MemBus]     pwm_data_o
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
    wire m3_ack_o;

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

    // rib hold flags
    // rib hold: [1]=master 仲裁等待, [0]=slave 外部存储事务等待
    wire rib_hold_flag_m;
    wire rib_hold_flag_s;
    wire [1:0] rib_hold_flag_o = {rib_hold_flag_m, rib_hold_flag_s};

    // external-memory handshake: arbitrated reqs from rib, done from bridge
    wire s0_req_o;
    wire s1_req_o;
    wire s0_done_o;
    wire s1_done_o;

    // tinyriscv处理器核模块例化
    cpu2_tinyriscv u_tinyriscv(
        .clk(clk),
        .rst(rst),
        .reg_we_o(reg_we_o),
        .reg_waddr_o(reg_waddr_o),
        .reg_wdata_o(reg_wdata_o),
        .reg_raddr1_o(reg_raddr1_o),
        .reg_raddr2_o(reg_raddr2_o),
        .reg_rdata1_i(reg_rdata1_i),
        .reg_rdata2_i(reg_rdata2_i),
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
        .s0_req_i(s0_req_o),
        .s0_we_i(s0_we_o),
        .s0_addr_i(s0_addr_o),
        .s0_data_i(s0_data_o),
        .s0_data_o(s0_data_i),
        .s0_done_o(s0_done_o),

        .s1_req_i(s1_req_o),
        .s1_we_i(s1_we_o),
        .s1_addr_i(s1_addr_o),
        .s1_data_i(s1_data_o),
        .s1_data_o(s1_data_i),
        .s1_done_o(s1_done_o),

        .ext_data_i(bridge_i),
        .ext_data_o(bridge_o)
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
        .m3_ack_o(m3_ack_o),

        // slave 0 interface
        .s0_addr_o(s0_addr_o),
        .s0_data_o(s0_data_o),
        .s0_data_i(s0_data_i),
        .s0_we_o(s0_we_o),
        .s0_req_o(s0_req_o),
        .s0_done_i(s0_done_o),

        // slave 1 interface
        .s1_addr_o(s1_addr_o),
        .s1_data_o(s1_data_o),
        .s1_data_i(s1_data_i),
        .s1_we_o(s1_we_o),
        .s1_req_o(s1_req_o),
        .s1_done_i(s1_done_o),

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

        // external-memory handshake
        .hold_flag_m(rib_hold_flag_m),
        .hold_flag_s(rib_hold_flag_s)
    );

    // debug bus: shared uart_debug -> RIB master 3
    assign m3_req_i  = dbg_req_i;
    assign m3_we_i   = dbg_we_i;
    assign m3_addr_i = dbg_addr_i;
    assign m3_data_i = dbg_wdata_i;
    assign dbg_rdata_o = m3_data_o;
    // RIB forwards the slave completion to master 3: the bridge ack for
    // external ROM/RAM writes, immediate ack for one-cycle peripherals.
    assign dbg_ack_o = m3_ack_o;

    // PWM bus: RIB slave 6 -> shared PWM
    assign pwm_we_o   = s6_we_o;
    assign pwm_addr_o = s6_addr_o;
    assign pwm_data_o = s6_data_o;

endmodule
