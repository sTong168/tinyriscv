`include "../core/defines.v"

// tinyriscv + bridge_fpga 联合顶层模块
module tinyriscv_bridge_soc_top(

    input wire clk,
    input wire rst,

    // output wire succ,         // 测试是否成功信号

    input wire uart_debug_pin, // 串口下载使能引脚

    output wire uart_tx_pin,  // UART发送引脚
    input wire uart_rx_pin,   // UART接收引脚

    output wire pwm    // PWM 输出引脚

    // inout wire scl,           // I2C SCL
    // inout wire sda            // I2C SDA

);

    // bridge 总线内部连接
    wire [`BridgeBus] bridge;

    wire [3:0] pwm_wire;
    assign pwm = pwm_wire[0];

    // tinyriscv soc顶层模块例化
    tinyriscv_soc_top u_tinyriscv_soc_top(
        .clk            (clk),
        .rst            (rst),
        .over           (over),
        .succ           (succ),
        .uart_debug_pin (uart_debug_pin),
        .uart_tx_pin    (uart_tx_pin),
        .uart_rx_pin    (uart_rx_pin),
        .bridge         (bridge),
        .pwm            (pwm_wire),
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