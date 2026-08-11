`include "shared/defines.v"

// 4-CPU tinyriscv SOC top module
// - chip_sel[1:0] selects active CPU (only selected CPU gets clock)
// - chip_sel=00/01: CPU0/CPU1 full 16-bit half-duplex bridge (_in/_o/_oe)
// - chip_sel=10/11: CPU2/CPU3 8-in/8-out bridge (bridge_i[7:0], bridge_o[7:0])
// - Shared peripherals: regs, pwm, uart_debug instantiated once, muxed by chip_sel
// - uart_debug and selected CPU share RIB bus (same as original single-CPU design)
module tinyriscv_4cpu_top(

    // System
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  chip_sel,

    // UART debug enable pin (shared uart_debug uses this directly)
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

    // CPU0 + CPU1 use the same 16-bit half-duplex protocol / PAD OE style
    wire bridge_bidi_mode = (chip_sel == 2'b00) || (chip_sel == 2'b01);

    // ================================================================
    // Per-CPU signal declarations (must precede mux logic for VCS)
    // ================================================================
    // Clock gating: only selected CPU receives clock (runs concurrently with uart_debug)
    wire cpu0_clk, cpu1_clk, cpu2_clk, cpu3_clk;
    assign cpu0_clk = clk & sel[0];
    assign cpu1_clk = clk & sel[1];
    assign cpu2_clk = clk & sel[2];
    assign cpu3_clk = clk & sel[3];

    // --- CPU0 signals (full 16-bit bidi bridge: _in/_o/_oe) ---
    wire [15:0] cpu0_bridge_in;
    wire [15:0] cpu0_bridge_o;
    wire        cpu0_bridge_oe;
    wire        cpu0_scl_o, cpu0_scl_oe;
    wire        cpu0_sda_o, cpu0_sda_oe;
    wire        cpu0_uart_tx;
    // regs interface
    wire        cpu0_reg_we;
    wire [4:0]  cpu0_reg_waddr;
    wire [31:0] cpu0_reg_wdata;
    wire [4:0]  cpu0_reg_raddr1;
    wire [4:0]  cpu0_reg_raddr2;
    // debug bus
    wire [31:0] cpu0_dbg_rdata;
    wire        cpu0_dbg_ack;
    // pwm bus
    wire        cpu0_pwm_we;
    wire [31:0] cpu0_pwm_addr;
    wire [31:0] cpu0_pwm_data;

    // --- CPU1 signals (16-bit bidi bridge, same as CPU0) ---
    wire [15:0] cpu1_bridge_in;
    wire [15:0] cpu1_bridge_o;
    wire        cpu1_bridge_oe;
    wire        cpu1_scl_o, cpu1_scl_oe;
    wire        cpu1_sda_o, cpu1_sda_oe;
    wire        cpu1_uart_tx;
    wire        cpu1_reg_we;
    wire [4:0]  cpu1_reg_waddr;
    wire [31:0] cpu1_reg_wdata;
    wire [4:0]  cpu1_reg_raddr1;
    wire [4:0]  cpu1_reg_raddr2;
    wire [31:0] cpu1_dbg_rdata;
    wire        cpu1_dbg_ack;
    wire        cpu1_pwm_we;
    wire [31:0] cpu1_pwm_addr;
    wire [31:0] cpu1_pwm_data;

    // --- CPU2 signals (8-in/8-out bridge) ---
    wire [7:0]  cpu2_bridge_i;
    wire [7:0]  cpu2_bridge_o;
    wire        cpu2_scl_o, cpu2_scl_oe;
    wire        cpu2_sda_o, cpu2_sda_oe;
    wire        cpu2_uart_tx;
    wire        cpu2_reg_we;
    wire [4:0]  cpu2_reg_waddr;
    wire [31:0] cpu2_reg_wdata;
    wire [4:0]  cpu2_reg_raddr1;
    wire [4:0]  cpu2_reg_raddr2;
    wire [31:0] cpu2_dbg_rdata;
    wire        cpu2_dbg_ack;
    wire        cpu2_pwm_we;
    wire [31:0] cpu2_pwm_addr;
    wire [31:0] cpu2_pwm_data;

    // --- CPU3 signals (8-in/8-out bridge) ---
    wire [7:0]  cpu3_bridge_i;
    wire [7:0]  cpu3_bridge_o;
    wire        cpu3_scl_o, cpu3_scl_oe;
    wire        cpu3_sda_o, cpu3_sda_oe;
    wire        cpu3_uart_tx;
    wire        cpu3_reg_we;
    wire [4:0]  cpu3_reg_waddr;
    wire [31:0] cpu3_reg_wdata;
    wire [4:0]  cpu3_reg_raddr1;
    wire [4:0]  cpu3_reg_raddr2;
    wire [31:0] cpu3_dbg_rdata;
    wire        cpu3_dbg_ack;
    wire        cpu3_pwm_we;
    wire [31:0] cpu3_pwm_addr;
    wire [31:0] cpu3_pwm_data;

    // Debug bus output wires (shared uart_debug → selected CPU)
    wire        cpu0_dbg_req,   cpu1_dbg_req,   cpu2_dbg_req,   cpu3_dbg_req;
    wire        cpu0_dbg_we,    cpu1_dbg_we,    cpu2_dbg_we,    cpu3_dbg_we;
    wire [31:0] cpu0_dbg_addr,  cpu1_dbg_addr,  cpu2_dbg_addr,  cpu3_dbg_addr;
    wire [31:0] cpu0_dbg_wdata, cpu1_dbg_wdata, cpu2_dbg_wdata, cpu3_dbg_wdata;
    wire        cpu0_dbg_valid, cpu1_dbg_valid, cpu2_dbg_valid, cpu3_dbg_valid;

    // ================================================================
    // Shared uart_debug: 2-FF synchronizer + instantiation
    // ================================================================
    reg dbg_sync0, dbg_sync1;
    always @(posedge clk) begin
        dbg_sync0 <= uart_debug_pin;
        dbg_sync1 <= dbg_sync0;
    end
    wire uart_debug_synced = dbg_sync1;

    wire        dbg_req;
    wire        dbg_we;
    wire [31:0] dbg_addr;
    wire [31:0] dbg_wdata;
    wire [31:0] dbg_rdata;
    wire        dbg_ack;
    wire        dbg_valid;

    shared_uart_debug u_uart_debug(
        .clk(clk),
        .rst(rst),
        .debug_en_i(uart_debug_synced),
        .req_o(dbg_req),
        .mem_we_o(dbg_we),
        .mem_addr_o(dbg_addr),
        .mem_wdata_o(dbg_wdata),
        .mem_rdata_i(dbg_rdata),
        .ack_i(dbg_ack),
        .mem_valid_o(dbg_valid)
    );

    // ================================================================
    // Shared regs: muxed interface from all CPUs
    // ================================================================
    wire [4:0]  muxed_reg_waddr;
    wire [31:0] muxed_reg_wdata;
    wire        muxed_reg_we;
    wire [4:0]  muxed_reg_raddr1;
    wire [4:0]  muxed_reg_raddr2;
    wire [31:0] shared_reg_rdata1;
    wire [31:0] shared_reg_rdata2;

    assign muxed_reg_we     = sel[0] ? cpu0_reg_we     : sel[1] ? cpu1_reg_we     :
                                sel[2] ? cpu2_reg_we     : cpu3_reg_we;
    assign muxed_reg_waddr  = sel[0] ? cpu0_reg_waddr  : sel[1] ? cpu1_reg_waddr  :
                                sel[2] ? cpu2_reg_waddr  : cpu3_reg_waddr;
    assign muxed_reg_wdata  = sel[0] ? cpu0_reg_wdata  : sel[1] ? cpu1_reg_wdata  :
                                sel[2] ? cpu2_reg_wdata  : cpu3_reg_wdata;
    assign muxed_reg_raddr1 = sel[0] ? cpu0_reg_raddr1 : sel[1] ? cpu1_reg_raddr1 :
                                sel[2] ? cpu2_reg_raddr1 : cpu3_reg_raddr1;
    assign muxed_reg_raddr2 = sel[0] ? cpu0_reg_raddr2 : sel[1] ? cpu1_reg_raddr2 :
                                sel[2] ? cpu2_reg_raddr2 : cpu3_reg_raddr2;

    shared_regs u_regs(
        .clk(clk),
        .rst(rst),
        .we_i(muxed_reg_we),
        .waddr_i(muxed_reg_waddr),
        .wdata_i(muxed_reg_wdata),
        .raddr1_i(muxed_reg_raddr1),
        .rdata1_o(shared_reg_rdata1),
        .raddr2_i(muxed_reg_raddr2),
        .rdata2_o(shared_reg_rdata2),
        .over(over),
        .succ(succ)
    );

    // Broadcast shared regs read data to all cores
    wire [31:0] cpu0_rdata1 = shared_reg_rdata1;
    wire [31:0] cpu0_rdata2 = shared_reg_rdata2;
    wire [31:0] cpu1_rdata1 = shared_reg_rdata1;
    wire [31:0] cpu1_rdata2 = shared_reg_rdata2;
    wire [31:0] cpu2_rdata1 = shared_reg_rdata1;
    wire [31:0] cpu2_rdata2 = shared_reg_rdata2;
    wire [31:0] cpu3_rdata1 = shared_reg_rdata1;
    wire [31:0] cpu3_rdata2 = shared_reg_rdata2;

    // ================================================================
    // Shared PWM: muxed bus from all CPUs
    // ================================================================
    wire        muxed_pwm_we;
    wire [31:0] muxed_pwm_addr;
    wire [31:0] muxed_pwm_data;

    assign muxed_pwm_we   = sel[0] ? cpu0_pwm_we   : sel[1] ? cpu1_pwm_we   :
                               sel[2] ? cpu2_pwm_we   : cpu3_pwm_we;
    assign muxed_pwm_addr  = sel[0] ? cpu0_pwm_addr  : sel[1] ? cpu1_pwm_addr  :
                               sel[2] ? cpu2_pwm_addr  : cpu3_pwm_addr;
    assign muxed_pwm_data  = sel[0] ? cpu0_pwm_data  : sel[1] ? cpu1_pwm_data  :
                               sel[2] ? cpu2_pwm_data  : cpu3_pwm_data;

    shared_pwm u_pwm(
        .clk(clk),
        .rst(rst),
        .we_i(muxed_pwm_we),
        .addr_i(muxed_pwm_addr),
        .data_i(muxed_pwm_data),
        .pwm_o(pwm)
    );

    // ================================================================
    // Shared uart_debug bus: mux to/from selected CPU
    // ================================================================
    // Outputs: shared uart_debug → selected CPU
    assign cpu0_dbg_req   = sel[0] ? dbg_req   : 1'b0;
    assign cpu1_dbg_req   = sel[1] ? dbg_req   : 1'b0;
    assign cpu2_dbg_req   = sel[2] ? dbg_req   : 1'b0;
    assign cpu3_dbg_req   = sel[3] ? dbg_req   : 1'b0;

    assign cpu0_dbg_we    = sel[0] ? dbg_we    : 1'b0;
    assign cpu1_dbg_we    = sel[1] ? dbg_we    : 1'b0;
    assign cpu2_dbg_we    = sel[2] ? dbg_we    : 1'b0;
    assign cpu3_dbg_we    = sel[3] ? dbg_we    : 1'b0;

    assign cpu0_dbg_addr  = sel[0] ? dbg_addr  : 32'h0;
    assign cpu1_dbg_addr  = sel[1] ? dbg_addr  : 32'h0;
    assign cpu2_dbg_addr  = sel[2] ? dbg_addr  : 32'h0;
    assign cpu3_dbg_addr  = sel[3] ? dbg_addr  : 32'h0;

    assign cpu0_dbg_wdata = sel[0] ? dbg_wdata : 32'h0;
    assign cpu1_dbg_wdata = sel[1] ? dbg_wdata : 32'h0;
    assign cpu2_dbg_wdata = sel[2] ? dbg_wdata : 32'h0;
    assign cpu3_dbg_wdata = sel[3] ? dbg_wdata : 32'h0;

    assign cpu0_dbg_valid = sel[0] ? dbg_valid : 1'b0;
    assign cpu1_dbg_valid = sel[1] ? dbg_valid : 1'b0;
    assign cpu2_dbg_valid = sel[2] ? dbg_valid : 1'b0;
    assign cpu3_dbg_valid = sel[3] ? dbg_valid : 1'b0;

    // Inputs: selected CPU → shared uart_debug
    assign dbg_rdata = sel[0] ? cpu0_dbg_rdata : sel[1] ? cpu1_dbg_rdata :
                      sel[2] ? cpu2_dbg_rdata : cpu3_dbg_rdata;
    assign dbg_ack   = sel[0] ? cpu0_dbg_ack   : sel[1] ? cpu1_dbg_ack   :
                      sel[2] ? cpu2_dbg_ack   : cpu3_dbg_ack;

    // ================================================================
    // Bridge control
    // ================================================================
    assign cpu0_bridge_in = sel[0] ? bridge_in : 16'h0;
    assign cpu1_bridge_in = sel[1] ? bridge_in : 16'h0;
    assign cpu2_bridge_i  = sel[2] ? bridge_in[7:0] : 8'h0;
    assign cpu3_bridge_i  = sel[3] ? bridge_in[7:0] : 8'h0;

    assign bridge_o[15:8] = sel[0] ? cpu0_bridge_o[15:8] :
                            sel[1] ? cpu1_bridge_o[15:8] :
                            sel[2] ? cpu2_bridge_o :
                                   cpu3_bridge_o;
    assign bridge_o[7:0]  = sel[0] ? cpu0_bridge_o[7:0] :
                            sel[1] ? cpu1_bridge_o[7:0] : 8'h00;

    wire bidi_oe = sel[0] ? cpu0_bridge_oe : cpu1_bridge_oe;
    assign bridge_oe_hi = bridge_bidi_mode ? bidi_oe : 1'b1;
    assign bridge_oe_lo = bridge_bidi_mode ? bidi_oe : 1'b0;

    // ================================================================
    // Output mux: uart_tx
    // ================================================================
    assign uart_tx_pin = sel[0] ? cpu0_uart_tx :
                         sel[1] ? cpu1_uart_tx :
                         sel[2] ? cpu2_uart_tx :
                                 cpu3_uart_tx;

    // ================================================================
    // I2C mux: outputs from selected CPU, inputs broadcast to all
    // ================================================================
    assign scl_o  = sel[0] ? cpu0_scl_o  : sel[1] ? cpu1_scl_o  :
                    sel[2] ? cpu2_scl_o  : cpu3_scl_o;

    assign scl_oe = sel[0] ? cpu0_scl_oe : sel[1] ? cpu1_scl_oe :
                    sel[2] ? cpu2_scl_oe : cpu3_scl_oe;

    assign sda_o  = sel[0] ? cpu0_sda_o  : sel[1] ? cpu1_sda_o  :
                    sel[2] ? cpu2_sda_o  : cpu3_sda_o;

    assign sda_oe = sel[0] ? cpu0_sda_oe : sel[1] ? cpu1_sda_oe :
                    sel[2] ? cpu2_sda_oe : cpu3_sda_oe;

    // ================================================================
    // CPU0 instantiation (chip_sel=00, full bidirectional bridge)
    // ================================================================
    cpu0_tinyriscv_soc_top_pad u_cpu0 (
        .clk(cpu0_clk),
        .rst(rst),
        .uart_tx_pin(cpu0_uart_tx),
        .uart_rx_pin(uart_rx_pin),
        .bridge_in(cpu0_bridge_in),
        .bridge_o(cpu0_bridge_o),
        .bridge_oe(cpu0_bridge_oe),
        .scl_in(scl_in),
        .scl_o(cpu0_scl_o),
        .scl_oe(cpu0_scl_oe),
        .sda_in(sda_in),
        .sda_o(cpu0_sda_o),
        .sda_oe(cpu0_sda_oe),
        // shared regs
        .reg_we_o(cpu0_reg_we),
        .reg_waddr_o(cpu0_reg_waddr),
        .reg_wdata_o(cpu0_reg_wdata),
        .reg_raddr1_o(cpu0_reg_raddr1),
        .reg_raddr2_o(cpu0_reg_raddr2),
        .reg_rdata1_i(cpu0_rdata1),
        .reg_rdata2_i(cpu0_rdata2),
        // shared uart_debug bus
        .dbg_req_i(cpu0_dbg_req),
        .dbg_we_i(cpu0_dbg_we),
        .dbg_addr_i(cpu0_dbg_addr),
        .dbg_wdata_i(cpu0_dbg_wdata),
        .dbg_rdata_o(cpu0_dbg_rdata),
        .dbg_ack_o(cpu0_dbg_ack),
        // shared PWM bus
        .pwm_we_o(cpu0_pwm_we),
        .pwm_addr_o(cpu0_pwm_addr),
        .pwm_data_o(cpu0_pwm_data)
    );

    // ================================================================
    // CPU1 instantiation (chip_sel=01, 16-bit bidi bridge — 王子阳 correct)
    // ================================================================
    cpu1_tinyriscv_soc_top u_cpu1 (
        .clk(cpu1_clk),
        .rst(rst),
        .uart_tx_pin(cpu1_uart_tx),
        .uart_rx_pin(uart_rx_pin),
        .bridge_in(cpu1_bridge_in),
        .bridge_o(cpu1_bridge_o),
        .bridge_oe(cpu1_bridge_oe),
        .scl_in(scl_in),
        .scl_o(cpu1_scl_o),
        .scl_oe(cpu1_scl_oe),
        .sda_in(sda_in),
        .sda_o(cpu1_sda_o),
        .sda_oe(cpu1_sda_oe),
        // shared regs
        .reg_we_o(cpu1_reg_we),
        .reg_waddr_o(cpu1_reg_waddr),
        .reg_wdata_o(cpu1_reg_wdata),
        .reg_raddr1_o(cpu1_reg_raddr1),
        .reg_raddr2_o(cpu1_reg_raddr2),
        .reg_rdata1_i(cpu1_rdata1),
        .reg_rdata2_i(cpu1_rdata2),
        // shared uart_debug bus
        .dbg_req_i(cpu1_dbg_req),
        .dbg_we_i(cpu1_dbg_we),
        .dbg_addr_i(cpu1_dbg_addr),
        .dbg_wdata_i(cpu1_dbg_wdata),
        .dbg_rdata_o(cpu1_dbg_rdata),
        .dbg_ack_o(cpu1_dbg_ack),
        // shared PWM bus
        .pwm_we_o(cpu1_pwm_we),
        .pwm_addr_o(cpu1_pwm_addr),
        .pwm_data_o(cpu1_pwm_data)
    );

    // ================================================================
    // CPU2 instantiation (chip_sel=10, 8-in/8-out bridge)
    // ================================================================
    cpu2_tinyriscv_soc_top u_cpu2 (
        .clk(cpu2_clk),
        .rst(rst),
        .uart_tx_pin(cpu2_uart_tx),
        .uart_rx_pin(uart_rx_pin),
        .bridge_i(cpu2_bridge_i),
        .bridge_o(cpu2_bridge_o),
        .scl_in(scl_in),
        .scl_o(cpu2_scl_o),
        .scl_oe(cpu2_scl_oe),
        .sda_in(sda_in),
        .sda_o(cpu2_sda_o),
        .sda_oe(cpu2_sda_oe),
        // shared regs
        .reg_we_o(cpu2_reg_we),
        .reg_waddr_o(cpu2_reg_waddr),
        .reg_wdata_o(cpu2_reg_wdata),
        .reg_raddr1_o(cpu2_reg_raddr1),
        .reg_raddr2_o(cpu2_reg_raddr2),
        .reg_rdata1_i(cpu2_rdata1),
        .reg_rdata2_i(cpu2_rdata2),
        // shared uart_debug bus
        .dbg_req_i(cpu2_dbg_req),
        .dbg_we_i(cpu2_dbg_we),
        .dbg_addr_i(cpu2_dbg_addr),
        .dbg_wdata_i(cpu2_dbg_wdata),
        .dbg_rdata_o(cpu2_dbg_rdata),
        .dbg_ack_o(cpu2_dbg_ack),
        // shared PWM bus
        .pwm_we_o(cpu2_pwm_we),
        .pwm_addr_o(cpu2_pwm_addr),
        .pwm_data_o(cpu2_pwm_data)
    );

    // ================================================================
    // CPU3 instantiation (chip_sel=11, 8-in/8-out bridge)
    // ================================================================
    cpu3_tinyriscv_soc_top u_cpu3 (
        .clk(cpu3_clk),
        .rst(rst),
        .uart_tx_pin(cpu3_uart_tx),
        .uart_rx_pin(uart_rx_pin),
        .bridge_i(cpu3_bridge_i),
        .bridge_o(cpu3_bridge_o),
        .scl_in(scl_in),
        .scl_o(cpu3_scl_o),
        .scl_oe(cpu3_scl_oe),
        .sda_in(sda_in),
        .sda_o(cpu3_sda_o),
        .sda_oe(cpu3_sda_oe),
        // shared regs
        .reg_we_o(cpu3_reg_we),
        .reg_waddr_o(cpu3_reg_waddr),
        .reg_wdata_o(cpu3_reg_wdata),
        .reg_raddr1_o(cpu3_reg_raddr1),
        .reg_raddr2_o(cpu3_reg_raddr2),
        .reg_rdata1_i(cpu3_rdata1),
        .reg_rdata2_i(cpu3_rdata2),
        // shared uart_debug bus
        .dbg_req_i(cpu3_dbg_req),
        .dbg_we_i(cpu3_dbg_we),
        .dbg_addr_i(cpu3_dbg_addr),
        .dbg_wdata_i(cpu3_dbg_wdata),
        .dbg_valid_i(cpu3_dbg_valid),
        .dbg_rdata_o(cpu3_dbg_rdata),
        .dbg_ack_o(cpu3_dbg_ack),
        // shared PWM bus
        .pwm_we_o(cpu3_pwm_we),
        .pwm_addr_o(cpu3_pwm_addr),
        .pwm_data_o(cpu3_pwm_data)
    );

endmodule
