`include "../core/defines.v"

// cpu1 SoC — 16-bit pad bridge + shared regs/pwm/uart_debug (4cpu packaging)
module cpu1_tinyriscv_soc_top(
    input  wire       clk,
    input  wire       rst,

    output wire       uart_tx_pin,
    input  wire       uart_rx_pin,

    input  wire [15:0] bridge_in,
    output wire [15:0] bridge_o,
    output wire        bridge_oe,

    input  wire       scl_in,
    output wire       scl_o,
    output wire       scl_oe,
    input  wire       sda_in,
    output wire       sda_o,
    output wire       sda_oe,

    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input  wire[`RegBus]     reg_rdata1_i,
    input  wire[`RegBus]     reg_rdata2_i,

    input  wire              dbg_req_i,
    input  wire              dbg_we_i,
    input  wire[`MemAddrBus] dbg_addr_i,
    input  wire[`MemBus]     dbg_wdata_i,
    output wire[`MemBus]     dbg_rdata_o,
    output wire              dbg_ack_o,

    output wire              pwm_we_o,
    output wire[`MemAddrBus] pwm_addr_o,
    output wire[`MemBus]     pwm_data_o
);

    wire [`MemAddrBus] m0_addr_i, m1_addr_i, m3_addr_i;
    wire [`MemBus]     m0_data_i, m3_data_i;
    wire [`MemBus]     m0_data_o, m1_data_o, m3_data_o;
    wire               m0_req_i, m3_req_i;
    wire               m0_we_i, m3_we_i;
    wire               m3_ack_o;

    wire [`MemAddrBus] s0_addr_o, s2_addr_o, s3_addr_o, s6_addr_o, s7_addr_o;
    wire [`MemBus]     s0_data_o, s2_data_o, s3_data_o, s6_data_o, s7_data_o;
    wire [`MemBus]     s0_data_i, s2_data_i, s3_data_i, s7_data_i;
    wire               s0_we_o, s2_we_o, s3_we_o, s6_we_o, s7_we_o;
    wire               s0_req_o, s2_req_o, s3_req_o, s6_req_o, s7_req_o;
    wire               s0_ack_i;

    wire [1:0] rib_hold_flag_o;

    wire        custom_start;
    wire [2:0]  custom_funct3;
    wire [31:0] custom_rs1, custom_rs2;
    wire [11:0] custom_imm;
    wire [4:0]  custom_rd_waddr, custom_rd_waddr_stored;
    wire        custom_busy, custom_done;
    wire [31:0] custom_result;
    wire        custom_uart_tx, custom_uart_busy;
    wire        custom_i2c_scl, custom_i2c_sda, custom_i2c_sda_oe;
    wire        bus_i2c_scl, bus_i2c_sda, bus_i2c_sda_oe;

    wire uart_main_tx;
    assign uart_tx_pin = custom_uart_busy ? custom_uart_tx : uart_main_tx;

    wire scl_line = custom_i2c_scl & bus_i2c_scl;
    wire sda_drive_low = (custom_i2c_sda_oe & ~custom_i2c_sda) | (bus_i2c_sda_oe & ~bus_i2c_sda);
    assign scl_o  = 1'b0;
    assign scl_oe = ~scl_line;
    assign sda_o  = 1'b0;
    assign sda_oe = sda_drive_low;
    wire _scl_in_unused = scl_in;

    cpu1_tinyriscv u_tinyriscv(
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
        .custom_start_o(custom_start),
        .custom_funct3_o(custom_funct3),
        .custom_rs1_o(custom_rs1),
        .custom_rs2_o(custom_rs2),
        .custom_imm_o(custom_imm),
        .custom_rd_waddr_o(custom_rd_waddr),
        .custom_busy_i(custom_busy),
        .custom_done_i(custom_done),
        .custom_result_i(custom_result),
        .custom_rd_waddr_i(custom_rd_waddr_stored),
        .reg_we_o(reg_we_o),
        .reg_waddr_o(reg_waddr_o),
        .reg_wdata_o(reg_wdata_o),
        .reg_raddr1_o(reg_raddr1_o),
        .reg_raddr2_o(reg_raddr2_o),
        .reg_rdata1_i(reg_rdata1_i),
        .reg_rdata2_i(reg_rdata2_i)
    );

    cpu1_bridge u_bridge(
        .clk(clk),
        .rst(rst),
        .addr_i(s0_addr_o),
        .data_i(s0_data_o),
        .data_o(s0_data_i),
        .we_i(s0_we_o),
        .req_i(s0_req_o),
        .ack_o(s0_ack_i),
        .bridge_o(bridge_o),
        .bridge_oe(bridge_oe),
        .bridge_in(bridge_in)
    );

    cpu1_lfsr u_lfsr(
        .clk(clk),
        .rst(rst),
        .addr_i(s2_addr_o),
        .data_i(s2_data_o),
        .we_i(s2_we_o),
        .data_o(s2_data_i)
    );

    cpu1_uart uart_0(
        .clk(clk),
        .rst(rst),
        .we_i(s3_we_o),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .tx_pin(uart_main_tx),
        .rx_pin(uart_rx_pin)
    );

    cpu1_i2c u_i2c(
        .clk(clk),
        .rst(rst),
        .we_i(s7_we_o),
        .addr_i(s7_addr_o),
        .data_i(s7_data_o),
        .data_o(s7_data_i),
        .scl_o(bus_i2c_scl),
        .sda_o(bus_i2c_sda),
        .sda_oe_o(bus_i2c_sda_oe),
        .sda_i(sda_in)
    );

    cpu1_custom_inst u_custom_inst(
        .clk(clk),
        .rst(rst),
        .start_i(custom_start),
        .funct3_i(custom_funct3),
        .rs1_i(custom_rs1),
        .rs2_i(custom_rs2),
        .imm_i(custom_imm),
        .rd_addr_i(custom_rd_waddr),
        .busy_o(custom_busy),
        .done_o(custom_done),
        .result_o(custom_result),
        .rd_addr_o(custom_rd_waddr_stored),
        .uart_tx_o(custom_uart_tx),
        .uart_busy_o(custom_uart_busy),
        .i2c_scl_o(custom_i2c_scl),
        .i2c_sda_o(custom_i2c_sda),
        .i2c_sda_oe_o(custom_i2c_sda_oe),
        .i2c_sda_i(sda_in)
    );

    cpu1_rib u_rib(
        .clk(clk),
        .rst(rst),
        .m0_addr_i(m0_addr_i), .m0_data_i(m0_data_i), .m0_data_o(m0_data_o),
        .m0_req_i(m0_req_i), .m0_we_i(m0_we_i),
        .m1_addr_i(m1_addr_i), .m1_data_i(`ZeroWord), .m1_data_o(m1_data_o),
        .m1_req_i(`RIB_REQ), .m1_we_i(`WriteDisable),
        .m3_addr_i(m3_addr_i), .m3_data_i(m3_data_i), .m3_data_o(m3_data_o),
        .m3_req_i(m3_req_i), .m3_we_i(m3_we_i), .m3_ack_o(m3_ack_o),
        .s0_addr_o(s0_addr_o), .s0_data_o(s0_data_o), .s0_data_i(s0_data_i),
        .s0_we_o(s0_we_o), .s0_req_o(s0_req_o), .s0_ack_i(s0_ack_i),
        .s2_addr_o(s2_addr_o), .s2_data_o(s2_data_o), .s2_data_i(s2_data_i),
        .s2_we_o(s2_we_o), .s2_req_o(s2_req_o), .s2_ack_i(`RIB_ACK),
        .s3_addr_o(s3_addr_o), .s3_data_o(s3_data_o), .s3_data_i(s3_data_i),
        .s3_we_o(s3_we_o), .s3_req_o(s3_req_o), .s3_ack_i(`RIB_ACK),
        .s6_addr_o(s6_addr_o), .s6_data_o(s6_data_o), .s6_data_i(`ZeroWord),
        .s6_we_o(s6_we_o), .s6_req_o(s6_req_o), .s6_ack_i(`RIB_ACK),
        .s7_addr_o(s7_addr_o), .s7_data_o(s7_data_o), .s7_data_i(s7_data_i),
        .s7_we_o(s7_we_o), .s7_req_o(s7_req_o), .s7_ack_i(`RIB_ACK),
        .hold_flag_o(rib_hold_flag_o)
    );

    assign m3_req_i   = dbg_req_i;
    assign m3_we_i    = dbg_we_i;
    assign m3_addr_i  = dbg_addr_i;
    assign m3_data_i  = dbg_wdata_i;
    assign dbg_rdata_o = m3_data_o;
    assign dbg_ack_o   = m3_ack_o;

    assign pwm_we_o   = s6_we_o;
    assign pwm_addr_o = s6_addr_o;
    assign pwm_data_o = s6_data_o;

endmodule
