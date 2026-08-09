`include "../core/defines.v"

// SoC top — backend / tape-out port list (group unified interface)
module cpu1_tinyriscv_soc_top #(
    parameter MEM_BYPASS = 0
)(
    input  wire       clk,
    input  wire       rst,

    output wire       uart_tx_pin,
    input  wire       uart_rx_pin,

    output wire [7:0] bridge_o,
    input  wire [7:0] bridge_i,

    input  wire       scl_in,
    output wire       scl_o,
    output wire       scl_oe,
    input  wire       sda_in,
    output wire       sda_o,
    output wire       sda_oe,

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

    wire [`MemAddrBus] m0_addr_i, m1_addr_i, m2_addr_i, m3_addr_i;
    wire [`MemBus]     m0_data_i, m1_data_i, m2_data_i, m3_data_i;
    wire [`MemBus]     m0_data_o, m1_data_o, m2_data_o, m3_data_o;
    wire               m0_req_i, m1_req_i, m2_req_i, m3_req_i;
    wire               m0_we_i, m1_we_i, m2_we_i, m3_we_i;

    wire [`MemAddrBus] s0_addr_o, s1_addr_o, s2_addr_o, s3_addr_o;
    wire [`MemAddrBus] s6_addr_o, s7_addr_o;
    wire [`MemBus]     s0_data_o, s1_data_o, s2_data_o, s3_data_o;
    wire [`MemBus]     s6_data_o, s7_data_o;
    wire [`MemBus]     s0_data_i, s1_data_i, s2_data_i, s3_data_i;
    wire [`MemBus]     s6_data_i, s7_data_i;
    wire               s0_we_o, s1_we_o, s2_we_o, s3_we_o;
    wire               s6_we_o, s7_we_o;

    wire [`MemAddrBus] ext_rom_addr, ext_ram_addr;
    wire               ext_rom_we, ext_ram_we;
    wire [`MemBus]     ext_rom_wdata, ext_ram_wdata;
    wire [`MemBus]     ext_rom_rdata, ext_ram_rdata;

    wire rib_hold_rib, rib_hold_cpu;
    wire mem_hold_flag, rom_wr_ack;
    wire custom_start;
    wire [2:0]  custom_funct3;
    wire [31:0] custom_rs1, custom_rs2;
    wire [11:0] custom_imm;
    wire [`RegAddrBus] custom_rd_waddr, custom_rd_waddr_stored;
    wire custom_busy, custom_done;
    wire [31:0] custom_result;
    wire uart_main_tx, custom_uart_tx, custom_uart_busy;

    wire bus_scl_o, bus_sda_o, bus_sda_oe;
    wire cust_scl_o, cust_sda_o, cust_sda_oe;
    wire mmio_scl_o, mmio_sda_o, mmio_sda_oe;

    assign uart_tx_pin = custom_uart_busy ? custom_uart_tx : uart_main_tx;

    // Open-drain merge: drive low or release (oe=0)
    wire scl_drive_low = (cust_scl_o == 1'b0) | (mmio_scl_o == 1'b0);
    wire sda_drive_low = (cust_sda_oe & ~cust_sda_o) | (mmio_sda_oe & ~mmio_sda_o);

    assign scl_o  = scl_drive_low ? 1'b0 : 1'b1;
    assign scl_oe = scl_drive_low;
    assign sda_o  = sda_drive_low ? 1'b0 : 1'b1;
    assign sda_oe = sda_drive_low;

  // unused pad readbacks (hook up in chip top)
  wire _unused_scl_in = scl_in;
  wire _unused_sda_in = sda_in;

    cpu1_ext_mem_port #(
        .MEM_BYPASS(MEM_BYPASS)
    ) u_ext_mem(
        .clk(clk),
        .rst(rst),
        .s0_addr_i(s0_addr_o),
        .s0_we_i(s0_we_o),
        .s0_wdata_i(s0_data_o),
        .s0_rdata_o(s0_data_i),
        .s1_addr_i(s1_addr_o),
        .s1_we_i(s1_we_o),
        .s1_wdata_i(s1_data_o),
        .s1_rdata_o(s1_data_i),
        .m0_req_i(m0_req_i),
        .m0_we_i(m0_we_i),
        .m0_addr_i(m0_addr_i),
        .ifetch_req_i(`RIB_REQ),
        .ifetch_addr_i(m1_addr_i),
        .ext_rom_addr_o(ext_rom_addr),
        .ext_rom_we_o(ext_rom_we),
        .ext_rom_wdata_o(ext_rom_wdata),
        .ext_rom_rdata_i(ext_rom_rdata),
        .ext_ram_addr_o(ext_ram_addr),
        .ext_ram_we_o(ext_ram_we),
        .ext_ram_wdata_o(ext_ram_wdata),
        .ext_ram_rdata_i(ext_ram_rdata),
        .bridge_o(bridge_o),
        .bridge_i(bridge_i),
        .rom_wr_ack_o(rom_wr_ack),
        .mem_hold_o(mem_hold_flag)
    );

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
        .rib_hold_flag_i(rib_hold_cpu),
        .reg_we_o(reg_we_o),
        .reg_waddr_o(reg_waddr_o),
        .reg_wdata_o(reg_wdata_o),
        .reg_raddr1_o(reg_raddr1_o),
        .reg_raddr2_o(reg_raddr2_o),
        .reg_rdata1_i(reg_rdata1_i),
        .reg_rdata2_i(reg_rdata2_i),
        .custom_start_o(custom_start),
        .custom_funct3_o(custom_funct3),
        .custom_rs1_o(custom_rs1),
        .custom_rs2_o(custom_rs2),
        .custom_imm_o(custom_imm),
        .custom_rd_waddr_o(custom_rd_waddr),
        .custom_busy_i(custom_busy),
        .custom_done_i(custom_done),
        .custom_result_i(custom_result),
        .custom_rd_waddr_i(custom_rd_waddr_stored)
    );

    cpu1_uart u_uart(
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
        .scl_o(mmio_scl_o),
        .sda_o(mmio_sda_o),
        .sda_oe_o(mmio_sda_oe),
        .sda_i(sda_in)
    );

    cpu1_lfsr u_lfsr(
        .clk(clk),
        .rst(rst),
        .addr_i(s2_addr_o),
        .data_i(s2_data_o),
        .we_i(s2_we_o),
        .data_o(s2_data_i)
    );

    cpu1_custom_inst u_custom(
        .clk(clk),
        .rst(rst),
        .start_i(custom_start),
        .funct3_i(custom_funct3),
        .rs1_i(custom_rs1),
        .rs2_i(custom_rs2),
        .imm_i(custom_imm),
        .rd_addr_i(custom_rd_waddr),
        .rd_addr_o(custom_rd_waddr_stored),
        .busy_o(custom_busy),
        .done_o(custom_done),
        .result_o(custom_result),
        .uart_tx_o(custom_uart_tx),
        .uart_busy_o(custom_uart_busy),
        .i2c_scl_o(cust_scl_o),
        .i2c_sda_o(cust_sda_o),
        .i2c_sda_oe_o(cust_sda_oe),
        .i2c_sda_i(sda_in)
    );

    cpu1_rib u_rib(
        .clk(clk),
        .rst(rst),
        .m0_addr_i(m0_addr_i), .m0_data_i(m0_data_i), .m0_data_o(m0_data_o), .m0_req_i(m0_req_i), .m0_we_i(m0_we_i),
        .m1_addr_i(m1_addr_i), .m1_data_i(`ZeroWord),  .m1_data_o(m1_data_o), .m1_req_i(`RIB_REQ),  .m1_we_i(`WriteDisable),
        .m2_addr_i(m2_addr_i), .m2_data_i(m2_data_i), .m2_data_o(m2_data_o), .m2_req_i(m2_req_i), .m2_we_i(m2_we_i),
        .m3_addr_i(m3_addr_i), .m3_data_i(m3_data_i), .m3_data_o(m3_data_o), .m3_req_i(m3_req_i), .m3_we_i(m3_we_i),
        .s0_addr_o(s0_addr_o), .s0_data_o(s0_data_o), .s0_data_i(s0_data_i), .s0_we_o(s0_we_o),
        .s1_addr_o(s1_addr_o), .s1_data_o(s1_data_o), .s1_data_i(s1_data_i), .s1_we_o(s1_we_o),
        .s2_addr_o(s2_addr_o), .s2_data_o(s2_data_o), .s2_data_i(s2_data_i), .s2_we_o(s2_we_o),
        .s3_addr_o(s3_addr_o), .s3_data_o(s3_data_o), .s3_data_i(s3_data_i), .s3_we_o(s3_we_o),
        .s4_addr_o(), .s4_data_o(), .s4_data_i(`ZeroWord), .s4_we_o(),
        .s5_addr_o(), .s5_data_o(), .s5_data_i(`ZeroWord), .s5_we_o(),
        .s6_addr_o(s6_addr_o), .s6_data_o(s6_data_o), .s6_data_i(s6_data_i), .s6_we_o(s6_we_o),
        .s7_addr_o(s7_addr_o), .s7_data_o(s7_data_o), .s7_data_i(s7_data_i), .s7_we_o(s7_we_o),
        .hold_flag_o(rib_hold_rib)
    );

    assign rib_hold_cpu = rib_hold_rib | mem_hold_flag;

    // debug bus: shared uart_debug -> RIB master 3
    assign m3_req_i = dbg_req_i;
    assign m3_we_i = dbg_we_i;
    assign m3_addr_i = dbg_addr_i;
    assign m3_data_i = dbg_wdata_i;
    assign dbg_rdata_o = m3_data_o;
    assign dbg_ack_o = rom_wr_ack;  // cpu1 uses ext_mem ack

    // PWM bus: RIB slave 6 -> shared PWM
    assign pwm_we_o = s6_we_o;
    assign pwm_addr_o = s6_addr_o;
    assign pwm_data_o = s6_data_o;

endmodule
