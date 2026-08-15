`include "../../shared/defines.v"

// Chip-side SoC. Program and data storage are external to this top level.
module cpu3_tinyriscv_soc_top(
    input wire clk,
    input wire rst,

    output wire uart_tx_pin,
    input wire uart_rx_pin,

    input wire [7:0] bridge_i,
    output wire [7:0] bridge_o,

    input wire scl_in,
    output wire scl_o,
    output wire scl_oe,
    input wire sda_in,
    output wire sda_o,
    output wire sda_oe,

    // shared regs interface (pass-through)
    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input wire[`RegBus]     reg_rdata1_i,
    input wire[`RegBus]     reg_rdata2_i,

    // shared uart_debug bus
    input wire              dbg_req_i,
    input wire              dbg_we_i,
    input wire[`MemAddrBus] dbg_addr_i,
    input wire[`MemBus]     dbg_wdata_i,
    input wire              dbg_valid_i,
    output wire[`MemBus]     dbg_rdata_o,
    output wire              dbg_ack_o,

    // shared PWM bus
    output wire              pwm_we_o,
    output wire[`MemAddrBus] pwm_addr_o,
    output wire[`MemBus]     pwm_data_o
    );

    // The four-CPU top keeps the original shared-register interface. CPU3's
    // request/ack protocol is terminated locally so this core can be dropped
    // into the unmodified team top level.
    wire              core_reg_we;
    wire[`RegAddrBus] core_reg_waddr;
    wire[`RegBus]     core_reg_wdata;
    wire[`RegAddrBus] core_reg_raddr1;
    wire[`RegAddrBus] core_reg_raddr2;
    wire[`RegBus]     core_reg_rdata1;
    wire[`RegBus]     core_reg_rdata2;
    wire              core_reg_hold;
    wire              core_reg_write_ack;
    wire              core_reg_read_req;
    wire              core_reg_read_ack;
    wire              core_reg_read_consume;

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
    wire debug_busy_o = dbg_req_i;  // req_o serves as busy flag for RIB hold
    wire uart_debug_mem_valid = dbg_valid_i;
    wire uart_debug_mem_we = dbg_we_i;
    wire[`MemAddrBus] uart_debug_mem_addr = dbg_addr_i;
    wire[`MemBus] uart_debug_mem_wdata = dbg_wdata_i;
    wire uart_debug_ack;
    assign dbg_rdata_o = m2_data_o;
    assign dbg_ack_o = uart_debug_ack;
    wire cpu_rib_hold_flag = rib_hold_flag_o | debug_busy_o;
    wire sid_start;
    wire sid_done;
    wire rt_start;
    wire rt_done;
    wire send_if_start;
    wire send_if_done;
    wire[7:0] if_data;
    wire[7:0] i2c_temp_data;
    localparam [1:0] ROM_CLEAR_IDLE = 2'd0;
    localparam [1:0] ROM_CLEAR_REQ  = 2'd1;
    localparam [1:0] ROM_CLEAR_GAP  = 2'd2;
    localparam [1:0] ROM_CLEAR_DONE = 2'd3;
    reg uart_debug_mem_valid_block;
    reg[1:0] rom_clear_state;
    reg[7:0] rom_clear_word_addr;
    reg rt_hex_pending;
    reg rt_done_d;
    reg send_if_start_d;
    reg[7:0] if_data_d;
    // Runtime RT/Temp and IF writes use hexadecimal ASCII.
    wire uart_hex_tx = (rt_hex_pending || rt_done || m4_req_i) &&
                       s3_req_o && s3_we_o &&
                       (s3_addr_o[7:0] == 8'h0c);
    // Hold only the CPU-side engines in reset during debug. The RIB, UART,
    // ROM-clear logic, and external-memory bridge must keep running.
    wire cpu_rst = rst & ~debug_busy_o;
    wire uart_debug_rom_write_pending = uart_debug_mem_valid &&
                                        uart_debug_mem_we &&
                                        (uart_debug_mem_addr[31:10] == 22'd0);
    wire rom_clear_start = (rom_clear_state == ROM_CLEAR_IDLE) &&
                           uart_debug_rom_write_pending;
    wire rom_clear_bus_active = (rom_clear_state == ROM_CLEAR_REQ) ||
                                (rom_clear_state == ROM_CLEAR_GAP);

    // Do not let a reset CPU launch data or instruction transactions while
    // uart_debug owns the memory path.
    assign m0_req_i = cpu_m0_req & ~debug_busy_o;
    assign m1_req_i = cpu_m1_req & ~debug_busy_o;
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
        if (!rst || !dbg_req_i) begin
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

    // The external-memory bridge completes before uart_debug advances its
    // registered address/data.  Insert one idle cycle so the old write is not
    // submitted again as the next transaction.
    always @ (posedge clk) begin
        if (!rst || !dbg_req_i) begin
            uart_debug_mem_valid_block <= 1'b0;
        end else if (!rom_clear_bus_active && !rom_clear_start &&
                     m2_req_i && m2_done_o && m2_we_i &&
                     ((m2_addr_i[31:28] == 4'h0) ||
                      (m2_addr_i[31:28] == 4'h1))) begin
            uart_debug_mem_valid_block <= 1'b1;
        end else begin
            uart_debug_mem_valid_block <= 1'b0;
        end
    end

    // The immutable Temp.data writes the raw rT byte once to UART TXDATA.
    // Mark that next write so UART can emit two hexadecimal ASCII digits.
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
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

    // PWM bus: RIB slave 2 -> shared PWM (cpu3 uses slave 2 for PWM)
    assign pwm_we_o = s2_we_o;
    assign pwm_addr_o = s2_addr_o;
    assign pwm_data_o = s2_data_o;

    cpu3_shared_regs_adapter u_shared_regs_adapter(
        .clk(clk),
        .rst(rst),
        .core_we_i(core_reg_we),
        .core_waddr_i(core_reg_waddr),
        .core_wdata_i(core_reg_wdata),
        .core_raddr1_i(core_reg_raddr1),
        .core_raddr2_i(core_reg_raddr2),
        .core_rdata1_o(core_reg_rdata1),
        .core_rdata2_o(core_reg_rdata2),
        .core_hold_o(core_reg_hold),
        .core_write_ack_o(core_reg_write_ack),
        .core_read_req_i(core_reg_read_req),
        .core_read_ack_o(core_reg_read_ack),
        .core_read_consume_i(core_reg_read_consume),
        .reg_we_o(reg_we_o),
        .reg_waddr_o(reg_waddr_o),
        .reg_wdata_o(reg_wdata_o),
        .reg_raddr1_o(reg_raddr1_o),
        .reg_raddr2_o(reg_raddr2_o),
        .reg_rdata1_i(reg_rdata1_i),
        .reg_rdata2_i(reg_rdata2_i)
    );

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
         .reg_we_o(core_reg_we),
         .reg_waddr_o(core_reg_waddr),
         .reg_wdata_o(core_reg_wdata),
         .reg_raddr1_o(core_reg_raddr1),
         .reg_raddr2_o(core_reg_raddr2),
         .reg_rdata1_i(core_reg_rdata1),
         .reg_rdata2_i(core_reg_rdata2),
         .reg_hold_i(core_reg_hold),
         .reg_write_ack_i(core_reg_write_ack),
         .reg_read_req_o(core_reg_read_req),
         .reg_read_ack_i(core_reg_read_ack),
         .reg_read_consume_o(core_reg_read_consume)
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

// Fixed-latency adapter between CPU3's transactional register-file interface
// and the original combinational-read/synchronous-write shared register file.
module cpu3_shared_regs_adapter(
    input wire clk,
    input wire rst,

    input wire              core_we_i,
    input wire[`RegAddrBus] core_waddr_i,
    input wire[`RegBus]     core_wdata_i,
    input wire[`RegAddrBus] core_raddr1_i,
    input wire[`RegAddrBus] core_raddr2_i,
    output wire[`RegBus]    core_rdata1_o,
    output wire[`RegBus]    core_rdata2_o,
    output wire             core_hold_o,
    output wire             core_write_ack_o,
    input wire              core_read_req_i,
    output wire             core_read_ack_o,
    input wire              core_read_consume_i,

    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input wire[`RegBus]      reg_rdata1_i,
    input wire[`RegBus]      reg_rdata2_i
    );

    reg write_pending;
    reg read_pending;
    reg read_ack_q;
    reg[`RegAddrBus] read_addr1_q;
    reg[`RegAddrBus] read_addr2_q;
    reg[`RegBus] read_data1_q;
    reg[`RegBus] read_data2_q;

    wire write_req = core_we_i && (core_waddr_i != `ZeroReg);
    assign core_hold_o = write_req && !write_pending;
    assign core_write_ack_o = write_pending;
    assign core_read_ack_o = read_ack_q;
    assign core_rdata1_o = read_ack_q ? read_data1_q : reg_rdata1_i;
    assign core_rdata2_o = read_ack_q ? read_data2_q : reg_rdata2_i;

    // Match the proven top-level handshake cycle for cycle: commit once on
    // the first request cycle, then hold ACK until the core drops the request.
    assign reg_we_o = write_req && !write_pending;
    assign reg_waddr_o = core_waddr_i;
    assign reg_wdata_o = core_wdata_i;
    assign reg_raddr1_o = (read_pending || read_ack_q) ?
                          read_addr1_q : core_raddr1_i;
    assign reg_raddr2_o = (read_pending || read_ack_q) ?
                          read_addr2_q : core_raddr2_i;

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            write_pending <= 1'b0;
        end else if (write_pending) begin
            if (!write_req)
                write_pending <= 1'b0;
        end else if (write_req) begin
            write_pending <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            read_pending <= 1'b0;
            read_ack_q <= 1'b0;
            read_addr1_q <= `ZeroReg;
            read_addr2_q <= `ZeroReg;
            read_data1_q <= `ZeroWord;
            read_data2_q <= `ZeroWord;
        end else if (read_ack_q) begin
            if (core_read_consume_i)
                read_ack_q <= 1'b0;
        end else if (read_pending) begin
            read_data1_q <= reg_rdata1_i;
            read_data2_q <= reg_rdata2_i;
            read_pending <= 1'b0;
            read_ack_q <= 1'b1;
        end else if (core_read_req_i) begin
            read_pending <= 1'b1;
            read_addr1_q <= core_raddr1_i;
            read_addr2_q <= core_raddr2_i;
        end
    end

endmodule
