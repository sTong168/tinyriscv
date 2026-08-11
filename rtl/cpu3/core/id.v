`include "../../shared/defines.v"

// RV32I instruction decoder.
module cpu3_id(
    input wire[`InstBus] inst_i,
    input wire[`InstAddrBus] inst_addr_i,
    input wire[`RegBus] reg1_rdata_i,
    input wire[`RegBus] reg2_rdata_i,

    output reg[`RegAddrBus] reg1_raddr_o,
    output reg[`RegAddrBus] reg2_raddr_o,
    output reg[`MemAddrBus] op1_o,
    output reg[`MemAddrBus] op2_o,
    output reg[`MemAddrBus] op1_jump_o,
    output reg[`MemAddrBus] op2_jump_o,
    output reg[`InstBus] inst_o,
    output reg[`RegBus] reg1_rdata_o,
    output reg[`RegBus] reg2_rdata_o,
    output reg reg_we_o,
    output reg[`RegAddrBus] reg_waddr_o
    );

    wire[6:0] opcode = inst_i[6:0];
    wire[2:0] funct3 = inst_i[14:12];
    wire[6:0] funct7 = inst_i[31:25];
    wire[4:0] rd = inst_i[11:7];
    wire[4:0] rs1 = inst_i[19:15];
    wire[4:0] rs2 = inst_i[24:20];

    always @ (*) begin
        inst_o = inst_i;
        reg1_rdata_o = reg1_rdata_i;
        reg2_rdata_o = reg2_rdata_i;
        reg1_raddr_o = `ZeroReg;
        reg2_raddr_o = `ZeroReg;
        reg_we_o = `WriteDisable;
        reg_waddr_o = `ZeroReg;
        op1_o = `ZeroWord;
        op2_o = `ZeroWord;
        op1_jump_o = `ZeroWord;
        op2_jump_o = `ZeroWord;

        case (opcode)
            `INST_TYPE_I: begin
                case (funct3)
                    `INST_ADDI, `INST_SLTI, `INST_SLTIU, `INST_XORI,
                    `INST_ORI, `INST_ANDI, `INST_SLLI, `INST_SRI: begin
                        reg1_raddr_o = rs1;
                        reg_we_o = `WriteEnable;
                        reg_waddr_o = rd;
                        op1_o = reg1_rdata_i;
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]};
                    end
                    default: begin end
                endcase
            end
            `INST_TYPE_R: begin
                if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin
                    case (funct3)
                        `INST_ADD_SUB, `INST_SLL, `INST_SLT, `INST_SLTU,
                        `INST_XOR, `INST_SR, `INST_OR, `INST_AND: begin
                            reg1_raddr_o = rs1;
                            reg2_raddr_o = rs2;
                            reg_we_o = `WriteEnable;
                            reg_waddr_o = rd;
                            op1_o = reg1_rdata_i;
                            op2_o = reg2_rdata_i;
                        end
                        default: begin end
                    endcase
                end
            end
            `INST_TYPE_L: begin
                case (funct3)
                    `INST_LB, `INST_LH, `INST_LW, `INST_LBU, `INST_LHU: begin
                        reg1_raddr_o = rs1;
                        reg_we_o = `WriteEnable;
                        reg_waddr_o = rd;
                        op1_o = reg1_rdata_i;
                        op2_o = {{20{inst_i[31]}}, inst_i[31:20]};
                    end
                    default: begin end
                endcase
            end
            `INST_TYPE_S: begin
                case (funct3)
                    `INST_SB, `INST_SH, `INST_SW: begin
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = rs2;
                        op1_o = reg1_rdata_i;
                        op2_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};
                    end
                    default: begin end
                endcase
            end
            `INST_TYPE_B: begin
                case (funct3)
                    `INST_BEQ, `INST_BNE, `INST_BLT, `INST_BGE,
                    `INST_BLTU, `INST_BGEU: begin
                        reg1_raddr_o = rs1;
                        reg2_raddr_o = rs2;
                        op1_o = reg1_rdata_i;
                        op2_o = reg2_rdata_i;
                        op1_jump_o = inst_addr_i;
                        op2_jump_o = {{20{inst_i[31]}}, inst_i[7], inst_i[30:25],
                                      inst_i[11:8], 1'b0};
                    end
                    default: begin end
                endcase
            end
            `INST_JAL: begin
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                op1_o = inst_addr_i;
                op2_o = 32'h4;
                op1_jump_o = inst_addr_i;
                op2_jump_o = {{12{inst_i[31]}}, inst_i[19:12], inst_i[20],
                              inst_i[30:21], 1'b0};
            end
            `INST_JALR: begin
                reg1_raddr_o = rs1;
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                op1_o = inst_addr_i;
                op2_o = 32'h4;
                op1_jump_o = reg1_rdata_i;
                op2_jump_o = {{20{inst_i[31]}}, inst_i[31:20]};
            end
            `INST_LUI: begin
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                op1_o = {inst_i[31:12], 12'b0};
            end
            `INST_AUIPC: begin
                reg_we_o = `WriteEnable;
                reg_waddr_o = rd;
                op1_o = inst_addr_i;
                op2_o = {inst_i[31:12], 12'b0};
            end
            `INST_FENCE: begin
                op1_jump_o = inst_addr_i;
                op2_jump_o = 32'h4;
            end
            `INST_TYPE_CUSTOM: begin
                if (funct3 == `INST_SID_FUNCT3) begin
                    op1_jump_o = inst_addr_i;
                    op2_jump_o = `ZeroWord;
                end else if (funct3 == `INST_RT_FUNCT3) begin
                    reg_we_o = `WriteEnable;
                    reg_waddr_o = rd;
                    op1_jump_o = inst_addr_i;
                    op2_jump_o = `ZeroWord;
                end else if (funct3 == `INST_IF_FUNCT3) begin
                    // IF reads x[rs1] and x31.  EX may loop on the
                    // current PC while the UART sender is active.
                    reg1_raddr_o = rs1;
                    reg2_raddr_o = 5'd31;
                    reg_waddr_o = rd;
                    op1_o = reg1_rdata_i;
                    op2_o = reg2_rdata_i;
                    op1_jump_o = inst_addr_i;
                    op2_jump_o = `ZeroWord;
                end
            end
            default: begin end
        endcase
    end

endmodule
