`include "../core/defines.v"

// FPGA board-validation wrapper. The bridge wires are internal because both
// endpoints are placed in the same FPGA during board testing.
module fpga_test_top(
    input wire clk,
    input wire rst,
    output wire over,
    output wire succ,
    input wire uart_debug_pin,
    output wire uart_tx_pin,
    input wire uart_rx_pin,
    output wire[3:0] pwm,
    inout wire io_sda,
    inout wire io_scl
    );

    wire[7:0] soc_bridge_i;
    wire[7:0] soc_bridge_o;
    wire scl_in;
    wire scl_o;
    wire scl_oe;
    wire sda_in;
    wire sda_o;
    wire sda_oe;

    assign scl_in = io_scl;
    assign io_scl = scl_oe ? scl_o : 1'bz;
    assign sda_in = io_sda;
    assign io_sda = sda_oe ? sda_o : 1'bz;

    tinyriscv_soc_top u_tinyriscv_soc(
        .clk(clk),
        .rst(rst),
        .over(over),
        .succ(succ),
        .uart_debug_pin(uart_debug_pin),
        .uart_tx_pin(uart_tx_pin),
        .uart_rx_pin(uart_rx_pin),
        .bridge_i(soc_bridge_i),
        .bridge_o(soc_bridge_o),
        .pwm(pwm),
        .scl_in(scl_in),
        .scl_o(scl_o),
        .scl_oe(scl_oe),
        .sda_in(sda_in),
        .sda_o(sda_o),
        .sda_oe(sda_oe)
    );

    fpga_bridge_top u_fpga_bridge_top(
        .clk(clk),
        .rst(rst),
        .bridge_i(soc_bridge_o),
        .bridge_o(soc_bridge_i)
    );

endmodule
