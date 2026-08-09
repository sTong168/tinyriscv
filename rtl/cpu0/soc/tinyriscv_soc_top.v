`include "../core/defines.v"

// tinyriscv soc顶层模块
module cpu0_tinyriscv_soc_top(

    input wire clk,
    input wire rst,

    output wire uart_tx_pin, // UART发送引脚
    input wire uart_rx_pin,  // UART接收引脚

    inout wire [`BridgeBus] bridge, // Bridge 通信总线

    inout wire scl,          // I2C SCL
    inout wire sda,          // I2C SDA

    // shared regs interface (pass-through)
    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input wire[`RegBus]     reg_rdata1_i,
    input wire[`RegBus]     reg_rdata2_i,

    // shared uart_debug bus
    input wire              dbg_req_i,
    input wire              dbg_we_i,
    input wire[`MemAddrBus] dbg_addr_i,
    input wire[`MemBus]     dbg_wdata_i,
    output wire[`MemBus]     dbg_rdata_o,
    output wire              dbg_ack_o,

    // shared PWM bus
    output wire              pwm_we_o,
    output wire[`MemAddrBus] pwm_addr_o,
    output wire[`MemBus]     pwm_data_o

    );


    // master 0 interface
    wire[`MemAddrBus] m0_addr_i;
    wire[`MemBus] m0_data_i;
    wire[`MemBus] m0_data_o;
    wire m0_req_i;
    wire m0_we_i;

    // master 1 interface
    wire[`MemAddrBus] m1_addr_i;
    wire[`MemBus] m1_data_i;
    wire[`MemBus] m1_data_o;
    wire m1_req_i;
    wire m1_we_i;

    // master 3 interface
    wire[`MemAddrBus] m3_addr_i;
    wire[`MemBus] m3_data_i;
    wire[`MemBus] m3_data_o;
    wire m3_req_i;
    wire m3_we_i;
    wire m3_ack_o;

    // slave 0 interface
    wire[`MemAddrBus] s0_addr_o;
    wire[`MemBus] s0_data_o;
    wire[`MemBus] s0_data_i;
    wire s0_we_o;
    wire s0_req_o;
    wire s0_ack_i;

    // slave 1 interface
    wire[`MemAddrBus] s1_addr_o;
    wire[`MemBus] s1_data_o;
    wire[`MemBus] s1_data_i;
    wire s1_we_o;
    wire s1_req_o;
    wire s1_ack_i;

    // slave 2 interface
    wire[`MemAddrBus] s2_addr_o;
    wire[`MemBus] s2_data_o;
    wire[`MemBus] s2_data_i;
    wire s2_we_o;
    wire s2_req_o;
    wire s2_ack_i;

    // slave 3 interface
    wire[`MemAddrBus] s3_addr_o;
    wire[`MemBus] s3_data_o;
    wire[`MemBus] s3_data_i;
    wire s3_we_o;
    wire s3_req_o;
    wire s3_ack_i;

    // slave 6 interface
    wire[`MemAddrBus] s6_addr_o;
    wire[`MemBus] s6_data_o;
    wire[`MemBus] s6_data_i;
    wire s6_we_o;
    wire s6_req_o;
    wire s6_ack_i;

    // rib
    wire [1:0] rib_hold_flag_o;

    // tinyriscv
    tinyriscv u_tinyriscv(
        .clk(clk),
        .rst(rst),
        .rib_ex_addr_o(m0_addr_i),
        .rib_ex_data_i(m0_data_o),
        .rib_ex_data_o(m0_data_i),
        .rib_ex_req_o(m0_req_i),
        .rib_ex_we_o(m0_we_i),

        .rib_pc_addr_o(m1_addr_i),
        .rib_pc_data_i(m1_data_o),

        .rib_hold_flag_i(rib_hold_flag_o),

        .reg_we_o(reg_we_o),
        .reg_waddr_o(reg_waddr_o),
        .reg_wdata_o(reg_wdata_o),
        .reg_raddr1_o(reg_raddr1_o),
        .reg_raddr2_o(reg_raddr2_o),
        .reg_rdata1_i(reg_rdata1_i),
        .reg_rdata2_i(reg_rdata2_i)
    );

    // bridge模块例化
    bridge u_bridge (
    .clk(clk),
    .rst(rst),
    .addr_i(s0_addr_o),
    .data_i(s0_data_o),
    .data_o(s0_data_i),
    .we_i(s0_we_o),
    .req_i(s0_req_o),
    .ack_o(s0_ack_i),
    .bridge_io(bridge)
  );

    // i2c模块例化
    i2c i2c_0(
        .clk(clk),
        .rst(rst),
        .data_i(s2_data_o),
        .addr_i(s2_addr_o),
        .we_i(s2_we_o),
        .data_o(s2_data_i),
        .req_i(s2_req_o),
        .scl(scl),
        .sda(sda)
    );

    // uart模块例化
    uart uart_0(
        .clk(clk),
        .rst(rst),
        .we_i(s3_we_o),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .tx_pin(uart_tx_pin),
        .rx_pin(uart_rx_pin)
    );

    // rib模块例化
    rib u_rib(
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
        .s0_ack_i(s0_ack_i),

        // slave 1 interface
        .s1_addr_o(s1_addr_o),
        .s1_data_o(s1_data_o),
        .s1_data_i(s1_data_i),
        .s1_we_o(s1_we_o),
        .s1_req_o(s1_req_o),
        .s1_ack_i(s1_ack_i),

        // slave 2 interface
        .s2_addr_o(s2_addr_o),
        .s2_data_o(s2_data_o),
        .s2_data_i(s2_data_i),
        .s2_we_o(s2_we_o),
        .s2_req_o(s2_req_o),
        .s2_ack_i(`RIB_ACK),

        // slave 3 interface
        .s3_addr_o(s3_addr_o),
        .s3_data_o(s3_data_o),
        .s3_data_i(s3_data_i),
        .s3_we_o(s3_we_o),
        .s3_req_o(s3_req_o),
        .s3_ack_i(`RIB_ACK),

        // slave 6 interface
        .s6_addr_o(s6_addr_o),
        .s6_data_o(s6_data_o),
        .s6_data_i(s6_data_i),
        .s6_we_o(s6_we_o),
        .s6_req_o(s6_req_o),
        .s6_ack_i(`RIB_ACK),

        .hold_flag_o(rib_hold_flag_o)
    );

    // shared uart_debug bus pass-through
    assign m3_req_i = dbg_req_i;
    assign m3_we_i = dbg_we_i;
    assign m3_addr_i = dbg_addr_i;
    assign m3_data_i = dbg_wdata_i;
    assign dbg_rdata_o = m3_data_o;
    assign dbg_ack_o = m3_ack_o;

    // shared PWM bus pass-through
    assign pwm_we_o = s6_we_o;
    assign pwm_addr_o = s6_addr_o;
    assign pwm_data_o = s6_data_o;

endmodule
