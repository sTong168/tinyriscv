`include "../core/defines.v"

// tinyriscv + bridge_fpga 联合顶层模块
module tinyriscv_bridge_soc_top(

    input wire clk,
    input wire rst,

    // output wire over,         // 测试是否完成信号
    output wire succ,         // 测试是否成功信号

    // output wire halted_ind,   // jtag是否已经halt住CPU信号

    input wire uart_debug_pin, // 串口下载使能引脚

    output wire uart_tx_pin,  // UART发送引脚
    input wire uart_rx_pin,   // UART接收引脚

    // input wire jtag_TCK,      // JTAG TCK引脚
    // input wire jtag_TMS,      // JTAG TMS引脚
    // input wire jtag_TDI,      // JTAG TDI引脚
    // output wire jtag_TDO,     // JTAG TDO引脚

    output wire [3:0] pwm,    // PWM 输出引脚

    inout wire scl,           // I2C SCL
    inout wire sda            // I2C SDA

);

    // bridge 总线内部连接
    wire [`BridgeBus] bridge;

    // JTAG 引脚未引出，内部接空闲态 (TCK=0, TMS=1, TDI=0) 防止悬空误触发
    wire jtag_TCK;
    wire jtag_TMS;
    wire jtag_TDI;
    wire jtag_TDO;
    assign jtag_TCK = 1'b0;
    assign jtag_TMS = 1'b1;
    assign jtag_TDI = 1'b0;

    // over 和 halted_ind 内部信号
    wire over;
    wire halted_ind;

    // tinyriscv soc顶层模块例化
    tinyriscv_soc_top u_tinyriscv_soc_top(
        .clk            (clk),
        .rst            (rst),
        .over           (over),
        .succ           (succ),
        .halted_ind     (halted_ind),
        .uart_debug_pin (uart_debug_pin),
        .uart_tx_pin    (uart_tx_pin),
        .uart_rx_pin    (uart_rx_pin),
        .jtag_TCK       (jtag_TCK),
        .jtag_TMS       (jtag_TMS),
        .jtag_TDI       (jtag_TDI),
        .jtag_TDO       (jtag_TDO),
        .bridge         (bridge),
        .pwm            (pwm),
        .scl            (scl),
        .sda            (sda)
    );

    // bridge_fpga模块例化 (FPGA端RAM/ROM，通过bridge总线通信)
    bridge_fpga u_bridge_fpga(
        .clk        (clk),
        .rst        (rst),
        .bridge_io  (bridge)
    );

endmodule
