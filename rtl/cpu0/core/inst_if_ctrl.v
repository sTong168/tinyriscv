`include "defines.v"

// IF指令UART发送控制模块
// 用于实现IF指令imm==0且x[rs1]>=x31时的单字节UART发送
// 状态机：轮询UART_STATUS → 写UART_TXDATA发送1字节 → 写回rd=0
module inst_if_ctrl(

    input wire clk,
    input wire rst,

    input wire start_i,                     // 开始发送信号(脉冲)
    input wire[7:0] send_byte_i,            // 要发送的字节(x[rs1][7:0])
    input wire[`RegAddrBus] rd_addr_i,      // 目标寄存器rd地址
    input wire[`MemBus] mem_rdata_i,        // 从总线读取的数据

    output reg busy_o,                      // 忙标志(暂停流水线)
    output reg[`MemAddrBus] addr_o,         // 读、写地址
    output reg[`MemBus] wdata_o,            // 写数据
    output reg we_o,                        // 写标志
    output reg req_o,                       // 请求标志
    output reg reg_we_o,                     // 写寄存器使能
    output reg[`RegAddrBus] reg_waddr_o,     // 写寄存器地址
    output reg[`RegBus] reg_wdata_o          // 写寄存器数据

    );

    // UART寄存器地址
    parameter UART_STATUS  = 32'h30000004;
    parameter UART_TXDATA  = 32'h3000000c;

    // 状态编码
    localparam STATE_IDLE   = 3'd0;
    localparam STATE_POLL   = 3'd1;
    localparam STATE_SEND   = 3'd2;
    localparam STATE_DONE   = 3'd3;

    reg[2:0] state;
    reg[7:0] saved_byte;
    reg[`RegAddrBus] saved_rd;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            busy_o <= `HoldDisable;
            addr_o <= `ZeroWord;
            wdata_o <= `ZeroWord;
            we_o <= `WriteDisable;
            req_o <= `RIB_NREQ;
            saved_byte <= 8'h0;
            saved_rd <= `ZeroWord;
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
                        saved_byte <= send_byte_i;
                        saved_rd <= rd_addr_i;
                        state <= STATE_POLL;
                        busy_o <= `HoldEnable;
                        addr_o <= UART_STATUS;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                    end
                end

                // 轮询UART_STATUS，检查bit 0(TX忙标志)
                STATE_POLL: begin
                    if (mem_rdata_i[0] == 1'b0) begin
                        // UART可以发送新数据
                        state <= STATE_SEND;
                        addr_o <= UART_TXDATA;
                        wdata_o <= {24'h0, saved_byte};
                        we_o <= `WriteEnable;
                        req_o <= `RIB_REQ;
                    end else begin
                        // UART仍忙，继续轮询
                        state <= STATE_POLL;
                        addr_o <= UART_STATUS;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                    end
                end

                // 发送一个字节
                STATE_SEND: begin
                    state <= STATE_DONE;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                end

                // 发送完毕，写回rd=0并释放流水线
                STATE_DONE: begin
                    state <= STATE_IDLE;
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                    reg_we_o <= `WriteEnable;
                    reg_waddr_o <= saved_rd;
                    reg_wdata_o <= `ZeroWord;
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
