`include "../core/defines.v"

// Chip-side SoC. Program and data storage are external to this top level.
module cpu3_tinyriscv_soc_top(
    input wire clk,
    input wire rst,

    output wire over,
    output wire succ,

    input wire uart_debug_pin,

    output wire uart_tx_pin,
    input wire uart_rx_pin,

    input wire [7:0] bridge_i,
    output wire [7:0] bridge_o,

    output wire [3:0] pwm,

    input wire scl_in,
    output wire scl_o,
    output wire scl_oe,
    input wire sda_in,
    output wire sda_o,
    output wire sda_oe
    );

    wire[`MemAddrBus] m0_addr_i;
    wire[`MemBus] m0_data_i;
    wire[`MemBus] m0_data_o;
    wire m0_req_i;
    wire cpu_m0_req;
    wire m0_we_i;
    wire m0_done_o;

    wire[`MemAddrBus] m1_addr_i;
    wire[`MemBus] m1_data_o;
    wire m1_req_i;
    wire cpu_m1_req;
    wire m1_done_o;

    wire[`MemAddrBus] m2_addr_i;
    wire[`MemBus] m2_data_i;
    wire[`MemBus] m2_data_o;
    wire m2_req_i;
    wire m2_we_i;
    wire m2_done_o;

    wire[`MemAddrBus] m3_addr_i;
    wire[`MemBus] m3_data_i;
    wire m3_req_i;
    wire m3_we_i;
    wire m3_done_o;

    wire[`MemAddrBus] m4_addr_i;
    wire[`MemBus] m4_data_i;
    wire[`MemBus] m4_data_o;
    wire m4_req_i;
    wire m4_we_i;
    wire m4_done_o;

    wire s0_req_o;
    wire[`MemAddrBus] s0_addr_o;
    wire[`MemBus] s0_data_o;
    wire[`MemBus] s0_data_i;
    wire s0_done_i;
    wire s0_we_o;

    wire[`MemAddrBus] s2_addr_o;
    wire[`MemBus] s2_data_o;
    wire s2_we_o;

    wire s3_req_o;
    wire[`MemAddrBus] s3_addr_o;
    wire[`MemBus] s3_data_o;
    wire[`MemBus] s3_data_i;
    wire s3_we_o;
    wire s3_ready_i;
    wire[`MemAddrBus] s4_addr_o;
    wire[`MemBus] s4_data_i;
    wire rib_hold_flag_o;
    wire debug_busy_o;
    wire uart_debug_mem_valid;
    wire uart_debug_mem_we;
    wire[`MemAddrBus] uart_debug_mem_addr;
    wire[`MemBus] uart_debug_mem_wdata;
    wire uart_debug_ack;
    wire cpu_rib_hold_flag = rib_hold_flag_o | debug_busy_o;
    wire cpu_over;
    wire cpu_succ;
    wire sid_start;
    wire sid_done;
    wire rt_start;
    wire rt_done;
    wire send_if_start;
    wire send_if_done;
    wire[7:0] if_data;
    wire[7:0] i2c_temp_data;
    reg over_r;
    reg succ_r;
    localparam integer DEBUG_DEBOUNCE_CYCLES = 1_000_000;
    localparam [1:0] ROM_CLEAR_IDLE = 2'd0;
    localparam [1:0] ROM_CLEAR_REQ  = 2'd1;
    localparam [1:0] ROM_CLEAR_GAP  = 2'd2;
    localparam [1:0] ROM_CLEAR_DONE = 2'd3;
    reg debug_pin_meta;
    reg debug_pin_sync;
    reg debug_pin_state;
    reg debug_pin_state_d;
    reg[19:0] debug_pin_count;
    reg uart_debug_enable;
    reg uart_debug_mem_valid_block;
    reg[1:0] rom_clear_state;
    reg[7:0] rom_clear_word_addr;
    reg cpu_run_enable;
    reg rt_hex_pending;
    reg rt_done_d;
    reg send_if_start_d;
    reg[7:0] if_data_d;
    // Runtime RT/Temp and IF writes use hexadecimal ASCII. During a firmware
    // download, uart_debug also writes UART TXDATA; those protocol responses
    // must remain raw bytes (0x06 ACK / 0x15 NAK).
    wire uart_hex_tx = !debug_pin_state &&
                       (rt_hex_pending || rt_done || m4_req_i) &&
                       s3_req_o && s3_we_o &&
                       (s3_addr_o[7:0] == 8'h0c);
    // RIB, UART, and uart_debug retain the board reset so the debug master
    // can continue transferring data while the CPU is held in reset. The CPU
    // is released only after a complete, debounced key press/release cycle;
    // releasing the board reset alone must not start the downloaded program.
    wire cpu_rst = rst & ~debug_pin_state & cpu_run_enable;
    wire uart_debug_rom_write_pending = uart_debug_enable &&
                                        uart_debug_mem_valid &&
                                        uart_debug_mem_we &&
                                        (uart_debug_mem_addr[31:10] == 22'd0);
    wire rom_clear_start = (rom_clear_state == ROM_CLEAR_IDLE) &&
                           uart_debug_rom_write_pending;
    wire rom_clear_bus_active = (rom_clear_state == ROM_CLEAR_REQ) ||
                                (rom_clear_state == ROM_CLEAR_GAP);

    assign over = over_r;
    assign succ = succ_r;
    // Once debug is active, let the RIB finish its captured CPU transaction
    // but do not allow the reset CPU to launch another fetch during bus gaps.
    assign m0_req_i = cpu_m0_req & ~debug_pin_state;
    assign m1_req_i = cpu_m1_req & ~debug_pin_state;
    assign m2_req_i = rom_clear_bus_active ?
                      (rom_clear_state == ROM_CLEAR_REQ) :
                      (rom_clear_start ? `RIB_NREQ :
                       (uart_debug_mem_valid & ~uart_debug_mem_valid_block));
    assign m2_we_i = rom_clear_bus_active ? `WriteEnable : uart_debug_mem_we;
    assign m2_addr_i = rom_clear_bus_active ?
                       {22'd0, rom_clear_word_addr, 2'b00} :
                       uart_debug_mem_addr;
    assign m2_data_i = rom_clear_bus_active ? `ZeroWord : uart_debug_mem_wdata;
    assign uart_debug_ack = (!rom_clear_bus_active && !rom_clear_start) ?
                            m2_done_o : `RIB_NACK;

    // Defer the 1 KiB ROM clear until uart_debug presents the first actual
    // firmware write. A key-only debug cycle can therefore restart the image
    // without erasing it. During a download, hold that first write and its ACK
    // until all stale words have been cleared.
    always @ (posedge clk) begin
        if (!rst || !debug_pin_state) begin
            rom_clear_state <= ROM_CLEAR_IDLE;
            rom_clear_word_addr <= 8'd0;
        end else begin
            case (rom_clear_state)
                ROM_CLEAR_IDLE: begin
                    if (uart_debug_rom_write_pending) begin
                        rom_clear_state <= ROM_CLEAR_REQ;
                        rom_clear_word_addr <= 8'd0;
                    end
                end
                ROM_CLEAR_REQ: begin
                    if (m2_done_o) begin
                        if (rom_clear_word_addr == 8'hff) begin
                            rom_clear_state <= ROM_CLEAR_DONE;
                        end else begin
                            rom_clear_word_addr <= rom_clear_word_addr + 1'b1;
                            rom_clear_state <= ROM_CLEAR_GAP;
                        end
                    end
                end
                ROM_CLEAR_GAP: begin
                    rom_clear_state <= ROM_CLEAR_REQ;
                end
                default: begin
                    rom_clear_state <= ROM_CLEAR_DONE;
                end
            endcase
        end
    end

    // Stop the CPU as soon as debug is requested, then let any already-active
    // external-memory transfer finish before uart_debug starts issuing its
    // one-cycle UART initialization writes.
    always @ (posedge clk) begin
        if (!rst || !debug_pin_state) begin
            uart_debug_enable <= 1'b0;
        end else if (!uart_debug_enable && !rib_hold_flag_o) begin
            uart_debug_enable <= 1'b1;
        end
    end

    // The external-memory bridge completes before uart_debug advances its
    // registered address/data.  Insert one idle cycle so the old write is not
    // submitted again as the next transaction.
    always @ (posedge clk) begin
        if (!rst || !debug_pin_state) begin
            uart_debug_mem_valid_block <= 1'b0;
        end else if (uart_debug_enable &&
                     !rom_clear_bus_active && !rom_clear_start &&
                     m2_req_i && m2_done_o && m2_we_i &&
                     ((m2_addr_i[31:28] == 4'h0) ||
                      (m2_addr_i[31:28] == 4'h1))) begin
            uart_debug_mem_valid_block <= 1'b1;
        end else begin
            uart_debug_mem_valid_block <= 1'b0;
        end
    end

    // Synchronize and debounce the debug key before it controls either the
    // downloader or the CPU reset. A stable 20 ms level is required.
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            debug_pin_meta <= 1'b0;
            debug_pin_sync <= 1'b0;
            debug_pin_state <= 1'b0;
            debug_pin_state_d <= 1'b0;
            debug_pin_count <= 20'd0;
            cpu_run_enable <= 1'b0;
        end else begin
            debug_pin_meta <= uart_debug_pin;
            debug_pin_sync <= debug_pin_meta;
            debug_pin_state_d <= debug_pin_state;
            if (debug_pin_sync == debug_pin_state) begin
                debug_pin_count <= 20'd0;
            end else if (debug_pin_count == DEBUG_DEBOUNCE_CYCLES - 1) begin
                debug_pin_state <= debug_pin_sync;
                debug_pin_count <= 20'd0;
            end else begin
                debug_pin_count <= debug_pin_count + 1'b1;
            end

            // A key release starts one clean CPU run. Board reset clears this
            // permission, so pressing/releasing reset cannot run the image.
            if (debug_pin_state_d && !debug_pin_state)
                cpu_run_enable <= 1'b1;
        end
    end

    // The immutable Temp.data writes the raw rT byte once to UART TXDATA.
    // Mark that next write so UART can emit two hexadecimal ASCII digits.
    always @ (posedge clk) begin
        if (rst == `RstEnable || debug_pin_state == 1'b1) begin
            rt_hex_pending <= 1'b0;
            rt_done_d <= 1'b0;
        end else if (uart_hex_tx) begin
            rt_hex_pending <= 1'b0;
            rt_done_d <= rt_done;
        end else begin
            rt_done_d <= rt_done;
            if (rt_done && !rt_done_d)
                rt_hex_pending <= 1'b1;
        end
    end

    always @ (posedge clk) begin
        if (rst == `RstEnable || debug_pin_state == 1'b1) begin
            over_r <= 1'b1;
            succ_r <= 1'b1;
        end else begin
            over_r <= ~cpu_over;
            succ_r <= ~cpu_succ;
        end
    end

    // Keep the operand stable while the IF sender accepts its start pulse.
    always @ (posedge clk or negedge rst) begin
        if (!rst) begin
            send_if_start_d <= 1'b0;
            if_data_d <= 8'd0;
        end else begin
            send_if_start_d <= send_if_start;
            if_data_d <= if_data;
        end
    end

    cpu3_tinyriscv u_tinyriscv(
        .clk(clk),
        .rst(cpu_rst),
        .rib_ex_addr_o(m0_addr_i),
        .rib_ex_data_i(m0_data_o),
        .rib_ex_data_o(m0_data_i),
        .rib_ex_req_o(cpu_m0_req),
        .rib_ex_we_o(m0_we_i),
        .rib_ex_done_i(m0_done_o),
        .rib_pc_addr_o(m1_addr_i),
        .rib_pc_req_o(cpu_m1_req),
        .rib_pc_data_i(m1_data_o),
        .rib_pc_done_i(m1_done_o),
        .rib_hold_flag_i(cpu_rib_hold_flag),
        .sid_start_o(sid_start),
        .sid_done_i(sid_done),
         .rt_start_o(rt_start),
         .rt_done_i(rt_done),
         .i2c_temp_data_i(i2c_temp_data),
         .send_if_start_o(send_if_start),
         .send_if_done_i(send_if_done),
         .if_data_o(if_data),
         .regs_over_o(cpu_over),
         .regs_succ_o(cpu_succ)
     );

    cpu3_chip_bridge u_chip_bridge(
        .clk(clk),
        .rst(rst),
        .req_i(s0_req_o),
        .we_i(s0_we_o),
        .addr_i(s0_addr_o),
        .wdata_i(s0_data_o),
        .rdata_o(s0_data_i),
        .done_o(s0_done_i),
        .busy_o(),
        .bridge_o(bridge_o),
        .bridge_i(bridge_i)
    );

    cpu3_uart u_uart(
        .clk(clk),
        .rst(rst),
        .we_i(s3_we_o),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .hex_tx_i(uart_hex_tx),
        .tx_ready_o(s3_ready_i),
        .tx_pin(uart_tx_pin),
        .rx_pin(uart_rx_pin)
    );

    cpu3_pwm u_pwm(
        .clk(clk),
        .rst(rst),
        .we_i(s2_we_o),
        .addr_i(s2_addr_o),
        .data_i(s2_data_o),
        .pwm_o(pwm)
    );

    cpu3_i2c_master u_i2c(
        .clk(clk),
        .rst(cpu_rst),
        .we_i(1'b0),
        .addr_i(s4_addr_o),
        .data_i(`ZeroWord),
        .data_o(s4_data_i),
        .scl_in(scl_in),
        .scl_o(scl_o),
        .scl_oe(scl_oe),
        .sda_in(sda_in),
        .sda_o(sda_o),
        .sda_oe(sda_oe),
        .start_i(rt_start),
        .done_o(rt_done),
        .busy_o(),
        .temp_data_o(i2c_temp_data)
    );

    cpu3_rib u_rib(
        .clk(clk),
        .rst(rst),
        .m0_addr_i(m0_addr_i),
        .m0_data_i(m0_data_i),
        .m0_data_o(m0_data_o),
        .m0_req_i(m0_req_i),
        .m0_we_i(m0_we_i),
        .m0_done_o(m0_done_o),
        .m1_addr_i(m1_addr_i),
        .m1_data_i(`ZeroWord),
        .m1_data_o(m1_data_o),
        .m1_req_i(m1_req_i),
        .m1_we_i(`WriteDisable),
        .m1_done_o(m1_done_o),
        .m2_addr_i(m2_addr_i),
        .m2_data_i(m2_data_i),
        .m2_data_o(m2_data_o),
        .m2_req_i(m2_req_i),
        .m2_we_i(m2_we_i),
        .m2_done_o(m2_done_o),
        .m3_addr_i(m3_addr_i),
        .m3_data_i(m3_data_i),
        .m3_data_o(),
         .m3_req_i(m3_req_i),
         .m3_we_i(m3_we_i),
         .m3_done_o(m3_done_o),
         .m4_addr_i(m4_addr_i),
         .m4_data_i(m4_data_i),
         .m4_data_o(m4_data_o),
         .m4_req_i(m4_req_i),
         .m4_we_i(m4_we_i),
        .m4_done_o(m4_done_o),
         .s0_req_o(s0_req_o),
        .s0_addr_o(s0_addr_o),
        .s0_data_o(s0_data_o),
        .s0_data_i(s0_data_i),
        .s0_done_i(s0_done_i),
        .s0_we_o(s0_we_o),
        .s2_addr_o(s2_addr_o),
        .s2_data_o(s2_data_o),
        .s2_data_i(`ZeroWord),
        .s2_we_o(s2_we_o),
        .s3_req_o(s3_req_o),
        .s3_addr_o(s3_addr_o),
        .s3_data_o(s3_data_o),
        .s3_data_i(s3_data_i),
        .s3_we_o(s3_we_o),
        .s3_ready_i(s3_ready_i),
        .s4_addr_o(s4_addr_o),
        .s4_data_i(s4_data_i),
        .s4_data_o(),
        .s4_we_o(),
        .hold_flag_o(rib_hold_flag_o)
    );

    cpu3_uart_debug u_uart_debug(
        .clk(clk),
        .rst(rst),
        .debug_en_i(uart_debug_enable),
        .req_o(debug_busy_o),
        .mem_valid_o(uart_debug_mem_valid),
        .mem_we_o(uart_debug_mem_we),
        .mem_addr_o(uart_debug_mem_addr),
        .mem_wdata_o(uart_debug_mem_wdata),
        .mem_rdata_i(m2_data_o),
        .ack_i(uart_debug_ack)
    );

    cpu3_sID u_sID(
        .clk(clk),
        .rst(cpu_rst),
        .start(sid_start),
        .done(sid_done),
        .req(m3_req_i),
        .we(m3_we_i),
        .addr(m3_addr_i),
        .wdata(m3_data_i),
        .rdata(`ZeroWord),
        .ack_i(m3_done_o)
    );

    cpu3_send_if u_send_if(
        .clk       (clk),
        .rst       (cpu_rst),
        .start     (send_if_start_d),
        .ack_i     (m4_done_o),
        .byte_data (if_data_d),
        .done      (send_if_done),
        .req       (m4_req_i),
        .we        (m4_we_i),
        .addr      (m4_addr_i),
        .wdata     (m4_data_i)
    );

endmodule
