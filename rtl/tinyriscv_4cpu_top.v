`include "cpu0/core/defines.v"

// 4-CPU tinyriscv SOC top module
// - chip_sel[1:0] selects active CPU (only selected CPU gets clock)
// - chip_sel=00: CPU0 gets full bidirectional bridge (16-bit, _in/_o/_oe)
// - chip_sel!=00: selected CPU gets 8-in/8-out bridge (bridge_i[7:0], bridge_o[7:0])
// - All output signals (over/succ/uart_tx/pwm/I2C) muxed by chip_sel
// - uart_debug is muxed by chip_sel, only one PAD pin needed
module tinyriscv_4cpu_top(

    // System
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  chip_sel,

    // UART debug enable pin (muxed to selected CPU by chip_sel)
    input  wire        uart_debug_pin,

    // Muxed output signals (one set, selected by chip_sel)
    output wire        over,
    output wire        succ,
    output wire        uart_tx_pin,
    input  wire        uart_rx_pin,
    output wire [3:0]  pwm,

    // Bridge -- split OE for per-byte PAD control
    input  wire [15:0] bridge_in,
    output wire [15:0] bridge_o,
    output wire        bridge_oe_hi,  // OE for bits[15:8]
    output wire        bridge_oe_lo,  // OE for bits[7:0]

    // I2C (muxed to selected CPU)
    input  wire        scl_in,
    output wire        scl_o,
    output wire        scl_oe,
    input  wire        sda_in,
    output wire        sda_o,
    output wire        sda_oe

);

    // ================================================================
    // Chip select one-hot decode
    // ================================================================
    wire [3:0] sel;
    assign sel[0] = (chip_sel == 2'b00);
    assign sel[1] = (chip_sel == 2'b01);
    assign sel[2] = (chip_sel == 2'b10);
    assign sel[3] = (chip_sel == 2'b11);

    wire bridge_bidi_mode = (chip_sel == 2'b00);

    // ================================================================
    // uart_debug mux: 片选到哪个CPU，哪个CPU收到uart_debug信号
    // ================================================================
    wire cpu0_uart_debug;
    wire cpu1_uart_debug;
    wire cpu2_uart_debug;
    wire cpu3_uart_debug;
    assign cpu0_uart_debug = sel[0] ? uart_debug_pin : 1'b0;
    assign cpu1_uart_debug = sel[1] ? uart_debug_pin : 1'b0;
    assign cpu2_uart_debug = sel[2] ? uart_debug_pin : 1'b0;
    assign cpu3_uart_debug = sel[3] ? uart_debug_pin : 1'b0;

    // ================================================================
    // Per-CPU signals
    // ================================================================
    // Clock gating: only selected CPU receives clock
    wire cpu0_clk;
    wire cpu1_clk;
    wire cpu2_clk;
    wire cpu3_clk;
    assign cpu0_clk = clk & sel[0];
    assign cpu1_clk = clk & sel[1];
    assign cpu2_clk = clk & sel[2];
    assign cpu3_clk = clk & sel[3];

    // --- CPU0 signals (full 16-bit bidi bridge: _in/_o/_oe) ---
    wire        cpu0_over;
    wire        cpu0_succ;
    wire        cpu0_uart_tx;
    wire [3:0]  cpu0_pwm;
    wire [15:0] cpu0_bridge_in;
    wire [15:0] cpu0_bridge_o;
    wire        cpu0_bridge_oe;
    wire        cpu0_scl_o;
    wire        cpu0_scl_oe;
    wire        cpu0_sda_o;
    wire        cpu0_sda_oe;

    // --- CPU1 signals (8-in/8-out bridge: bridge_i[7:0], bridge_o[7:0], 无bridge_oe) ---
    wire        cpu1_over;
    wire        cpu1_succ;
    wire        cpu1_uart_tx;
    wire [3:0]  cpu1_pwm;
    wire [7:0]  cpu1_bridge_i;
    wire [7:0]  cpu1_bridge_o;
    wire        cpu1_scl_o;
    wire        cpu1_scl_oe;
    wire        cpu1_sda_o;
    wire        cpu1_sda_oe;

    // --- CPU2 signals (8-in/8-out bridge: bridge_i[7:0], bridge_o[7:0], 无bridge_oe) ---
    wire        cpu2_over;
    wire        cpu2_succ;
    wire        cpu2_uart_tx;
    wire [3:0]  cpu2_pwm;
    wire [7:0]  cpu2_bridge_i;
    wire [7:0]  cpu2_bridge_o;
    wire        cpu2_scl_o;
    wire        cpu2_scl_oe;
    wire        cpu2_sda_o;
    wire        cpu2_sda_oe;

    // --- CPU3 signals (8-in/8-out bridge: bridge_i[7:0], bridge_o[7:0], 无bridge_oe) ---
    wire        cpu3_over;
    wire        cpu3_succ;
    wire        cpu3_uart_tx;
    wire [3:0]  cpu3_pwm;
    wire [7:0]  cpu3_bridge_i;
    wire [7:0]  cpu3_bridge_o;
    wire        cpu3_scl_o;
    wire        cpu3_scl_oe;
    wire        cpu3_sda_o;
    wire        cpu3_sda_oe;

    // ================================================================
    // Bridge control
    // ================================================================

    // CPU0: full 16-bit bridge, only gets data when selected
    assign cpu0_bridge_in = sel[0] ? bridge_in : 16'h0;

    // CPU1-3: 8-bit bridge_i 接收外部bridge_in的低8位(输入口)
    //           8-bit bridge_o 输出到外部bridge_o的高8位(输出口)
    assign cpu1_bridge_i = sel[1] ? bridge_in[7:0] : 8'h0;
    assign cpu2_bridge_i = sel[2] ? bridge_in[7:0] : 8'h0;
    assign cpu3_bridge_i = sel[3] ? bridge_in[7:0] : 8'h0;

    // bridge_o[15:8]: CPU0用高8位; CPU1-3用各自的8-bit bridge_o
    assign bridge_o[15:8] = sel[0] ? cpu0_bridge_o[15:8] :
                            sel[1] ? cpu1_bridge_o :
                            sel[2] ? cpu2_bridge_o :
                                           cpu3_bridge_o;

    // bridge_o[7:0]: 仅CPU0 bidi模式下有效
    assign bridge_o[7:0]  = sel[0] ? cpu0_bridge_o[7:0] : 8'h00;

    // bridge_oe: bidi模式(CPU0)用CPU0的oe; 8-in/8-out模式写死hi=1,lo=0
    assign bridge_oe_hi = bridge_bidi_mode ? cpu0_bridge_oe : 1'b1;
    assign bridge_oe_lo = bridge_bidi_mode ? cpu0_bridge_oe : 1'b0;

    // ================================================================
    // Output mux: over, succ
    // ================================================================
    assign over = sel[0] ? cpu0_over :
                  sel[1] ? cpu1_over :
                  sel[2] ? cpu2_over :
                          cpu3_over;

    assign succ = sel[0] ? cpu0_succ :
                  sel[1] ? cpu1_succ :
                  sel[2] ? cpu2_succ :
                          cpu3_succ;

    // ================================================================
    // Output mux: uart_tx
    // ================================================================
    assign uart_tx_pin = sel[0] ? cpu0_uart_tx :
                         sel[1] ? cpu1_uart_tx :
                         sel[2] ? cpu2_uart_tx :
                                 cpu3_uart_tx;

    // ================================================================
    // Output mux: pwm[3:0]
    // ================================================================
    assign pwm = sel[0] ? cpu0_pwm :
                 sel[1] ? cpu1_pwm :
                 sel[2] ? cpu2_pwm :
                         cpu3_pwm;

    // ================================================================
    // I2C mux: outputs from selected CPU, inputs broadcast to all
    // ================================================================
    assign scl_o  = sel[0] ? cpu0_scl_o  :
                    sel[1] ? cpu1_scl_o  :
                    sel[2] ? cpu2_scl_o  :
                            cpu3_scl_o;

    assign scl_oe = sel[0] ? cpu0_scl_oe :
                    sel[1] ? cpu1_scl_oe :
                    sel[2] ? cpu2_scl_oe :
                            cpu3_scl_oe;

    assign sda_o  = sel[0] ? cpu0_sda_o  :
                    sel[1] ? cpu1_sda_o  :
                    sel[2] ? cpu2_sda_o  :
                            cpu3_sda_o;

    assign sda_oe = sel[0] ? cpu0_sda_oe :
                    sel[1] ? cpu1_sda_oe :
                    sel[2] ? cpu2_sda_oe :
                            cpu3_sda_oe;

    // ================================================================
    // CPU0 instantiation (chip_sel=00, full bidirectional bridge)
    //   clk:        gated clock, only active when chip_sel==00
    //   rst:        shared reset (active low)
    //   over/succ:  test completion signals (from regs[26]/[27])
    //   uart_debug: serial download enable (muxed from PAD)
    //   uart_tx/rx: UART communication (tx muxed out, rx broadcast in)
    //   bridge:     16-bit external bus (_in[15:0]/_o[15:0]/_oe split for PAD control)
    //   pwm:        4-bit PWM output
    //   scl/sda:    I2C bus (_in/_o/_oe split for open-drain PAD control)
    // ================================================================
    cpu0_tinyriscv_soc_top_pad u_cpu0 (
        .clk            (cpu0_clk),
        .rst            (rst),
        .over           (cpu0_over),
        .succ           (cpu0_succ),
        .uart_debug_pin (cpu0_uart_debug),
        .uart_tx_pin    (cpu0_uart_tx),
        .uart_rx_pin    (uart_rx_pin),
        .bridge_in      (cpu0_bridge_in),
        .bridge_o       (cpu0_bridge_o),
        .bridge_oe      (cpu0_bridge_oe),
        .pwm            (cpu0_pwm),
        .scl_in         (scl_in),
        .scl_o          (cpu0_scl_o),
        .scl_oe         (cpu0_scl_oe),
        .sda_in         (sda_in),
        .sda_o          (cpu0_sda_o),
        .sda_oe         (cpu0_sda_oe)
    );

    // ================================================================
    // CPU1 instantiation (chip_sel=01, 8-in/8-out bridge)
    //   bridge_i[7:0]: 8位输入，连接外部bridge低8位
    //   bridge_o[7:0]: 8位输出，连接外部bridge高8位
    //   无bridge_oe，三态门使能由4cpu模块根据chip_sel写死
    // ================================================================
    cpu1_tinyriscv_soc_top u_cpu1 (
        .clk            (cpu1_clk),
        .rst            (rst),
        .over           (cpu1_over),
        .succ           (cpu1_succ),
        .uart_debug_pin (cpu1_uart_debug),
        .uart_tx_pin    (cpu1_uart_tx),
        .uart_rx_pin    (uart_rx_pin),
        .bridge_i       (cpu1_bridge_i),
        .bridge_o       (cpu1_bridge_o),
        .pwm            (cpu1_pwm),
        .scl_in         (scl_in),
        .scl_o          (cpu1_scl_o),
        .scl_oe         (cpu1_scl_oe),
        .sda_in         (sda_in),
        .sda_o          (cpu1_sda_o),
        .sda_oe         (cpu1_sda_oe)
    );

    // ================================================================
    // CPU2 instantiation (chip_sel=10, 8-in/8-out bridge)
    //   接口同CPU1，无em_req/em_ack
    //   模块已接入
    // ================================================================
    cpu2_tinyriscv_soc_top u_cpu2 (
        .clk            (cpu2_clk),
        .rst            (rst),
        .over           (cpu2_over),
        .succ           (cpu2_succ),
        .uart_debug_pin (cpu2_uart_debug),
        .uart_tx_pin    (cpu2_uart_tx),
        .uart_rx_pin    (uart_rx_pin),
        .bridge_i       (cpu2_bridge_i),
        .bridge_o       (cpu2_bridge_o),
        .pwm            (cpu2_pwm),
        .scl_in         (scl_in),
        .scl_o          (cpu2_scl_o),
        .scl_oe         (cpu2_scl_oe),
        .sda_in         (sda_in),
        .sda_o          (cpu2_sda_o),
        .sda_oe         (cpu2_sda_oe)
    );

    // ================================================================
    // CPU3 instantiation (chip_sel=11, 8-in/8-out bridge)
    //   接口同CPU1
    // ================================================================
    cpu3_tinyriscv_soc_top u_cpu3 (
        .clk            (cpu3_clk),
        .rst            (rst),
        .over           (cpu3_over),
        .succ           (cpu3_succ),
        .uart_debug_pin (cpu3_uart_debug),
        .uart_tx_pin    (cpu3_uart_tx),
        .uart_rx_pin    (uart_rx_pin),
        .bridge_i       (cpu3_bridge_i),
        .bridge_o       (cpu3_bridge_o),
        .pwm            (cpu3_pwm),
        .scl_in         (scl_in),
        .scl_o          (cpu3_scl_o),
        .scl_oe         (cpu3_scl_oe),
        .sda_in         (sda_in),
        .sda_o          (cpu3_sda_o),
        .sda_oe         (cpu3_sda_oe)
    );

endmodule
