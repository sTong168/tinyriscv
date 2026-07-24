`include "defines.v"

module tinyriscv_top_IO (

    // === Input PADs ===
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  chip_sel,
    input  wire        uart_de,

    // === Output PADs ===
    output wire        over,
    output wire        succ,
    output wire        uart_tx,
    input  wire        uart_rx,
    output wire [3:0]  pwm,

    // === Bidirectional PADs (bridge 16-bit, split 8+8) ===
    inout  wire [7:0]  mfpga_mem_out,
    inout  wire [7:0]  mfpga_mem_in,

    // === Bidirectional PADs (I2C) ===
    inout  wire        msda,
    inout  wire        mscl

);

    // ============================================================
    // Internal wires
    // ============================================================
    // Input PAD → core
    wire        clk_core;
    wire        rst_core;
    wire [1:0]  chip_sel_core;
    wire        uart_debug_core;
    wire        uart_rx_core;
    // Core → output PAD
    wire        over_core;
    wire        succ_core;
    wire        uart_tx_core;
    wire [3:0]  pwm_core;

    // Bridge (16-bit, split direction/data)
    wire        bridge_oe;
    wire [15:0] bridge_o;
    wire [15:0] bridge_in;

    // I2C
    wire        scl_o;
    wire        scl_oe;
    wire        scl_in;
    wire        sda_o;
    wire        sda_oe;
    wire        sda_in;

    // =============================
    //  Input PADs
    // =============================
    // clk
    PDDW0204CDG mclk (
        .PAD(clk),           .C(clk_core),        .I(1'b0),
        .OEN(1'b1), .IE(1'b1), .DS(1'b0), .PE(1'b0)
    );
    // rst
    PDDW0204CDG mrst (
        .PAD(rst),           .C(rst_core),        .I(1'b0),
        .OEN(1'b1), .IE(1'b1), .DS(1'b0), .PE(1'b0)
    );
    // chip_sel[1:0] — 4 core片选 (msel0/msel1 匹配 io.file)
    PDDW0204CDG msel0 (
        .PAD(chip_sel[0]),   .C(chip_sel_core[0]), .I(1'b0),
        .OEN(1'b1), .IE(1'b1), .DS(1'b0), .PE(1'b0)
    );
    PDDW0204CDG msel1 (
        .PAD(chip_sel[1]),   .C(chip_sel_core[1]), .I(1'b0),
        .OEN(1'b1), .IE(1'b1), .DS(1'b0), .PE(1'b0)
    );
    // uart_debug
    PDDW0204CDG muart_d (
        .PAD(uart_de),       .C(uart_debug_core), .I(1'b0),
        .OEN(1'b1), .IE(1'b1), .DS(1'b0), .PE(1'b0)
    );
    // uart_rx
    PDDW0204CDG muart_rx (
        .PAD(uart_rx),       .C(uart_rx_core),    .I(1'b0),
        .OEN(1'b1), .IE(1'b1), .DS(1'b0), .PE(1'b0)
    );

    // =============================
    //  Output PADs
    // =============================
    // over
    PDDW0204CDG mover (
        .PAD(over),          .I(over_core),        .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );
    // succ
    PDDW0204CDG msucc (
        .PAD(succ),          .I(succ_core),        .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );
    // uart_tx
    PDDW0204CDG muart_tx (
        .PAD(uart_tx),       .I(uart_tx_core),     .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );

    // =============================
    //  PWM Output PADs
    // =============================
    PDDW0204CDG mpwm0 (
        .PAD(pwm[0]),        .I(pwm_core[0]),      .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );
    PDDW0204CDG mpwm1 (
        .PAD(pwm[1]),        .I(pwm_core[1]),      .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );
    PDDW0204CDG mpwm2 (
        .PAD(pwm[2]),        .I(pwm_core[2]),      .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );
    PDDW0204CDG mpwm3 (
        .PAD(pwm[3]),        .I(pwm_core[3]),      .C(),
        .OEN(1'b0), .IE(1'b0), .DS(1'b1), .PE(1'b0)
    );

    // =============================
    //  Bidirectional PADs: Bridge (16-bit, split 8+8 per io.file)
    //  实例名必须与 io.file 中的 inst name 一致
    //  bridge_oe=1 → 写模式: PAD驱动bridge_o到外部
    //  bridge_oe=0 → 读模式: PAD高阻, 外部数据进入bridge_in
    // =============================
    // Top: mfpga_mem_out[7:0]  → bridge_o[7:0] / bridge_in[7:0]
    PDDW0204CDG mfpga_mem_out0 (.PAD(mfpga_mem_out[0]), .I(bridge_o[0]),  .C(bridge_in[0]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out1 (.PAD(mfpga_mem_out[1]), .I(bridge_o[1]),  .C(bridge_in[1]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out2 (.PAD(mfpga_mem_out[2]), .I(bridge_o[2]),  .C(bridge_in[2]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out3 (.PAD(mfpga_mem_out[3]), .I(bridge_o[3]),  .C(bridge_in[3]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out4 (.PAD(mfpga_mem_out[4]), .I(bridge_o[4]),  .C(bridge_in[4]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out5 (.PAD(mfpga_mem_out[5]), .I(bridge_o[5]),  .C(bridge_in[5]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out6 (.PAD(mfpga_mem_out[6]), .I(bridge_o[6]),  .C(bridge_in[6]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_out7 (.PAD(mfpga_mem_out[7]), .I(bridge_o[7]),  .C(bridge_in[7]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    // Bottom: mfpga_mem_in[7:0]  → bridge_o[15:8] / bridge_in[15:8]
    PDDW0204CDG mfpga_mem_in0  (.PAD(mfpga_mem_in[0]),  .I(bridge_o[8]),  .C(bridge_in[8]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in1  (.PAD(mfpga_mem_in[1]),  .I(bridge_o[9]),  .C(bridge_in[9]),  .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in2  (.PAD(mfpga_mem_in[2]),  .I(bridge_o[10]), .C(bridge_in[10]), .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in3  (.PAD(mfpga_mem_in[3]),  .I(bridge_o[11]), .C(bridge_in[11]), .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in4  (.PAD(mfpga_mem_in[4]),  .I(bridge_o[12]), .C(bridge_in[12]), .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in5  (.PAD(mfpga_mem_in[5]),  .I(bridge_o[13]), .C(bridge_in[13]), .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in6  (.PAD(mfpga_mem_in[6]),  .I(bridge_o[14]), .C(bridge_in[14]), .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));
    PDDW0204CDG mfpga_mem_in7  (.PAD(mfpga_mem_in[7]),  .I(bridge_o[15]), .C(bridge_in[15]), .OEN(~bridge_oe), .IE(~bridge_oe), .DS(1'b1), .PE(1'b0));

    // =============================
    //  Bidirectional PADs: I2C (open-drain)
    //  scl_oe=1/sda_oe=1 → I2C模块驱动总线
    //  scl_oe=0/sda_oe=0 → I2C模块释放总线（高阻）
    // =============================
    // SCL
    PDDW0204CDG mscl_pad (
        .PAD(mscl),          .I(scl_o),
        .C(scl_in),
        .OEN(~scl_oe),
        .IE(~scl_oe),
        .DS(1'b1), .PE(1'b0)
    );
    // SDA
    PDDW0204CDG msda_pad (
        .PAD(msda),          .I(sda_o),
        .C(sda_in),
        .OEN(~sda_oe),
        .IE(~sda_oe),
        .DS(1'b1), .PE(1'b0)
    );

    // =============================
    //  Core instantiation
    // =============================
    tinyriscv_soc_top u_soc (
        .clk            (clk_core),
        .rst            (rst_core),
        .over           (over_core),
        .succ           (succ_core),
        .uart_debug_pin (uart_debug_core),
        .uart_tx_pin    (uart_tx_core),
        .uart_rx_pin    (uart_rx_core),
        .bridge_in      (bridge_in),
        .bridge_o       (bridge_o),
        .bridge_oe      (bridge_oe),
        .pwm            (pwm_core),
        .scl_in         (scl_in),
        .scl_o          (scl_o),
        .scl_oe         (scl_oe),
        .sda_in         (sda_in),
        .sda_o          (sda_o),
        .sda_oe         (sda_oe)
    );

endmodule
