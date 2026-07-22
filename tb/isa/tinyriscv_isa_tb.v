`timescale 1 ns / 1 ps

`include "defines.v"

// Core-level testbench for the prebuilt tests/isa/generated images.
// It intentionally bypasses the resource-limited SoC ROM and peripherals.
module tinyriscv_isa_tb;

    localparam MEM_WORDS = 2048;
    localparam TIMEOUT_CYCLES = 2000000;

    reg clk;
    reg rst;
    integer cycles;
    integer done_delay;
    integer r;

    reg [`MemBus] mem [0:MEM_WORDS - 1];

    wire [`MemAddrBus] ex_addr;
    wire [`MemBus] ex_rdata;
    wire [`MemBus] ex_wdata;
    wire ex_req;
    wire ex_we;
    wire [`MemAddrBus] pc_addr;
    wire [`MemBus] pc_data;
    wire [`RegBus] jtag_reg_data;

    wire pc_in_range = (pc_addr[31:13] == 19'b0);
    wire ex_in_range = (ex_addr[31:13] == 19'b0);

    assign pc_data = pc_in_range ? mem[pc_addr[12:2]] : `INST_NOP;
    assign ex_rdata = ex_in_range ? mem[ex_addr[12:2]] : `ZeroWord;

    tinyriscv u_core(
        .clk(clk),
        .rst(rst),
        .rib_ex_addr_o(ex_addr),
        .rib_ex_data_i(ex_rdata),
        .rib_ex_data_o(ex_wdata),
        .rib_ex_req_o(ex_req),
        .rib_ex_we_o(ex_we),
        .rib_pc_addr_o(pc_addr),
        .rib_pc_data_i(pc_data),
        .jtag_reg_addr_i(`ZeroReg),
        .jtag_reg_data_i(`ZeroWord),
        .jtag_reg_we_i(`WriteDisable),
        .jtag_reg_data_o(jtag_reg_data),
        .rib_hold_flag_i(2'b00),
        .jtag_halt_flag_i(`HoldDisable),
        .jtag_reset_flag_i(1'b0),
        .int_i(`INT_NONE)
    );

    always #10 clk = ~clk;

    always @(posedge clk) begin
        if ((rst == `RstDisable) && ex_req && ex_we && ex_in_range)
            mem[ex_addr[12:2]] <= ex_wdata;
    end

    initial begin
        clk = 1'b0;
        rst = `RstEnable;
        cycles = 0;
        done_delay = 0;
        for (r = 0; r < MEM_WORDS; r = r + 1)
            mem[r] = `ZeroWord;
        $readmemh("inst.data", mem);

        #40 rst = `RstDisable;
    end

    always @(posedge clk) begin
        if (rst == `RstDisable) begin
            cycles <= cycles + 1;
            if ((u_core.u_regs.regs[26] == 32'b1) && (done_delay == 0))
                done_delay <= 1;
            else if ((done_delay > 0) && (done_delay < 8))
                done_delay <= done_delay + 1;

            if (done_delay == 7) begin
                if (u_core.u_regs.regs[27] == 32'b1) begin
                    $display("TEST_PASS");
                end else begin
                    $display("TEST_FAIL testnum=%0d", u_core.u_regs.regs[3]);
                end
                $finish;
            end

            if (cycles >= TIMEOUT_CYCLES) begin
                $display("TEST_TIMEOUT pc=0x%08x testnum=%0d", pc_addr,
                         u_core.u_regs.regs[3]);
                $finish;
            end
        end
    end

endmodule
