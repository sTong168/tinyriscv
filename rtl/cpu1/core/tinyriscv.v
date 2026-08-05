`include "defines.v"

// tinyriscv processor core (backend / RV32I + custom, no M/CSR/CLINT/JTAG)
module cpu1_tinyriscv(
    input wire clk,
    input wire rst,

    output wire[`MemAddrBus] rib_ex_addr_o,
    input  wire[`MemBus]     rib_ex_data_i,
    output wire[`MemBus]     rib_ex_data_o,
    output wire              rib_ex_req_o,
    output wire              rib_ex_we_o,

    output wire[`MemAddrBus] rib_pc_addr_o,
    input  wire[`MemBus]     rib_pc_data_i,

    input wire rib_hold_flag_i,

    output wire over,
    output wire succ,

    output wire              custom_start_o,
    output wire [2:0]        custom_funct3_o,
    output wire [31:0]       custom_rs1_o,
    output wire [31:0]       custom_rs2_o,
    output wire [11:0]       custom_imm_o,
    output wire [`RegAddrBus] custom_rd_waddr_o,
    input  wire              custom_busy_i,
    input  wire              custom_done_i,
    input  wire [31:0]       custom_result_i,
    input  wire [`RegAddrBus] custom_rd_waddr_i
);

    wire[`InstAddrBus] pc_pc_o;

    wire[`InstBus] if_inst_o;
    wire[`InstAddrBus] if_inst_addr_o;

    wire[`RegAddrBus] id_reg1_raddr_o, id_reg2_raddr_o;
    wire[`InstBus] id_inst_o;
    wire[`InstAddrBus] id_inst_addr_o;
    wire[`RegBus] id_reg1_rdata_o, id_reg2_rdata_o;
    wire id_reg_we_o;
    wire[`RegAddrBus] id_reg_waddr_o;
    wire[`MemAddrBus] id_op1_o, id_op2_o, id_op1_jump_o, id_op2_jump_o;

    wire[`InstBus] ie_inst_o;
    wire[`InstAddrBus] ie_inst_addr_o;
    wire ie_reg_we_o;
    wire[`RegAddrBus] ie_reg_waddr_o;
    wire[`RegBus] ie_reg1_rdata_o, ie_reg2_rdata_o;
    wire[`MemAddrBus] ie_op1_o, ie_op2_o, ie_op1_jump_o, ie_op2_jump_o;

    wire[`MemBus] ex_mem_wdata_o;
    wire[`MemAddrBus] ex_mem_raddr_o, ex_mem_waddr_o;
    wire ex_mem_we_o, ex_mem_req_o;
    wire[`RegBus] ex_reg_wdata_o;
    wire ex_reg_we_o;
    wire[`RegAddrBus] ex_reg_waddr_o;
    wire ex_hold_flag_o, ex_jump_flag_o;
    wire[`InstAddrBus] ex_jump_addr_o;
    wire[`RegAddrBus] ex_custom_rd_waddr_o;

    wire[`RegBus] regs_rdata1_o, regs_rdata2_o;

    wire[`Hold_Flag_Bus] ctrl_hold_flag_o;
    wire ctrl_jump_flag_o;
    wire[`InstAddrBus] ctrl_jump_addr_o;

    assign rib_ex_addr_o = (ex_mem_we_o == `WriteEnable) ? ex_mem_waddr_o : ex_mem_raddr_o;
    assign rib_ex_data_o = ex_mem_wdata_o;
    assign rib_ex_req_o  = ex_mem_req_o;
    assign rib_ex_we_o   = ex_mem_we_o;
    assign rib_pc_addr_o = pc_pc_o;

    cpu1_pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .pc_o(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .jump_flag_i(ctrl_jump_flag_o),
        .jump_addr_i(ctrl_jump_addr_o)
    );

    cpu1_ctrl u_ctrl(
        .rst(rst),
        .jump_flag_i(ex_jump_flag_o),
        .jump_addr_i(ex_jump_addr_o),
        .hold_flag_ex_i(ex_hold_flag_o),
        .hold_flag_rib_i(rib_hold_flag_i),
        .hold_flag_o(ctrl_hold_flag_o),
        .jump_flag_o(ctrl_jump_flag_o),
        .jump_addr_o(ctrl_jump_addr_o)
    );

    cpu1_regs u_regs(
        .clk(clk),
        .rst(rst),
        .we_i(ex_reg_we_o),
        .waddr_i(ex_reg_waddr_o),
        .wdata_i(ex_reg_wdata_o),
        .raddr1_i(id_reg1_raddr_o),
        .rdata1_o(regs_rdata1_o),
        .raddr2_i(id_reg2_raddr_o),
        .rdata2_o(regs_rdata2_o),
        .over(over),
        .succ(succ)
    );

    cpu1_if_id u_if_id(
        .clk(clk),
        .rst(rst),
        .inst_i(rib_pc_data_i),
        .inst_addr_i(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_o(if_inst_o),
        .inst_addr_o(if_inst_addr_o)
    );

    cpu1_id u_id(
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

    cpu1_id_ex u_id_ex(
        .clk(clk),
        .rst(rst),
        .inst_i(id_inst_o),
        .inst_addr_i(id_inst_addr_o),
        .reg_we_i(id_reg_we_o),
        .reg_waddr_i(id_reg_waddr_o),
        .reg1_rdata_i(id_reg1_rdata_o),
        .reg2_rdata_i(id_reg2_rdata_o),
        .op1_i(id_op1_o),
        .op2_i(id_op2_o),
        .op1_jump_i(id_op1_jump_o),
        .op2_jump_i(id_op2_jump_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_o(ie_inst_o),
        .inst_addr_o(ie_inst_addr_o),
        .reg_we_o(ie_reg_we_o),
        .reg_waddr_o(ie_reg_waddr_o),
        .reg1_rdata_o(ie_reg1_rdata_o),
        .reg2_rdata_o(ie_reg2_rdata_o),
        .op1_o(ie_op1_o),
        .op2_o(ie_op2_o),
        .op1_jump_o(ie_op1_jump_o),
        .op2_jump_o(ie_op2_jump_o)
    );

    cpu1_ex u_ex(
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
        .jump_flag_o(ex_jump_flag_o),
        .jump_addr_o(ex_jump_addr_o),
        .custom_start_o(custom_start_o),
        .custom_funct3_o(custom_funct3_o),
        .custom_rs1_o(custom_rs1_o),
        .custom_rs2_o(custom_rs2_o),
        .custom_imm_o(custom_imm_o),
        .custom_rd_waddr_o(ex_custom_rd_waddr_o),
        .custom_busy_i(custom_busy_i),
        .custom_done_i(custom_done_i),
        .custom_result_i(custom_result_i),
        .custom_rd_waddr_i(custom_rd_waddr_i)
    );

endmodule
