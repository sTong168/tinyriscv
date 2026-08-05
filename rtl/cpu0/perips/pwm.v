`include "../core/defines.v"


// PWM模块
// A0~A3 (0x600x0000): period in clock cycles
// B0~B3 (0x601x0000): high time in clock cycles
// C     (0x60040000): [3:0] channel enable
// pwm_o[3:0]: 4 PWM output pins
module pwm(

    input  wire        clk   ,
    input  wire        rst   ,

    input  wire        we_i  ,
    input  wire [31:0] addr_i,
    input  wire [31:0] data_i,

    // input wire req_i,
    // output wire ack_o,

    output reg  [3:0] pwm_o

    );

    // A registers (period)
    reg  [31:0] period [0:3];
    // B registers (high time)
    reg  [31:0] high [0:3]  ;
    // C register (enable)
    reg  [31:0] enable      ;

    wire  [3:0] channel     ;
    wire        is_a        ;
    wire        is_c        ;

    assign channel = addr_i[19:16]                           ;
    assign is_a    = (addr_i[20] == 1'b0) & (channel < 4'h4) ;
    assign is_b    = (addr_i[20] == 1'b1) & (channel < 4'h4) ;
    assign is_c    = (addr_i[20] == 1'b0) & (channel == 4'h4);
    
    // write registers
    integer i;
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            for (i = 0; i < 4; i = i + 1) begin
                period[i]       <= `ZeroWord;
                high[i]         <= `ZeroWord;
            end
            enable          <= `ZeroWord;
        end else begin
            if (we_i == `WriteEnable) begin
                if (is_a) begin
                    period[channel] <= data_i;
                end else if (is_b) begin
                    high[channel]   <= data_i;
                end else if (is_c) begin
                    enable          <= data_i;
                end
            end
        end
    end

    // PWM counter and output
    integer        j        ;
    reg     [31:0] cnt [0:3];
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            for (j = 0; j < 4; j = j + 1) begin
                cnt[j]   <= `ZeroWord;
            end
            pwm_o    <= 4'b0;
        end else begin
            for (j = 0; j < 4; j = j + 1) begin
                if (enable[j] == 1'b0) begin
                    // channel disabled
                    pwm_o[j] <= 1'b0;
                end else if (period[j] == `ZeroWord) begin
                    // period is 0, output 0
                    pwm_o[j] <= 1'b0;
                end else begin
                    if (cnt[j] >= period[j] - 1) begin
                        cnt[j]   <= `ZeroWord;
                    end else begin
                        cnt[j]   <= cnt[j] + 1'b1;
                    end
                    pwm_o[j] <= (cnt[j] < high[j]);
                end
            end
        end
    end

endmodule
