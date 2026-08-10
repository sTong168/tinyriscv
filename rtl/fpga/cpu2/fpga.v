`include "../core/defines.v"

// FPGA综合顶层
module cpu2_fpga_top(
    input wire clk,
    input wire rst,

    output wire succ,

    input wire uart_debug_pin,

    output wire uart_tx_pin,
    input wire uart_rx_pin,

    output wire [2:0] PWM_o,

    inout wire i2c_scl,
    inout wire i2c_sda
);

    wire over_unused;
    wire [7:0] chip_to_fpga;
    wire [7:0] fpga_to_chip;

    // 测试通过指示：寄存器堆不复位（x27 会残留），所以在顶层做
    // "复位清零、succ 拉高后保持"的锁存，保证按复位后 LED 熄灭
    wire succ_raw;
    reg succ_led;
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            succ_led <= 1'b0;
        end else if (succ_raw == 1'b0) begin
            succ_led <= 1'b1;
        end
    end
    assign succ = ~ succ_led;

    // I2C 三态门 ↔ FPGA inout
    wire scl_o, scl_oe;
    wire sda_o, sda_oe;
    wire scl_in, sda_in;

    assign i2c_scl = scl_oe ? scl_o : 1'bz;
    assign scl_in = i2c_scl;
    assign i2c_sda = sda_oe ? sda_o : 1'bz;
    assign sda_in = i2c_sda;

    // 片外 ROM/RAM (FPGA内部模拟)
    cpu2_bridge_fpga u_ram_bridge (
        .clk(clk),
        .rst(rst),
        .chip_data_i(chip_to_fpga),
        .chip_data_o(fpga_to_chip)
    );

    cpu2_tinyriscv_soc_top u_soc(
        .clk(clk),
        .rst(rst),
        .over(over_unused),
        .succ(succ_raw),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .bridge_i(fpga_to_chip),
        .bridge_o(chip_to_fpga),
        .pwm(PWM_o),
        .scl_in(scl_in),
        .scl_o(scl_o),
        .scl_oe(scl_oe),
        .sda_in(sda_in),
        .sda_o(sda_o),
        .sda_oe(sda_oe)
    );

endmodule