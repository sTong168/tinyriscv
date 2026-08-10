// ============================================================
// Merged defines for 4-CPU tinyriscv SoC
// Base: cpu0, with cpu1/cpu2/cpu3 additions marked
// ============================================================

`define CpuResetAddr 32'h0

// --- Common (all CPUs) ---
`define RstEnable 1'b0
`define RstDisable 1'b1
`define ZeroWord 32'h0
`define ZeroReg 5'h0
`define WriteEnable 1'b1
`define WriteDisable 1'b0
`define ReadEnable 1'b1
`define ReadDisable 1'b0
`define True 1'b1
`define False 1'b0
`define ChipEnable 1'b1
`define ChipDisable 1'b0
`define JumpEnable 1'b1
`define JumpDisable 1'b0
`define HoldEnable 1'b1
`define HoldDisable 1'b0
`define LSEnable 1'b1
`define LSDisable 1'b0

`define RIB_ACK 1'b1
`define RIB_NACK 1'b0
`define RIB_REQ 1'b1
`define RIB_NREQ 1'b0

`define Hold_Flag_Bus   2:0
`define Hold_None       3'b000
`define Hold_Pc         3'b001
`define Hold_If_keep    3'b010
`define Hold_Id_keep    3'b011
`define Hold_If_keep_Id_clr 3'b100
`define Hold_If_clr     3'b110
`define Hold_Id_clr     3'b111

// --- Bus widths (common) ---
`define MemBus 31:0
`define MemAddrBus 31:0
`define InstBus 31:0
`define InstAddrBus 31:0
`define RegAddrBus 4:0
`define RegBus 31:0
`define RegWidth 32
`define RegNum 32
`define RegNumLog2 5

`define RomNum 256
`define MemNum 16

// --- Instruction opcodes (common) ---
`define INST_TYPE_I 7'b0010011
`define INST_ADDI   3'b000
`define INST_SLTI   3'b010
`define INST_SLTIU  3'b011
`define INST_XORI   3'b100
`define INST_ORI    3'b110
`define INST_ANDI   3'b111
`define INST_SLLI   3'b001
`define INST_SRI    3'b101

`define INST_TYPE_L 7'b0000011
`define INST_LB     3'b000
`define INST_LH     3'b001
`define INST_LW     3'b010
`define INST_LBU    3'b100
`define INST_LHU    3'b101

`define INST_TYPE_S 7'b0100011
`define INST_SB     3'b000
`define INST_SH     3'b001
`define INST_SW     3'b010

`define INST_TYPE_R_M 7'b0110011
`define INST_ADD_SUB 3'b000
`define INST_SLL    3'b001
`define INST_SLT    3'b010
`define INST_SLTU   3'b011
`define INST_XOR    3'b100
`define INST_SR     3'b101
`define INST_OR     3'b110
`define INST_AND    3'b111

`define INST_JAL    7'b1101111
`define INST_JALR   7'b1100111
`define INST_LUI    7'b0110111
`define INST_AUIPC  7'b0010111
`define INST_NOP    32'h00000001
`define INST_NOP_OP 7'b0000001

`define INST_TYPE_B 7'b1100011
`define INST_BEQ    3'b000
`define INST_BNE    3'b001
`define INST_BLT    3'b100
`define INST_BGE    3'b101
`define INST_BLTU   3'b110
`define INST_BGEU   3'b111

// --- cpu0 ---
`define BridgeBus 15:0
`define Stop 1'b1
`define NoStop 1'b0
`define SEL_ROM 1'b0
`define SEL_RAM 1'b1
`define MEM_Start 4'b1010
`define INST_MRET   32'h30200073
`define INST_RET    32'h00008067
`define INST_FENCE  7'b0001111
`define INST_ECALL  32'h73
`define INST_EBREAK 32'h00100073

// cpu0: custom instruction (opcode 0101111)
`define INST_TYPE_CUSTOM 7'b0101111
`define INST_CUSTOM_SID     3'h0
`define INST_CUSTOM_RT      3'h1
`define INST_CUSTOM_IF      3'h2
`define INST_CUSTOM_POPCNT  3'h3

// cpu0: short aliases for custom funct3
`define INST_SID 3'b000
`define INST_RT  3'b001
`define INST_IF  3'b010

// cpu0: I2C state machine
`define I2C_FREE 2'd0
`define I2C_BUSY 2'd1
`define I2C_DONE 2'd2

// cpu0: student ID ASCII (学号: 2025210875)
`define ASCII_0 8'h32
`define ASCII_1 8'h30
`define ASCII_2 8'h32
`define ASCII_3 8'h35
`define ASCII_4 8'h32
`define ASCII_5 8'h31
`define ASCII_6 8'h30
`define ASCII_7 8'h38
`define ASCII_8 8'h37
`define ASCII_9 8'h35

// --- cpu2 ---
// cpu2: opcode alias (same value as INST_TYPE_CUSTOM)
`define INST_CUSTOM 7'b0101111

// --- cpu3 ---
// cpu3: R-type alias (same value as INST_TYPE_R_M)
`define INST_TYPE_R 7'b0110011

// cpu3: custom instruction funct3 aliases
`define INST_SID_FUNCT3 3'b000
`define INST_RT_FUNCT3  3'b001
`define INST_IF_FUNCT3  3'b010

// cpu3: hold flag aliases
`define Hold_If 3'b010
`define Hold_Id 3'b011
