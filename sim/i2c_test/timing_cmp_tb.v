`timescale 1ns / 1ps

// 对比 i2c_v2 与 i2c_modified 的 SCL/SDA 时序
// 同频: v2 SCL_DIV=250 -> period=500, mod iic_div=500 -> period=500
module timing_cmp_tb;

    reg clk, rst_n, v2_rst;

    // ---- v2 ----
    wire v2_scl, v2_sda;
    reg [31:0] v2_a, v2_d; wire [31:0] v2_q; reg v2_we, v2_req;
    i2c_v2 #(.SCL_DIV(250)) u_v2 (
        .clk(clk), .rst(v2_rst), .we_i(v2_we), .addr_i(v2_a),
        .data_i(v2_d), .data_o(v2_q), .req_i(v2_req),
        .scl(v2_scl), .sda(v2_sda));

    // ---- modified ----
    wire m_scl, m_sda;
    reg [31:0] m_a, m_d; wire [31:0] m_q; wire m_rdy; reg m_we, m_req;
    i2c_mod_core u_mod (
        .clk(clk), .rst_n(rst_n), .we_i(m_we), .addr_i(m_a),
        .data_i(m_d), .data_o(m_q), .read_data_ready_o(m_rdy),
        .req_i(m_req), .scl(m_scl), .sda(m_sda));

    // pullups
    pullup(v2_scl); pullup(v2_sda);
    pullup(m_scl);  pullup(m_sda);

    always #10 clk = ~clk;  // 50MHz

    initial begin
        $dumpfile("timing_cmp.vcd");
        $dumpvars(0, timing_cmp_tb);
        clk=0; rst_n=0; v2_rst=0;
        v2_a=0; v2_d=0; v2_we=0; v2_req=0;
        m_a=0;  m_d=0;  m_we=0;  m_req=0;
        #100; rst_n=1; v2_rst=1;
        #80;

        // ---- 同时触发两个模块 ----
        // v2: 写地址 0x90, 写 0x70020000 触发
        v2_a<=32'h70010000; v2_d<=32'h90; v2_we<=1; v2_req<=1; @(posedge clk);
        v2_a<=32'h70020000; v2_d<=0;                      @(posedge clk);
        v2_we<=0; v2_req<=0; v2_a<=0; v2_d<=0;

        // mod: 写地址 0x91(R=1), 写 iic_div=500, 写 iic_en=1 触发
        m_a<=32'h70010000; m_d<=32'h91; m_we<=1; m_req<=1; @(posedge clk);
        m_a<=32'h70050000; m_d<=500;                       @(posedge clk);
        m_a<=32'h70040000; m_d<=1;                         @(posedge clk);
        m_we<=0; m_req<=0; m_a<=0; m_d<=0;

        // 等两个模块都跑完
        #2000000;

        // 关掉 mod 的循环触发
        m_a<=32'h70040000; m_d<=0; m_we<=1; m_req<=1; @(posedge clk);
        m_we<=0; m_req<=0;

        #10000;
        $display("VCD: timing_cmp.vcd");
        $finish;
    end
endmodule
