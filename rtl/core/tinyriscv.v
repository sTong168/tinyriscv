`include "defines.v"

// tinyriscv处理器核顶层模块
module tinyriscv(

    input wire clk,
    input wire rst,

    output wire[`MemAddrBus] rib_ex_addr_o,    // 读、写外设的地址
    input wire[`MemBus] rib_ex_data_i,         // 从外设读取的数据
    output wire[`MemBus] rib_ex_data_o,        // 写入外设的数据
    output wire rib_ex_req_o,                  // 访问外设请求
    output wire rib_ex_we_o,                   // 写外设标志

    output wire[`MemAddrBus] rib_pc_addr_o,    // 取指地址
    input wire[`MemBus] rib_pc_data_i,         // 取到的指令内容

    input wire [1:0] rib_hold_flag_i           // 总线暂停标志

    );

    // pc_reg模块输出信号
	wire[`InstAddrBus] pc_pc_o;

    // if_id模块输出信号
	wire[`InstBus] if_inst_o;
    wire[`InstAddrBus] if_inst_addr_o;

    // id模块输出信号
	wire[`RegAddrBus] id_reg1_raddr_o;
	wire[`RegAddrBus] id_reg2_raddr_o;
	wire[`InstBus] id_inst_o;
	wire[`InstAddrBus] id_inst_addr_o;
	wire[`RegBus] id_reg1_rdata_o;
	wire[`RegBus] id_reg2_rdata_o;
	wire id_reg_we_o;
	wire[`RegAddrBus] id_reg_waddr_o;
	wire[`MemAddrBus] id_op1_o;
	wire[`MemAddrBus] id_op2_o;
	wire[`MemAddrBus] id_op1_jump_o;
	wire[`MemAddrBus] id_op2_jump_o;

    // id_ex模块输出信号
    wire[`InstBus] ie_inst_o;
    wire[`InstAddrBus] ie_inst_addr_o;
    wire ie_reg_we_o;
    wire[`RegAddrBus] ie_reg_waddr_o;
    wire[`RegBus] ie_reg1_rdata_o;
    wire[`RegBus] ie_reg2_rdata_o;
    wire[`MemAddrBus] ie_op1_o;
    wire[`MemAddrBus] ie_op2_o;
    wire[`MemAddrBus] ie_op1_jump_o;
    wire[`MemAddrBus] ie_op2_jump_o;

    // ex模块输出信号
    wire[`MemBus] ex_mem_wdata_o;
    wire[`MemAddrBus] ex_mem_raddr_o;
    wire[`MemAddrBus] ex_mem_waddr_o;
    wire ex_mem_we_o;
    wire ex_mem_req_o;
    wire[`RegBus] ex_reg_wdata_o;
    wire ex_reg_we_o;
    wire[`RegAddrBus] ex_reg_waddr_o;
    wire ex_hold_flag_o;
    wire ex_ls_flag_o;
    wire ex_jump_flag_o;
    wire[`InstAddrBus] ex_jump_addr_o;

    // regs模块输出信号
    wire[`RegBus] regs_rdata1_o;
    wire[`RegBus] regs_rdata2_o;

    // ctrl模块输出信号
    wire[`Hold_Flag_Bus] ctrl_hold_flag_o;
    wire ctrl_jump_flag_o;
    wire[`InstAddrBus] ctrl_jump_addr_o;

    // uart_send模块信号
    wire uart_start;
    wire uart_busy;
    wire[`MemAddrBus] uart_addr;
    wire[`MemBus] uart_wdata;
    wire uart_we;
    wire uart_req;

    // i2c_send模块信号
    wire i2c_start;
    wire i2c_busy;
    wire[`MemAddrBus] i2c_addr;
    wire[`MemBus] i2c_wdata;
    wire i2c_we;
    wire i2c_req;
    wire i2c_reg_we;
    wire[`RegAddrBus] i2c_reg_waddr;
    wire[`RegBus] i2c_reg_wdata;

    // inst_if_ctrl模块信号
    wire if_start;
    wire if_busy;
    wire[`MemAddrBus] if_addr;
    wire[`MemBus] if_wdata;
    wire if_we;
    wire if_req;
    wire if_reg_we;
    wire[`RegAddrBus] if_reg_waddr;
    wire[`RegBus] if_reg_wdata;
    wire[7:0] if_send_byte;
    wire[`RegAddrBus] if_rd_addr;


    assign rib_ex_addr_o = (ex_mem_we_o == `WriteEnable)? ex_mem_waddr_o: ex_mem_raddr_o;
    assign rib_ex_data_o = ex_mem_wdata_o;
    assign rib_ex_req_o = ex_mem_req_o;
    assign rib_ex_we_o = ex_mem_we_o;

    assign rib_pc_addr_o = pc_pc_o;


    // pc_reg模块例化
    pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .pc_o(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .jump_flag_i(ctrl_jump_flag_o),
        .jump_addr_i(ctrl_jump_addr_o)
    );

    // ctrl模块例化
    ctrl u_ctrl(
        .clk(clk),
        .rst(rst),
        .jump_flag_i(ex_jump_flag_o),
        .jump_addr_i(ex_jump_addr_o),
        .ls_flag_i(ex_ls_flag_o),
        .hold_flag_ex_i(ex_hold_flag_o),
        .hold_flag_rib_i(rib_hold_flag_i),
        .hold_flag_o(ctrl_hold_flag_o),
        .jump_flag_o(ctrl_jump_flag_o),
        .jump_addr_o(ctrl_jump_addr_o)
    );

    // regs模块例化
    regs u_regs(
        .clk(clk),
        .rst(rst),
        .we_i(ex_reg_we_o),
        .waddr_i(ex_reg_waddr_o),
        .wdata_i(ex_reg_wdata_o),
        .raddr1_i(id_reg1_raddr_o),
        .rdata1_o(regs_rdata1_o),
        .raddr2_i(id_reg2_raddr_o),
        .rdata2_o(regs_rdata2_o)
    );

    // if_id模块例化
    if_id u_if_id(
        .clk(clk),
        .rst(rst),
        .inst_i(rib_pc_data_i),
        .inst_addr_i(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_o(if_inst_o),
        .inst_addr_o(if_inst_addr_o)
    );

    // id模块例化
    id u_id(
        .rst(rst),
        .inst_i(if_inst_o),
        .inst_addr_i(if_inst_addr_o),
        .reg1_rdata_i(regs_rdata1_o),
        .reg2_rdata_i(regs_rdata2_o),
        .ex_jump_flag_i(ex_jump_flag_o),
        .reg1_raddr_o(id_reg1_raddr_o),
        .reg2_raddr_o(id_reg2_raddr_o),
        .inst_o(id_inst_o),
        .inst_addr_o(id_inst_addr_o),
        .reg1_rdata_o(id_reg1_rdata_o),
        .reg2_rdata_o(id_reg2_rdata_o),
        .reg_we_o(id_reg_we_o),
        .reg_waddr_o(id_reg_waddr_o),
        .op1_o(id_op1_o),
        .op2_o(id_op2_o),
        .op1_jump_o(id_op1_jump_o),
        .op2_jump_o(id_op2_jump_o)
    );

    // id_ex模块例化
    id_ex u_id_ex(
        .clk(clk),
        .rst(rst),
        .inst_i(id_inst_o),
        .inst_addr_i(id_inst_addr_o),
        .reg_we_i(id_reg_we_o),
        .reg_waddr_i(id_reg_waddr_o),
        .reg1_rdata_i(id_reg1_rdata_o),
        .reg2_rdata_i(id_reg2_rdata_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_o(ie_inst_o),
        .inst_addr_o(ie_inst_addr_o),
        .reg_we_o(ie_reg_we_o),
        .reg_waddr_o(ie_reg_waddr_o),
        .reg1_rdata_o(ie_reg1_rdata_o),
        .reg2_rdata_o(ie_reg2_rdata_o),
        .op1_i(id_op1_o),
        .op2_i(id_op2_o),
        .op1_jump_i(id_op1_jump_o),
        .op2_jump_i(id_op2_jump_o),
        .op1_o(ie_op1_o),
        .op2_o(ie_op2_o),
        .op1_jump_o(ie_op1_jump_o),
        .op2_jump_o(ie_op2_jump_o)
    );

    // ex模块例化
    ex u_ex(
        .clk(clk),
        .rst(rst),
        .inst_i(ie_inst_o),
        .inst_addr_i(ie_inst_addr_o),
        .reg_we_i(ie_reg_we_o),
        .reg_waddr_i(ie_reg_waddr_o),
        .reg1_rdata_i(ie_reg1_rdata_o),
        .reg2_rdata_i(ie_reg2_rdata_o),
        .op1_i(ie_op1_o),
        .op2_i(ie_op2_o),
        .op1_jump_i(ie_op1_jump_o),
        .op2_jump_i(ie_op2_jump_o),
        .mem_rdata_i(rib_ex_data_i),
        .mem_wdata_o(ex_mem_wdata_o),
        .mem_raddr_o(ex_mem_raddr_o),
        .mem_waddr_o(ex_mem_waddr_o),
        .mem_we_o(ex_mem_we_o),
        .mem_req_o(ex_mem_req_o),
        .reg_wdata_o(ex_reg_wdata_o),
        .reg_we_o(ex_reg_we_o),
        .reg_waddr_o(ex_reg_waddr_o),
        .hold_flag_o(ex_hold_flag_o),
        .ls_flag_o(ex_ls_flag_o),
        .jump_flag_o(ex_jump_flag_o),
        .jump_addr_o(ex_jump_addr_o),
        .uart_busy_i(uart_busy),
        .uart_wdata_i(uart_wdata),
        .uart_addr_i(uart_addr),
        .uart_we_i(uart_we),
        .uart_req_i(uart_req),
        .uart_start_o(uart_start),
        .i2c_busy_i(i2c_busy),
        .i2c_wdata_i(i2c_wdata),
        .i2c_addr_i(i2c_addr),
        .i2c_we_i(i2c_we),
        .i2c_req_i(i2c_req),
        .i2c_reg_we_i(i2c_reg_we),
        .i2c_reg_waddr_i(i2c_reg_waddr),
        .i2c_reg_wdata_i(i2c_reg_wdata),
        .i2c_start_o(i2c_start),
        .if_busy_i(if_busy),
        .if_wdata_i(if_wdata),
        .if_addr_i(if_addr),
        .if_we_i(if_we),
        .if_req_i(if_req),
        .if_reg_we_i(if_reg_we),
        .if_reg_waddr_i(if_reg_waddr),
        .if_reg_wdata_i(if_reg_wdata),
        .if_start_o(if_start),
        .if_send_byte_o(if_send_byte),
        .if_rd_addr_o(if_rd_addr)
    );

    // inst_sid_ctrl模块例化
    inst_sid_ctrl u_inst_sid_ctrl(
        .clk(clk),
        .rst(rst),
        .start_i(uart_start),
        .mem_rdata_i(rib_ex_data_i),
        .busy_o(uart_busy),
        .addr_o(uart_addr),
        .wdata_o(uart_wdata),
        .we_o(uart_we),
        .req_o(uart_req)
    );

    // i2c_send模块例化
    inst_rt_ctrl u_inst_rt_ctrl(
        .clk(clk),
        .rst(rst),
        .start_i(i2c_start),
        .mem_rdata_i(rib_ex_data_i),
        .reg_waddr_i(ie_reg_waddr_o),
        .busy_o(i2c_busy),
        .addr_o(i2c_addr),
        .wdata_o(i2c_wdata),
        .we_o(i2c_we),
        .req_o(i2c_req),
        .reg_we_o(i2c_reg_we),
        .reg_waddr_o(i2c_reg_waddr),
        .reg_wdata_o(i2c_reg_wdata)
    );

    // inst_if_ctrl模块例化
    inst_if_ctrl u_inst_if_ctrl(
        .clk(clk),
        .rst(rst),
        .start_i(if_start),
        .send_byte_i(if_send_byte),
        .rd_addr_i(if_rd_addr),
        .mem_rdata_i(rib_ex_data_i),
        .busy_o(if_busy),
        .addr_o(if_addr),
        .wdata_o(if_wdata),
        .we_o(if_we),
        .req_o(if_req),
        .reg_we_o(if_reg_we),
        .reg_waddr_o(if_reg_waddr),
        .reg_wdata_o(if_reg_wdata)
    );

endmodule