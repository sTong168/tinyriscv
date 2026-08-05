`include "defines.v"

// UART发送模块
// 用于实现自定义指令的UART发送功能
// 状态机：写UART_CTRL初始化 → 轮询UART_STATUS → 写UART_TXDATA发送10位学号ASCII
module inst_sid_ctrl(

    input wire clk,
    input wire rst,

    input wire start_i,                 // 开始发送信号(脉冲)
    input wire[`MemBus] mem_rdata_i,    // 从总线读取的数据

    output reg busy_o,                  // 忙标志
    output reg[`MemAddrBus] addr_o,     // 读、写地址
    output reg[`MemBus] wdata_o,        // 写数据
    output reg we_o,                    // 写标志
    output reg req_o                    // 请求标志

    );

    // UART寄存器地址
    parameter UART_CTRL    = 32'h30000000;
    parameter UART_STATUS  = 32'h30000004;
    parameter UART_TXDATA  = 32'h3000000c;

    // 状态编码
    localparam STATE_IDLE   = 4'd0;
    localparam STATE_INIT   = 4'd1;
    localparam STATE_POLL   = 4'd2;
    localparam STATE_SEND   = 4'd3;
    localparam STATE_DONE   = 4'd4;

    reg[3:0] state;
    reg[3:0] byte_cnt;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            state <= STATE_IDLE;
            busy_o <= `HoldDisable;
            addr_o <= `ZeroWord;
            wdata_o <= `ZeroWord;
            we_o <= `WriteDisable;
            req_o <= `RIB_NREQ;
            byte_cnt <= 4'd0;
        end else begin
            case (state)
                // 空闲状态，等待开始信号
                STATE_IDLE: begin
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                    if (start_i == `True) begin
                        state <= STATE_POLL;
                        busy_o <= `HoldEnable;
                        // addr_o <= UART_CTRL;
                        addr_o <= UART_STATUS;
                        // wdata_o <= 32'h3;  // 使能UART TX和RX
                        // we_o <= `WriteEnable;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                        byte_cnt <= 4'd0;
                    end
                end

                // UART初始化：写入0x3到UART_CTRL
                // STATE_INIT: begin
                //     state <= STATE_POLL;
                //     addr_o <= UART_STATUS;
                //     we_o <= `WriteDisable;
                //     req_o <= `RIB_REQ;
                // end

                // 轮询UART_STATUS，检查bit 0(TX忙标志)
                STATE_POLL: begin
                    if (mem_rdata_i[0] == 1'b0) begin
                        // UART可以发送新数据
                        state <= STATE_SEND;
                        addr_o <= UART_TXDATA;
                        we_o <= `WriteEnable;
                        req_o <= `RIB_REQ;
                        case (byte_cnt)
                            4'd0: wdata_o <= {24'h0, `ASCII_0};
                            4'd1: wdata_o <= {24'h0, `ASCII_1};
                            4'd2: wdata_o <= {24'h0, `ASCII_2};
                            4'd3: wdata_o <= {24'h0, `ASCII_3};
                            4'd4: wdata_o <= {24'h0, `ASCII_4};
                            4'd5: wdata_o <= {24'h0, `ASCII_5};
                            4'd6: wdata_o <= {24'h0, `ASCII_6};
                            4'd7: wdata_o <= {24'h0, `ASCII_7};
                            4'd8: wdata_o <= {24'h0, `ASCII_8};
                            4'd9: wdata_o <= {24'h0, `ASCII_9};
                            default: wdata_o <= `ZeroWord;
                        endcase
                    end else begin
                        // UART仍忙，继续轮询
                        state <= STATE_POLL;
                        addr_o <= UART_STATUS;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                    end
                end

                // 发送一个字节，然后切换到下一个或结束
                STATE_SEND: begin
                    if (byte_cnt >= 4'd9) begin
                        // 10位学号全部发送完毕
                        state <= STATE_DONE;
                        busy_o <= `HoldDisable;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_NREQ;
                    end else begin
                        // 继续发送下一个字节
                        state <= STATE_POLL;
                        byte_cnt <= byte_cnt + 1;
                        addr_o <= UART_STATUS;
                        we_o <= `WriteDisable;
                        req_o <= `RIB_REQ;
                    end
                end

                // 发送完毕，回到空闲状态
                STATE_DONE: begin
                    state <= STATE_IDLE;
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                end

                default: begin
                    state <= STATE_IDLE;
                    busy_o <= `HoldDisable;
                    we_o <= `WriteDisable;
                    req_o <= `RIB_NREQ;
                end
            endcase
        end
    end

endmodule
