`include "defines.v"

// I2C发送模块
// 用于实现自定义指令rT的I2C读写功能
// 状态机：写0xA5到I2C_ADDR → 写0xE3到I2C_SEND → 轮询I2C_RECV直到DONE → 写结果到rd
module i2c_send(

    input wire clk,
    input wire rst,

    input wire start_i,                     // 开始发送信号(脉冲)
    input wire[`MemBus] mem_rdata_i,        // 从总线读取的数据
    input wire[`RegAddrBus] reg_waddr_i,    // 目标寄存器rd地址(来自EX阶段)

    output reg busy_o,                      // 忙标志(暂停流水线)
    output reg[`MemAddrBus] addr_o,         // 读、写地址
    output reg[`MemBus] wdata_o,            // 写数据
    output reg we_o,                        // 写标志
    output reg req_o,                       // 请求标志
    output reg reg_we_o,                     // 写寄存器使能
    output reg[`RegAddrBus] reg_waddr_o,     // 写寄存器地址
    output reg[`RegBus] reg_wdata_o          // 写寄存器数据

    );

    // I2C寄存器地址
    parameter I2C_ADDR   = 32'h70010000;
    parameter I2C_SEND   = 32'h70020000;
    parameter I2C_RECV   = 32'h70030000;

    // 状态编码
    localparam STATE_IDLE    = 4'd0;
    localparam STATE_SET_ADDR = 4'd1;
    localparam STATE_TRIGGER = 4'd2;
    localparam STATE_POLL    = 4'd3;
    localparam STATE_DONE    = 4'd4;

    reg[3:0] state;
    reg[`RegAddrBus] saved_rd;
    reg[`RegBus] result;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            busy_o <= `HoldDisable;
            addr_o <= `ZeroWord;
            wdata_o <= `ZeroWord;
            we_o <= `WriteDisable;
            req_o <= `RIB_NREQ;
            saved_rd <= `ZeroWord;
            result <= `ZeroWord;
            reg_we_o <= `WriteDisable;
            reg_waddr_o <= `ZeroWord;
            reg_wdata_o <= `ZeroWord;
        end else begin
            case (state)
                // 空闲状态，等待开始信号
                STATE_IDLE: begin
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                    reg_we_o <= `WriteDisable;
                    reg_waddr_o <= `ZeroWord;
                    reg_wdata_o <= `ZeroWord;
                    if (start_i == `True) begin
                        saved_rd <= reg_waddr_i;  // 保存rd，流水线暂停后EX的指令会被清空
                        state <= STATE_SET_ADDR;
                        busy_o <= `HoldEnable;
                        addr_o <= I2C_ADDR;
                        wdata_o <= 32'hA5;        // I2C slave device address
                        we_o <= `WriteEnable;
                        req_o <= `RIB_REQ;
                    end
                end

                // 写I2C从设备地址到0x70010000
                STATE_SET_ADDR: begin
                    state <= STATE_TRIGGER;
                    addr_o <= I2C_SEND;
                    wdata_o <= 32'hE3;            // trigger I2C transaction
                    we_o <= `WriteEnable;
                    req_o <= `RIB_REQ;
                end

                // 写触发命令到0x70020000
                STATE_TRIGGER: begin
                    state <= STATE_POLL;
                    addr_o <= I2C_RECV;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_REQ;
                end

                // 轮询I2C_RECV直到buzy[31:30] == DONE (2'b10)
                STATE_POLL: begin
                    if (mem_rdata_i[31:30] == 2'b10) begin
                        // I2C传输完成，捕获结果
                        result <= mem_rdata_i;
                        state <= STATE_DONE;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                    end else begin
                        // 仍忙，继续轮询
                        state <= STATE_POLL;
                        addr_o <= I2C_RECV;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                    end
                end

                // 完成：写回目标寄存器，释放流水线
                STATE_DONE: begin
                    state <= STATE_IDLE;
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                    reg_we_o <= `WriteEnable;
                    reg_waddr_o <= saved_rd;
                    // reg_wdata_o <= result;
                    reg_wdata_o <= {24'b0, result[14:7]}; // 只读出温度芯片需要的位
                end

                default: begin
                    state <= STATE_IDLE;
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                    reg_we_o <= `WriteDisable;
                    reg_waddr_o <= `ZeroWord;
                    reg_wdata_o <= `ZeroWord;
                end
            endcase
        end
    end

endmodule
