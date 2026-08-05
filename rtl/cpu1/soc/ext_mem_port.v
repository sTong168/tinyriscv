// ext_mem_port.v — external ROM/RAM port: BYPASS (32b) or EMIF-8 bridge (tape-out)
`include "../core/defines.v"

module cpu1_ext_mem_port #(
    parameter MEM_BYPASS = 1
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [31:0] s0_addr_i,
    input  wire        s0_we_i,
    input  wire [31:0] s0_wdata_i,
    output wire [31:0] s0_rdata_o,

    input  wire [31:0] s1_addr_i,
    input  wire        s1_we_i,
    input  wire [31:0] s1_wdata_i,
    output wire [31:0] s1_rdata_o,

    input  wire        m0_req_i,
    input  wire        m0_we_i,
    input  wire [31:0] m0_addr_i,

    input  wire        ifetch_req_i,
    input  wire [31:0] ifetch_addr_i,

    output wire [31:0] ext_rom_addr_o,
    output wire        ext_rom_we_o,
    output wire [31:0] ext_rom_wdata_o,
    input  wire [31:0] ext_rom_rdata_i,

    output wire [31:0] ext_ram_addr_o,
    output wire        ext_ram_we_o,
    output wire [31:0] ext_ram_wdata_o,
    input  wire [31:0] ext_ram_rdata_i,

    output wire [7:0]  bridge_o,
    input  wire [7:0]  bridge_i,

    output wire        rom_wr_ack_o,

    output wire        mem_hold_o
);

    generate
        if (MEM_BYPASS == 1) begin : gen_bypass
            assign ext_rom_addr_o  = s0_addr_i;
            assign ext_rom_we_o    = s0_we_i;
            assign ext_rom_wdata_o = s0_wdata_i;
            assign s0_rdata_o      = ext_rom_rdata_i;

            assign ext_ram_addr_o  = s1_addr_i;
            assign ext_ram_we_o    = s1_we_i;
            assign ext_ram_wdata_o = s1_wdata_i;
            assign s1_rdata_o      = ext_ram_rdata_i;

            assign mem_hold_o   = 1'b0;
            assign rom_wr_ack_o = (s0_we_i == `WriteEnable);
            assign bridge_o     = `EMIF_IDLE;
        end else begin : gen_bridge
            reg        pending;
            reg        pend_memsel, pend_we;
            reg [31:0] pend_addr, pend_wdata;
            reg [31:0] rom_rdata_r, ram_rdata_r;
            reg        pend_ifetch;
            reg        bridge_start;
            reg        rom_wr_ack_r;
            wire       if_hit, if_miss;
            wire [31:0] if_rdata;
            wire [31:0] if_refill_addr;
            reg        if_refill_done;
            wire       bridge_busy, bridge_done;
            wire [31:0] bridge_rdata;

            wire m0_s0_rd = (m0_req_i == `RIB_REQ) && (m0_addr_i[31:28] == 4'h0) && (m0_we_i == `WriteDisable);
            wire m0_s1_rd = (m0_req_i == `RIB_REQ) && (m0_addr_i[31:28] == 4'h1) && (m0_we_i == `WriteDisable);

            cpu1_ifetch_line_buf u_ifetch_buf(
                .clk(clk), .rst(rst),
                .addr_i(ifetch_addr_i),
                .req_i(ifetch_req_i),
                .rdata_o(if_rdata),
                .hit_o(if_hit),
                .miss_o(if_miss),
                .refill_addr_o(if_refill_addr),
                .refill_req_o(),
                .refill_rdata_i(bridge_rdata),
                .refill_done_i(if_refill_done)
            );

            cpu1_mem_bridge_master u_bridge(
                .clk(clk), .rst(rst),
                .start_i(bridge_start),
                .memsel_i(pend_memsel),
                .we_i(pend_we),
                .addr_i(pend_addr),
                .wdata_i(pend_wdata),
                .rdata_o(bridge_rdata),
                .done_o(bridge_done),
                .busy_o(bridge_busy),
                .bridge_o(bridge_o),
                .bridge_i(bridge_i)
            );

            assign rom_wr_ack_o = rom_wr_ack_r;

            assign s0_rdata_o = if_hit ? if_rdata : rom_rdata_r;
            assign s1_rdata_o = ram_rdata_r;

            assign ext_rom_addr_o  = 32'h0;
            assign ext_rom_we_o    = `WriteDisable;
            assign ext_rom_wdata_o = 32'h0;
            assign ext_ram_addr_o  = 32'h0;
            assign ext_ram_we_o    = `WriteDisable;
            assign ext_ram_wdata_o = 32'h0;

            assign mem_hold_o = pending | bridge_busy | (if_miss & ~if_hit);

            always @ (posedge clk) begin
                if (rst == `RstEnable) begin
                    pending         <= 1'b0;
                    bridge_start    <= 1'b0;
                    if_refill_done  <= 1'b0;
                    rom_rdata_r     <= 32'h0;
                    ram_rdata_r     <= 32'h0;
                    pend_ifetch     <= 1'b0;
                    rom_wr_ack_r    <= 1'b0;
                end else begin
                    bridge_start   <= 1'b0;
                    if_refill_done <= 1'b0;
                    rom_wr_ack_r   <= bridge_done && pend_we && (pend_memsel == `EMIF_ROM);

                    if (!pending && !bridge_busy) begin
                        if (s0_we_i == `WriteEnable) begin
                            pending     <= 1'b1;
                            pend_ifetch <= 1'b0;
                            pend_memsel <= `EMIF_ROM;
                            pend_we     <= 1'b1;
                            pend_addr   <= s0_addr_i;
                            pend_wdata  <= s0_wdata_i;
                        end else if (s1_we_i == `WriteEnable) begin
                            pending     <= 1'b1;
                            pend_ifetch <= 1'b0;
                            pend_memsel <= `EMIF_RAM;
                            pend_we     <= 1'b1;
                            pend_addr   <= s1_addr_i;
                            pend_wdata  <= s1_wdata_i;
                        end else if (if_miss) begin
                            pending     <= 1'b1;
                            pend_ifetch <= 1'b1;
                            pend_memsel <= `EMIF_ROM;
                            pend_we     <= 1'b0;
                            pend_addr   <= if_refill_addr;
                        end else if (m0_s1_rd) begin
                            pending     <= 1'b1;
                            pend_ifetch <= 1'b0;
                            pend_memsel <= `EMIF_RAM;
                            pend_we     <= 1'b0;
                            pend_addr   <= m0_addr_i;
                        end else if (m0_s0_rd) begin
                            pending     <= 1'b1;
                            pend_ifetch <= 1'b0;
                            pend_memsel <= `EMIF_ROM;
                            pend_we     <= 1'b0;
                            pend_addr   <= m0_addr_i;
                        end
                    end

                    if (pending && !bridge_busy && !bridge_start)
                        bridge_start <= 1'b1;

                    if (bridge_done) begin
                        pending <= 1'b0;
                        if (pend_memsel == `EMIF_ROM && !pend_we) begin
                            rom_rdata_r <= bridge_rdata;
                            if (pend_ifetch)
                                if_refill_done <= 1'b1;
                        end else if (pend_memsel == `EMIF_RAM && !pend_we) begin
                            ram_rdata_r <= bridge_rdata;
                        end
                        pend_ifetch <= 1'b0;
                    end
                end
            end
        end
    endgenerate

endmodule
