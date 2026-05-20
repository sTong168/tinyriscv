
`ifdef TEST_I2C

// ============================================================
// I2C Slave - full protocol (Addr+W + Data + Addr+R -> 3 bytes)
// ============================================================

reg sda_s1, sda_s2;
reg scl_s1, scl_s2;

always @(posedge clk) begin
    sda_s1 <= sda; sda_s2 <= sda_s1;
    scl_s1 <= scl; scl_s2 <= scl_s1;
end

wire sda_fall =  sda_s2 && ~sda_s1;
wire sda_rise = ~sda_s2 &&  sda_s1;
wire scl_rise = ~scl_s2 &&  scl_s1;
wire scl_fall =  scl_s2 && ~scl_s1;
wire i2c_start = sda_fall && scl_s1;
wire i2c_stop  = sda_rise && scl_s1;

localparam I2C_IDLE = 3'd0;
localparam I2C_RECV = 3'd1;
localparam I2C_SACK = 3'd2;
localparam I2C_SEND = 3'd3;
localparam I2C_MACK = 3'd4;

localparam I2C_TEST_DATA0 = `I2C_TEST_DATA0;
localparam I2C_TEST_DATA1 = `I2C_TEST_DATA1;

reg [2:0] i2c_state;
reg [7:0] i2c_sreg;
reg [3:0] i2c_bcnt;
reg [7:0] i2c_txbuf;
reg       i2c_dir;
reg       i2c_phase;
reg [1:0] i2c_rcnt;

initial begin
    i2c_txbuf = I2C_TEST_DATA0;
end

always @(posedge clk or posedge rst) begin
    if (rst == `RstEnable) begin
        i2c_state <= I2C_IDLE; i2c_bcnt <= 0; i2c_sreg <= 0;
        i2c_phase <= 0; i2c_rcnt <= 0;
        sda_oe <= 0; sda_o <= 0;
    end else begin
        if (i2c_start) begin
            if (i2c_state == I2C_SACK) i2c_rcnt <= i2c_rcnt + 1;
            i2c_state <= I2C_RECV; i2c_bcnt <= 0; i2c_sreg <= 0; sda_oe <= 0;
        end else if (i2c_stop) begin
            i2c_state <= I2C_IDLE; i2c_bcnt <= 0; i2c_rcnt <= 0; sda_oe <= 0;
        end else begin
            case (i2c_state)
                I2C_IDLE: begin sda_oe <= 0; i2c_bcnt <= 0; i2c_phase <= 0; i2c_rcnt <= 0; end
                I2C_RECV: begin
                    if (scl_rise && i2c_bcnt < 8) begin
                        i2c_sreg <= {i2c_sreg[6:0], sda_s1};
                        i2c_bcnt <= i2c_bcnt + 1;
                    end
                    if (i2c_bcnt == 8 && scl_fall) begin
                        i2c_dir <= i2c_sreg[0]; i2c_state <= I2C_SACK;
                    end
                end
                I2C_SACK: begin
                    sda_oe <= 1; sda_o <= 0;
                    if (scl_fall) begin
                        i2c_bcnt <= 0; i2c_rcnt <= i2c_rcnt + 1;
                        if (i2c_rcnt == 2'd2) begin
                            i2c_state <= I2C_SEND;
                            i2c_txbuf <= {I2C_TEST_DATA0[6:0], 1'b0};
                            sda_oe <= 1; sda_o <= I2C_TEST_DATA0[7];
                        end else begin
                            sda_oe <= 0; i2c_state <= I2C_RECV; i2c_sreg <= 0;
                        end
                    end
                end
                I2C_SEND: begin
                    if (scl_fall && i2c_bcnt < 7) begin
                        sda_oe <= 1; sda_o <= i2c_txbuf[7];
                        i2c_txbuf <= {i2c_txbuf[6:0], 1'b0};
                        i2c_bcnt <= i2c_bcnt + 1;
                    end
                    if (i2c_bcnt == 7 && scl_fall) begin
                        sda_oe <= 0; i2c_state <= I2C_MACK;
                    end
                end
                I2C_MACK: begin
                    if (scl_fall) begin
                        if (sda_s2 == 0) begin
                            i2c_state <= I2C_SEND; i2c_bcnt <= 0;
                            i2c_txbuf <= {I2C_TEST_DATA1[6:0], 1'b0};
                            sda_o <= I2C_TEST_DATA1[7]; sda_oe <= 1;
                        end else begin
                            i2c_state <= I2C_IDLE; i2c_bcnt <= 0;
                            sda_oe <= 0; sda_o <= 0;
                        end
                    end
                end
                default: begin i2c_state <= I2C_IDLE; sda_oe <= 0; end
            endcase
        end
    end
end

`elsif TEST_I2C_V2

// ============================================================
// I2C V2 Slave - receive Addr+R, send 2 data bytes
// Protocol: START + Addr+R + ACK + byte0 + MACK + byte1 + MNACK + STOP
// ============================================================

reg v2_s1, v2_s2, v2_d1, v2_d2;

always @(posedge clk) begin
    v2_s1 <= scl; v2_s2 <= v2_s1;
    v2_d1 <= sda; v2_d2 <= v2_d1;
end

wire v2_sre  = ~v2_s2 &  v2_s1;
wire v2_sfe  =  v2_s2 & ~v2_s1;
wire v2_dfe  =  v2_d2 & ~v2_d1;
wire v2_start = v2_dfe & v2_s1;

localparam V2_IDLE=0, V2_RECV=1, V2_SACK=2, V2_SEND=3, V2_MACK=4;

localparam V2_DATA0 = `V2_TEST_DATA0;
localparam V2_DATA1 = `V2_TEST_DATA1;

reg [2:0] vs;
reg [3:0] vb;
reg [7:0] vr;
reg [7:0] vt;
reg [1:0] vc;

always @(posedge clk or posedge rst) begin
    if (rst == `RstEnable) begin
        vs <= V2_IDLE; vb <= 0; vr <= 0; vc <= 0;
        sda_oe <= 0; sda_o <= 0; vt <= V2_DATA0;
    end else begin
        if (v2_start) begin
            vs <= V2_RECV; vb <= 0; vr <= 0; sda_oe <= 0;
        end

        case (vs)
            V2_IDLE: begin sda_oe <= 0; vb <= 0; vc <= 0; end

            V2_RECV: begin
                if (v2_sre && vb < 8) begin
                    vr <= {vr[6:0], v2_d1};
                    vb <= vb + 1;
                end
                if (vb == 8 && v2_sfe) vs <= V2_SACK;
            end

            V2_SACK: begin
                sda_oe <= 1; sda_o <= 0;
                if (v2_sfe) begin
                    vb <= 0; vc <= vc + 1;
                    if (vc == 2'd1) begin
                        vs <= V2_SEND;
                        vt <= {V2_DATA0[6:0], 1'b0};
                        sda_oe <= 1; sda_o <= V2_DATA0[7];
                    end else begin
                        sda_oe <= 0; vs <= V2_RECV;
                    end
                end
            end

            V2_SEND: begin
                if (v2_sfe && vb < 7) begin
                    sda_oe <= 1; sda_o <= vt[7];
                    vt <= {vt[6:0], 1'b0};
                    vb <= vb + 1;
                end
                if (vb == 7 && v2_sfe) begin
                    sda_oe <= 0; vs <= V2_MACK;
                end
            end

            V2_MACK: begin
                if (v2_sfe) begin
                    if (vc < 2'd2) begin
                        vs <= V2_SEND; vb <= 0; vc <= vc + 1;
                        vt <= {V2_DATA1[6:0], 1'b0};
                        sda_oe <= 1; sda_o <= V2_DATA1[7];
                    end else begin
                        vs <= V2_IDLE; sda_oe <= 0;
                    end
                end
            end

            default: begin vs <= V2_IDLE; sda_oe <= 0; end
        endcase
    end
end

`endif  // TEST_I2C / TEST_I2C_V2
