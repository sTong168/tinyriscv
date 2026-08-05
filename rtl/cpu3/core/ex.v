`include "defines.v"

// RV32I execute and memory stage.
module cpu3_ex(
    input wire[`InstBus] inst_i,
    input wire reg_we_i,
    input wire[`RegAddrBus] reg_waddr_i,
    input wire[`RegBus] reg1_rdata_i,
    input wire[`RegBus] reg2_rdata_i,
    input wire[`MemAddrBus] op1_i,
    input wire[`MemAddrBus] op2_i,
    input wire[`MemAddrBus] op1_jump_i,
    input wire[`MemAddrBus] op2_jump_i,
    input wire[`MemBus] mem_rdata_i,

    output reg[`MemBus] mem_wdata_o,
    output reg[`MemAddrBus] mem_raddr_o,
    output reg[`MemAddrBus] mem_waddr_o,
    output wire mem_we_o,
    output wire mem_req_o,
    output wire[`RegBus] reg_wdata_o,
    output wire reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire hold_flag_o,
    output wire jump_flag_o,
    output wire[`InstAddrBus] jump_addr_o,
    output wire sid_start_o,
    input wire sid_done_i,
    output wire rt_start_o,
    input wire rt_done_i,
    input wire[7:0] i2c_temp_data_i,
    output reg send_if_start_o,
    input wire send_if_done_i,
    output wire[7:0] if_data_o
    );

    wire[1:0] mem_raddr_index =
        (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:20]}) & 2'b11;
    wire[1:0] mem_waddr_index =
        (reg1_rdata_i + {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]}) & 2'b11;
    wire[6:0] opcode = inst_i[6:0];
    wire[2:0] funct3 = inst_i[14:12];

    wire[31:0] sr_shift = reg1_rdata_i >> reg2_rdata_i[4:0];
    wire[31:0] sri_shift = reg1_rdata_i >> inst_i[24:20];
    wire[31:0] sr_shift_mask = 32'hffffffff >> reg2_rdata_i[4:0];
    wire[31:0] sri_shift_mask = 32'hffffffff >> inst_i[24:20];
    wire[31:0] op1_add_op2_res = op1_i + op2_i;
    wire[31:0] op1_jump_add_op2_jump_res = op1_jump_i + op2_jump_i;
    wire op1_ge_op2_signed = $signed(op1_i) >= $signed(op2_i);
    wire op1_ge_op2_unsigned = op1_i >= op2_i;
    wire op1_eq_op2 = op1_i == op2_i;

    reg[`RegBus] reg_wdata;
    reg reg_we;
    reg[`RegAddrBus] reg_waddr;
    reg mem_we;
    reg mem_req;
    reg hold_flag;
    reg jump_flag;
    reg[`InstAddrBus] jump_addr;

    assign reg_wdata_o = reg_wdata;
    assign reg_we_o = reg_we;
    assign reg_waddr_o = reg_waddr;
    assign mem_we_o = mem_we;
    assign mem_req_o = mem_req;
    assign hold_flag_o = hold_flag;
    assign jump_flag_o = jump_flag;
    assign jump_addr_o = jump_addr;
    assign sid_start_o = (opcode == `INST_TYPE_CUSTOM) &&
                         (funct3 == `INST_SID_FUNCT3) && !sid_done_i;
    assign rt_start_o = (opcode == `INST_TYPE_CUSTOM) &&
                        (funct3 == `INST_RT_FUNCT3) && !rt_done_i;
    assign if_data_o = op1_i[7:0];

    always @ (*) begin
        reg_wdata = `ZeroWord;
        reg_we = reg_we_i;
        reg_waddr = reg_waddr_i;
        mem_wdata_o = `ZeroWord;
        mem_raddr_o = `ZeroWord;
        mem_waddr_o = `ZeroWord;
        mem_we = `WriteDisable;
        mem_req = `RIB_NREQ;
        hold_flag = `HoldDisable;
        jump_flag = `JumpDisable;
        jump_addr = `ZeroWord;
        send_if_start_o = 1'b0;

        case (opcode)
            `INST_TYPE_I: begin
                case (funct3)
                    `INST_ADDI: reg_wdata = op1_add_op2_res;
                    `INST_SLTI: reg_wdata = {32{~op1_ge_op2_signed}} & 32'h1;
                    `INST_SLTIU: reg_wdata = {32{~op1_ge_op2_unsigned}} & 32'h1;
                    `INST_XORI: reg_wdata = op1_i ^ op2_i;
                    `INST_ORI: reg_wdata = op1_i | op2_i;
                    `INST_ANDI: reg_wdata = op1_i & op2_i;
                    `INST_SLLI: reg_wdata = reg1_rdata_i << inst_i[24:20];
                    `INST_SRI: begin
                        if (inst_i[30]) begin
                            reg_wdata = (sri_shift & sri_shift_mask) |
                                        ({32{reg1_rdata_i[31]}} & ~sri_shift_mask);
                        end else begin
                            reg_wdata = reg1_rdata_i >> inst_i[24:20];
                        end
                    end
                    default: begin
                        reg_we = `WriteDisable;
                    end
                endcase
            end
            `INST_TYPE_R: begin
                if ((inst_i[31:25] == 7'b0000000) ||
                    (inst_i[31:25] == 7'b0100000)) begin
                    case (funct3)
                        `INST_ADD_SUB: begin
                            if (inst_i[30]) reg_wdata = op1_i - op2_i;
                            else reg_wdata = op1_add_op2_res;
                        end
                        `INST_SLL: reg_wdata = op1_i << op2_i[4:0];
                        `INST_SLT: reg_wdata = {32{~op1_ge_op2_signed}} & 32'h1;
                        `INST_SLTU: reg_wdata = {32{~op1_ge_op2_unsigned}} & 32'h1;
                        `INST_XOR: reg_wdata = op1_i ^ op2_i;
                        `INST_SR: begin
                            if (inst_i[30]) begin
                                reg_wdata = (sr_shift & sr_shift_mask) |
                                            ({32{reg1_rdata_i[31]}} & ~sr_shift_mask);
                            end else begin
                                reg_wdata = reg1_rdata_i >> reg2_rdata_i[4:0];
                            end
                        end
                        `INST_OR: reg_wdata = op1_i | op2_i;
                        `INST_AND: reg_wdata = op1_i & op2_i;
                        default: reg_we = `WriteDisable;
                    endcase
                end else begin
                    reg_we = `WriteDisable;
                end
            end
            `INST_TYPE_L: begin
                case (funct3)
                    `INST_LB: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: reg_wdata = {{24{mem_rdata_i[7]}}, mem_rdata_i[7:0]};
                            2'b01: reg_wdata = {{24{mem_rdata_i[15]}}, mem_rdata_i[15:8]};
                            2'b10: reg_wdata = {{24{mem_rdata_i[23]}}, mem_rdata_i[23:16]};
                            default: reg_wdata = {{24{mem_rdata_i[31]}}, mem_rdata_i[31:24]};
                        endcase
                    end
                    `INST_LH: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_raddr_index == 2'b00)
                            reg_wdata = {{16{mem_rdata_i[15]}}, mem_rdata_i[15:0]};
                        else
                            reg_wdata = {{16{mem_rdata_i[31]}}, mem_rdata_i[31:16]};
                    end
                    `INST_LW: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        reg_wdata = mem_rdata_i;
                    end
                    `INST_LBU: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_raddr_index)
                            2'b00: reg_wdata = {24'h0, mem_rdata_i[7:0]};
                            2'b01: reg_wdata = {24'h0, mem_rdata_i[15:8]};
                            2'b10: reg_wdata = {24'h0, mem_rdata_i[23:16]};
                            default: reg_wdata = {24'h0, mem_rdata_i[31:24]};
                        endcase
                    end
                    `INST_LHU: begin
                        mem_req = `RIB_REQ;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_raddr_index == 2'b00)
                            reg_wdata = {16'h0, mem_rdata_i[15:0]};
                        else
                            reg_wdata = {16'h0, mem_rdata_i[31:16]};
                    end
                    default: reg_we = `WriteDisable;
                endcase
            end
            `INST_TYPE_S: begin
                case (funct3)
                    `INST_SB: begin
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        case (mem_waddr_index)
                            2'b00: mem_wdata_o = {mem_rdata_i[31:8], reg2_rdata_i[7:0]};
                            2'b01: mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[7:0], mem_rdata_i[7:0]};
                            2'b10: mem_wdata_o = {mem_rdata_i[31:24], reg2_rdata_i[7:0], mem_rdata_i[15:0]};
                            default: mem_wdata_o = {reg2_rdata_i[7:0], mem_rdata_i[23:0]};
                        endcase
                        reg_we = `WriteDisable;
                    end
                    `INST_SH: begin
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        if (mem_waddr_index == 2'b00)
                            mem_wdata_o = {mem_rdata_i[31:16], reg2_rdata_i[15:0]};
                        else
                            mem_wdata_o = {reg2_rdata_i[15:0], mem_rdata_i[15:0]};
                        reg_we = `WriteDisable;
                    end
                    `INST_SW: begin
                        mem_we = `WriteEnable;
                        mem_req = `RIB_REQ;
                        mem_waddr_o = op1_add_op2_res;
                        mem_raddr_o = op1_add_op2_res;
                        mem_wdata_o = reg2_rdata_i;
                        reg_we = `WriteDisable;
                    end
                    default: reg_we = `WriteDisable;
                endcase
            end
            `INST_TYPE_B: begin
                case (funct3)
                    `INST_BEQ: begin
                        jump_flag = op1_eq_op2;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                    `INST_BNE: begin
                        jump_flag = ~op1_eq_op2;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                    `INST_BLT: begin
                        jump_flag = ~op1_ge_op2_signed;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                    `INST_BGE: begin
                        jump_flag = op1_ge_op2_signed;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                    `INST_BLTU: begin
                        jump_flag = ~op1_ge_op2_unsigned;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                    `INST_BGEU: begin
                        jump_flag = op1_ge_op2_unsigned;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                    default: reg_we = `WriteDisable;
                endcase
                reg_we = `WriteDisable;
            end
            `INST_JAL, `INST_JALR: begin
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
                reg_wdata = op1_add_op2_res;
            end
            `INST_LUI, `INST_AUIPC: begin
                reg_wdata = op1_add_op2_res;
            end
            `INST_FENCE: begin
                jump_flag = `JumpEnable;
                jump_addr = op1_jump_add_op2_jump_res;
                reg_we = `WriteDisable;
            end
            `INST_TYPE_CUSTOM: begin
                mem_we = `WriteDisable;
                mem_req = `RIB_NREQ;
                if (funct3 == `INST_SID_FUNCT3) begin
                    reg_we = `WriteDisable;
                    if (sid_done_i) begin
                        jump_flag = `JumpDisable;
                        jump_addr = `ZeroWord;
                    end else begin
                        jump_flag = `JumpEnable;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                end else if (funct3 == `INST_RT_FUNCT3) begin
                    if (rt_done_i) begin
                        jump_flag = `JumpDisable;
                        jump_addr = `ZeroWord;
                        reg_we = `WriteEnable;
                        reg_wdata = {24'h0, i2c_temp_data_i};
                    end else begin
                        reg_we = `WriteDisable;
                        jump_flag = `JumpEnable;
                        jump_addr = op1_jump_add_op2_jump_res;
                    end
                end else if (funct3 == `INST_IF_FUNCT3) begin
                    if (inst_i[31:20] == 12'h000) begin
                        if (op1_ge_op2_signed) begin
                            if (send_if_done_i) begin
                                reg_we = `WriteEnable;
                                reg_waddr = inst_i[11:7];
                                reg_wdata = `ZeroWord;
                            end else begin
                                reg_we = `WriteDisable;
                                send_if_start_o = 1'b1;
                                jump_flag = `JumpEnable;
                                jump_addr = op1_jump_add_op2_jump_res;
                            end
                        end else begin
                            reg_we = `WriteEnable;
                            reg_waddr = inst_i[11:7];
                            reg_wdata = op1_i;
                        end
                    end else begin
                        reg_we = `WriteEnable;
                        reg_waddr = inst_i[11:7];
                        reg_wdata = op1_i +
                                    {{20{inst_i[31]}}, inst_i[31:20]};
                    end
                end else begin
                    reg_we = `WriteDisable;
                end
            end
            `INST_NOP_OP: begin
                reg_we = `WriteDisable;
            end
            default: begin
                reg_we = `WriteDisable;
            end
        endcase
    end

endmodule
