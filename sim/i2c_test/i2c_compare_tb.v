`timescale 1ns / 1ps

// ============================================================
// I2C 三方对比: i2c.v / i2c_modified.v / i2c_v2.v
// 同频运行, 对比 SCL/SDA 波形
// ============================================================
module i2c_compare_tb;

    reg clk, rst_n;
    reg our_rst, v2_rst;

    // ======================== Ours ========================
    wire our_scl, our_sda;
    reg [31:0] our_a, our_wd; wire [31:0] our_rd; reg our_we, our_req;
    i2c #(.SCL_DIV(50)) u_ours (
        .clk(clk), .rst(our_rst), .we_i(our_we), .addr_i(our_a),
        .data_i(our_wd), .data_o(our_rd), .req_i(our_req),
        .scl(our_scl), .sda(our_sda));

    // ======================== Modified ========================
    wire mod_scl, mod_sda;
    reg [31:0] mod_a, mod_wd; wire [31:0] mod_rd; wire mod_rdy; reg mod_we, mod_req;
    i2c_mod_core u_mod (
        .clk(clk), .rst_n(rst_n), .we_i(mod_we), .addr_i(mod_a),
        .data_i(mod_wd), .data_o(mod_rd), .read_data_ready_o(mod_rdy),
        .req_i(mod_req), .scl(mod_scl), .sda(mod_sda));

    // ======================== V2 ========================
    wire v2_scl, v2_sda;
    reg [31:0] v2_a, v2_wd; wire [31:0] v2_rd; reg v2_we, v2_req;
    i2c_v2 #(.SCL_DIV(50)) u_v2 (
        .clk(clk), .rst(v2_rst), .we_i(v2_we), .addr_i(v2_a),
        .data_i(v2_wd), .data_o(v2_rd), .req_i(v2_req),
        .scl(v2_scl), .sda(v2_sda));

    // ============================================================
    // 通用从设备 (接收1或3字节后发数据)
    // addr=0x48, 发温度25°C = 0x1900
    // ============================================================
    localparam IDL=0, RCV=1, SACK=2, SACK2=3, SEND=4, MACK=5;
    localparam TH=8'h19, TL=8'h00;

    // ======================== Ours slave (3 bytes -> send) ========================
    pullup(our_scl); pullup(our_sda);
    reg [2:0] os_st; reg [3:0] os_bc; reg [7:0] os_sr;
    reg os_dv, os_vl; reg [2:0] os_rc;
    reg s1,s2, d1,d2;
    wire sre=~s2&s1, sfe=s2&~s1, dfe=d2&~d1, sta=dfe&s1;
    assign our_sda = os_dv ? os_vl : 1'bz;
    always @(posedge clk) begin s1<=our_scl; s2<=s1; d1<=our_sda; d2<=d1; end
    always @(posedge clk) begin
        if(!rst_n) begin os_st<=0;os_bc<=0;os_sr<=0;os_dv<=0;os_vl<=0;os_rc<=0; end
        else begin
            if(sta) begin os_st<=RCV; os_bc<=0; os_sr<=0; os_dv<=0; end
            case(os_st)
                IDL: begin os_dv<=0; os_bc<=0; os_rc<=0; end
                RCV: begin
                    if(sre && os_bc<8) begin os_sr<={os_sr[6:0],d1}; os_bc<=os_bc+1; end
                    if(os_bc==8 && sfe) os_st<=SACK;
                end
                SACK: begin os_dv<=1; os_vl<=0; if(sre) begin os_rc<=os_rc+1; os_st<=SACK2; end end
                SACK2: begin
                    os_dv<=1; os_vl<=0;
                    if(sfe) begin os_bc<=0;
                        if(os_rc==3'd3) begin os_st<=SEND; os_sr<=TH; os_dv<=1; os_vl<=TH[7]; end
                        else begin os_dv<=0; os_st<=RCV; os_sr<=0; end
                    end
                end
                SEND: begin
                    if(sfe && os_bc<7) begin os_vl<=os_sr[7]; os_sr<={os_sr[6:0],1'b0}; os_bc<=os_bc+1; end
                    if(os_bc==7 && sfe) begin os_dv<=0; os_st<=MACK; end
                end
                MACK: begin if(sfe) begin os_st<=SEND; os_bc<=0; os_sr<=TL; os_dv<=1; os_vl<=TL[7]; end end
            endcase
        end
    end

    // ======================== Modified slave (1 byte -> send) ========================
    pullup(mod_scl); pullup(mod_sda);
    reg [2:0] ms_st; reg [3:0] ms_bc; reg [7:0] ms_sr;
    reg ms_dv, ms_vl; reg [2:0] ms_rc;
    reg ms1,ms2, md1,md2;
    wire msre=~ms2&ms1, msfe=ms2&~ms1, mdfe=md2&~md1, msta=mdfe&ms1;
    assign mod_sda = ms_dv ? ms_vl : 1'bz;
    always @(posedge clk) begin ms1<=mod_scl; ms2<=ms1; md1<=mod_sda; md2<=md1; end
    always @(posedge clk) begin
        if(!rst_n) begin ms_st<=0;ms_bc<=0;ms_sr<=0;ms_dv<=0;ms_vl<=0;ms_rc<=0; end
        else begin
            if(msta) begin ms_st<=RCV; ms_bc<=0; ms_sr<=0; ms_dv<=0; end
            case(ms_st)
                IDL: begin ms_dv<=0; ms_bc<=0; ms_rc<=0; end
                RCV: begin
                    if(msre && ms_bc<8) begin ms_sr<={ms_sr[6:0],md1}; ms_bc<=ms_bc+1; end
                    if(ms_bc==8 && msfe) ms_st<=SACK;
                end
                SACK: begin ms_dv<=1; ms_vl<=0; if(msre) begin ms_rc<=ms_rc+1; ms_st<=SACK2; end end
                SACK2: begin
                    ms_dv<=1; ms_vl<=0;
                    if(msfe) begin ms_bc<=0;
                        if(ms_rc==3'd1) begin ms_st<=SEND; ms_sr<=TH; ms_dv<=1; ms_vl<=TH[7]; end
                        else begin ms_dv<=0; ms_st<=RCV; ms_sr<=0; end
                    end
                end
                SEND: begin
                    if(msfe && ms_bc<7) begin ms_vl<=ms_sr[7]; ms_sr<={ms_sr[6:0],1'b0}; ms_bc<=ms_bc+1; end
                    if(ms_bc==7 && msfe) begin ms_dv<=0; ms_st<=MACK; end
                end
                MACK: begin if(msfe) begin ms_st<=SEND; ms_bc<=0; ms_sr<=TL; ms_dv<=1; ms_vl<=TL[7]; end end
            endcase
        end
    end

    // ======================== V2 slave (1 byte -> send, same as mod) ========================
    pullup(v2_scl); pullup(v2_sda);
    reg [2:0] vs_st; reg [3:0] vs_bc; reg [7:0] vs_sr;
    reg vs_dv, vs_vl; reg [2:0] vs_rc;
    reg vs1,vs2, vd1,vd2;
    wire vsre=~vs2&vs1, vsfe=vs2&~vs1, vdfe=vd2&~vd1, vsta=vdfe&vs1;
    assign v2_sda = vs_dv ? vs_vl : 1'bz;
    always @(posedge clk) begin vs1<=v2_scl; vs2<=vs1; vd1<=v2_sda; vd2<=vd1; end
    always @(posedge clk) begin
        if(!rst_n) begin vs_st<=0;vs_bc<=0;vs_sr<=0;vs_dv<=0;vs_vl<=0;vs_rc<=0; end
        else begin
            if(vsta) begin vs_st<=RCV; vs_bc<=0; vs_sr<=0; vs_dv<=0; end
            case(vs_st)
                IDL: begin vs_dv<=0; vs_bc<=0; vs_rc<=0; end
                RCV: begin
                    if(vsre && vs_bc<8) begin vs_sr<={vs_sr[6:0],vd1}; vs_bc<=vs_bc+1; end
                    if(vs_bc==8 && vsfe) vs_st<=SACK;
                end
                SACK: begin vs_dv<=1; vs_vl<=0; if(vsre) begin vs_rc<=vs_rc+1; vs_st<=SACK2; end end
                SACK2: begin
                    vs_dv<=1; vs_vl<=0;
                    if(vsfe) begin vs_bc<=0;
                        if(vs_rc==3'd1) begin vs_st<=SEND; vs_sr<=TH; vs_dv<=1; vs_vl<=TH[7]; end
                        else begin vs_dv<=0; vs_st<=RCV; vs_sr<=0; end
                    end
                end
                SEND: begin
                    if(vsfe && vs_bc<7) begin vs_vl<=vs_sr[7]; vs_sr<={vs_sr[6:0],1'b0}; vs_bc<=vs_bc+1; end
                    if(vs_bc==7 && vsfe) begin vs_dv<=0; vs_st<=MACK; end
                end
                MACK: begin if(vsfe) begin vs_st<=SEND; vs_bc<=0; vs_sr<=TL; vs_dv<=1; vs_vl<=TL[7]; end end
            endcase
        end
    end

    // ======================== Clock ========================
    always #10 clk = ~clk;

    // ======================== Tests ========================
    reg [31:0] res;

    initial begin
        $dumpfile("i2c_compare.vcd");
        $dumpvars(0, i2c_compare_tb);
        clk=0; rst_n=0; our_rst=0; v2_rst=0;
        our_a=0; our_wd=0; our_we=0; our_req=0;
        mod_a=0; mod_wd=0; mod_we=0; mod_req=0;
        v2_a=0; v2_wd=0; v2_we=0; v2_req=0;
        #100; rst_n=1; our_rst=1; v2_rst=1;
        #80;

        // ==== Ours ====
        $display("[%0t] === Ours (Addr+W+Data+RepeatedSTART+Addr+R) ===",$time);
        do_write_ours(32'h70010000, 32'h90);
        do_write_ours(32'h70020000, 32'h00);
        poll_ours(res);
        $display("  data[15:0]=0x%04X  [14:7]=0x%02X", res[15:0], res[14:7]);

        // ==== Modified ====
        $display("[%0t] === Modified (START+Addr+R+Read) ===",$time);
        do_write_mod(32'h70010000, 32'h91);
        do_write_mod(32'h70050000, 32'h64);
        do_write_mod(32'h70040000, 32'h01);
        @(posedge clk); mod_a <= 32'h70030000;
        repeat(100) @(posedge clk);
        wait(mod_rdy);
        $display("  raw=0x%08X", mod_rd);
        do_write_mod(32'h70040000, 32'h00);

        // ==== V2 ====
        $display("[%0t] === V2 (START+Addr+R+Read, our iface) ===",$time);
        do_write_v2(32'h70010000, 32'h90);
        do_write_v2(32'h70020000, 32'h00);
        poll_v2(res);
        $display("  data[15:0]=0x%04X  [14:7]=0x%02X", res[15:0], res[14:7]);

        // ==== Ours 2nd ====
        $display("[%0t] === Ours 2nd ===",$time);
        do_write_ours(32'h70010000, 32'h90);
        do_write_ours(32'h70020000, 32'h00);
        poll_ours(res);
        $display("  data[15:0]=0x%04X", res[15:0]);

        // ==== V2 2nd ====
        $display("[%0t] === V2 2nd ===",$time);
        do_write_v2(32'h70010000, 32'h90);
        do_write_v2(32'h70020000, 32'h00);
        poll_v2(res);
        $display("  data[15:0]=0x%04X", res[15:0]);

        #200;
        $display("\n==============================================");
        $display("  Waveform: i2c_compare.vcd");
        $display("  Signals:  our_scl/sda  mod_scl/sda  v2_scl/sda");
        $display("==============================================");
        #100; $finish;
    end

    task do_write_ours(input [31:0] addr, input [31:0] dat);
        begin @(posedge clk); our_a<=addr; our_wd<=dat; our_we<=1; our_req<=1;
        @(posedge clk); our_a<=0; our_wd<=0; our_we<=0; our_req<=0;
        @(posedge clk); end
    endtask
    task do_write_mod(input [31:0] addr, input [31:0] dat);
        begin @(posedge clk); mod_a<=addr; mod_wd<=dat; mod_we<=1; mod_req<=1;
        @(posedge clk); mod_a<=0; mod_wd<=0; mod_we<=0; mod_req<=0;
        @(posedge clk); end
    endtask
    task do_write_v2(input [31:0] addr, input [31:0] dat);
        begin @(posedge clk); v2_a<=addr; v2_wd<=dat; v2_we<=1; v2_req<=1;
        @(posedge clk); v2_a<=0; v2_wd<=0; v2_we<=0; v2_req<=0;
        @(posedge clk); end
    endtask

    task poll_ours(output [31:0] r);
        begin repeat(100) @(posedge clk);
        forever begin
            @(posedge clk); our_a<=32'h70030000; our_we<=0; our_req<=1;
            @(posedge clk); r=our_rd; our_a<=0; our_req<=0;
            if(r[31:30]==2'b10) disable poll_ours;
            @(posedge clk);
        end end
    endtask

    task poll_v2(output [31:0] r);
        begin repeat(100) @(posedge clk);
        forever begin
            @(posedge clk); v2_a<=32'h70030000; v2_we<=0; v2_req<=1;
            @(posedge clk); r=v2_rd; v2_a<=0; v2_req<=0;
            if(r[31:30]==2'b10) disable poll_v2;
            @(posedge clk);
        end end
    endtask

endmodule
