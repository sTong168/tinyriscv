 /*                                                                      
 Copyright 2020 Blue Liang, liangkangnan@163.com
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
 Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */


// 涓插彛妯″潡(榛樿: 115200, 8 N 1)
module cpu3_uart(

	input wire clk,
	input wire rst,

    input wire we_i,
    input wire[31:0] addr_i,
    input wire[31:0] data_i,
    input wire hex_tx_i,

    output reg[31:0] data_o,
	output wire tx_pin,
    output wire tx_ready_o,
    input wire rx_pin

    );


    // 50MHz鏃堕挓锛屾尝鐗圭巼115200bps瀵瑰簲鐨勫垎棰戠郴鏁?
    localparam BAUD_115200 = 32'h1B8;

    localparam S_IDLE       = 4'b0001;
    localparam S_START      = 4'b0010;
    localparam S_SEND_BYTE  = 4'b0100;
    localparam S_STOP       = 4'b1000;

    reg tx_data_valid;
    reg tx_data_ready;
    reg tx_hex_pending;
    reg[7:0] tx_hex_low;

    reg[3:0] state;
    reg[15:0] cycle_cnt;
    reg[3:0] bit_cnt;
    reg[7:0] tx_data;
    reg tx_reg;

    reg rx_q0;
    reg rx_q1;
    wire rx_negedge;
    reg rx_start;                      // RX浣胯兘
    reg[3:0] rx_clk_edge_cnt;          // clk鏃堕挓娌跨殑涓暟
    reg rx_clk_edge_level;             // clk娌跨數骞?
    reg rx_done;
    reg[15:0] rx_clk_cnt;
    reg[15:0] rx_div_cnt;
    reg[7:0] rx_data;
    reg rx_over;

    localparam UART_CTRL = 8'h0;
    localparam UART_STATUS = 8'h4;
    localparam UART_BAUD = 8'h8;
    localparam UART_TXDATA = 8'hc;
    localparam UART_RXDATA = 8'h10;

    // addr: 0x00
    // rw. bit[0]: tx enable, 1 = enable, 0 = disable
    // rw. bit[1]: rx enable, 1 = enable, 0 = disable
    reg[31:0] uart_ctrl;

    // addr: 0x04
    // ro. bit[0]: tx busy, 1 = busy, 0 = idle
    // rw. bit[1]: rx over, 1 = over, 0 = receiving
    // must check this bit before tx data
    reg[31:0] uart_status;

    // addr: 0x08
    // rw. clk div
    reg[31:0] uart_baud;

    // addr: 0x10
    // ro. rx data
    reg[31:0] uart_rx;

    // The UART peripheral is accepted only when the transmitter and the
    // optional second hexadecimal character are both idle. Keep this ready
    // signal independent of the bus address/data to avoid a combinational
    // loop through the interconnect and a CPU master.
    wire tx_write_ready = (uart_status[0] == 1'b0) &&
                          (state == S_IDLE) &&
                          (tx_data_valid == 1'b0) &&
                          (tx_hex_pending == 1'b0);
    assign tx_ready_o = tx_write_ready;

    assign tx_pin = tx_reg;

    function[7:0] hex_ascii;
        input[3:0] nibble;
        begin
            if (nibble < 4'd10)
                hex_ascii = 8'h30 + nibble;
            else
                hex_ascii = 8'h41 + nibble - 4'd10;
        end
    endfunction


    // 鍐欏瘎瀛樺櫒
    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            uart_ctrl <= 32'h0;
            uart_status <= 32'h0;
            uart_rx <= 32'h0;
            uart_baud <= BAUD_115200;
            tx_data_valid <= 1'b0;
            tx_hex_pending <= 1'b0;
            tx_hex_low <= 8'h30;
            tx_data <= 8'h00;
        end else begin
            tx_data_valid <= 1'b0;
            if (tx_data_ready == 1'b1) begin
                if (tx_hex_pending == 1'b1) begin
                    tx_data <= tx_hex_low;
                    tx_hex_pending <= 1'b0;
                    uart_status[0] <= 1'b1;
                    tx_data_valid <= 1'b1;
                end else begin
                    uart_status[0] <= 1'b0;
                end
            end
            if (we_i == 1'b1) begin
                case (addr_i[7:0])
                    UART_CTRL: begin
                        uart_ctrl <= data_i;
                    end
                    UART_BAUD: begin
                        uart_baud <= data_i;
                    end
                    UART_STATUS: begin
                        if (data_i[31:8] == 24'h0 && data_i[7:0] != 8'h0) begin
                            if (tx_write_ready) begin
                                tx_data <= data_i[7:0];
                                uart_status[0] <= 1'b1;
                                tx_data_valid <= 1'b1;
                            end
                        end else begin
                            uart_status[1] <= data_i[1];
                        end
                    end
                    UART_TXDATA: begin
                        if (tx_write_ready) begin
                            if (hex_tx_i == 1'b1) begin
                                tx_data <= hex_ascii(data_i[7:4]);
                                tx_hex_low <= hex_ascii(data_i[3:0]);
                                tx_hex_pending <= 1'b1;
                            end else begin
                                tx_data <= data_i[7:0];
                                tx_hex_pending <= 1'b0;
                            end
                            uart_status[0] <= 1'b1;
                            tx_data_valid <= 1'b1;
                        end
                    end
                endcase
            end
            if (uart_ctrl[1] == 1'b1) begin
                if (rx_over == 1'b1) begin
                    uart_status[1] <= 1'b1;
                    uart_rx <= {24'h0, rx_data};
                end
            end
        end
    end

    // 璇诲瘎瀛樺櫒
    always @ (*) begin
        if (rst == 1'b0) begin
            data_o = 32'h0;
        end else begin
            case (addr_i[7:0])
                UART_CTRL: begin
                    data_o = {uart_ctrl[31:2], ~uart_status[0], uart_ctrl[0]};
                end
                UART_STATUS: begin
                    data_o = uart_status;
                end
                UART_BAUD: begin
                    data_o = uart_baud;
                end
                UART_RXDATA: begin
                    data_o = uart_rx;
                end
                default: begin
                    data_o = 32'h0;
                end
            endcase
        end
    end

    // *************************** TX鍙戦?? ****************************

    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            state <= S_IDLE;
            cycle_cnt <= 16'd0;
            tx_reg <= 1'b1;
            bit_cnt <= 4'd0;
            tx_data_ready <= 1'b0;
        end else begin
            if (state == S_IDLE) begin
                tx_reg <= 1'b1;
                tx_data_ready <= 1'b0;
                if (tx_data_valid == 1'b1) begin
                    state <= S_START;
                    cycle_cnt <= 16'd0;
                    bit_cnt <= 4'd0;
                    tx_reg <= 1'b0;
                end
            end else begin
                cycle_cnt <= cycle_cnt + 16'd1;
                if (cycle_cnt == uart_baud[15:0]) begin
                    cycle_cnt <= 16'd0;
                    case (state)
                        S_START: begin
                            tx_reg <= tx_data[bit_cnt];
                            state <= S_SEND_BYTE;
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                        S_SEND_BYTE: begin
                            bit_cnt <= bit_cnt + 4'd1;
                            if (bit_cnt == 4'd8) begin
                                state <= S_STOP;
                                tx_reg <= 1'b1;
                            end else begin                
                                tx_reg <= tx_data[bit_cnt];
                            end
                        end
                        S_STOP: begin
                            tx_reg <= 1'b1;
                            state <= S_IDLE;
                            tx_data_ready <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

    // *************************** RX鎺ユ敹 ****************************

    // 涓嬮檷娌挎娴?(妫?娴嬭捣濮嬩俊鍙?)
    assign rx_negedge = rx_q1 && ~rx_q0;


    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            rx_q0 <= 1'b0;
            rx_q1 <= 1'b0;	
        end else begin
            rx_q0 <= rx_pin;
            rx_q1 <= rx_q0;
        end
    end

    // 寮?濮嬫帴鏀舵暟鎹俊鍙凤紝鎺ユ敹鏈熼棿涓?鐩存湁鏁?
    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            rx_start <= 1'b0;
        end else begin
            if (uart_ctrl[1]) begin
                if (rx_negedge) begin
                    rx_start <= 1'b1;
                end else if (rx_clk_edge_cnt == 4'd9) begin
                    rx_start <= 1'b0;
                end
            end else begin
                rx_start <= 1'b0;
            end
        end
    end

    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            rx_div_cnt <= 16'h0;
        end else begin
            // 绗竴涓椂閽熸部鍙渶娉㈢壒鐜囧垎棰戠郴鏁扮殑涓?鍗?
            if (rx_start == 1'b1 && rx_clk_edge_cnt == 4'h0) begin
                rx_div_cnt <= {1'b0, uart_baud[15:1]};
            end else begin
                rx_div_cnt <= uart_baud[15:0];
            end
        end
    end

    // 瀵规椂閽熻繘琛岃鏁?
    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            rx_clk_cnt <= 16'h0;
        end else if (rx_start == 1'b1) begin
            // 璁℃暟杈惧埌鍒嗛鍊?
            if (rx_clk_cnt == rx_div_cnt) begin
                rx_clk_cnt <= 16'h0;
            end else begin
                rx_clk_cnt <= rx_clk_cnt + 1'b1;
            end
        end else begin
            rx_clk_cnt <= 16'h0;
        end
    end

    // 姣忓綋鏃堕挓璁℃暟杈惧埌鍒嗛鍊兼椂浜х敓涓?涓笂鍗囨部鑴夊啿
    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            rx_clk_edge_cnt <= 4'h0;
            rx_clk_edge_level <= 1'b0;
        end else if (rx_start == 1'b1) begin
            // 璁℃暟杈惧埌鍒嗛鍊?
            if (rx_clk_cnt == rx_div_cnt) begin
                // 鏃堕挓娌夸釜鏁拌揪鍒版渶澶у??
                if (rx_clk_edge_cnt == 4'd9) begin
                    rx_clk_edge_cnt <= 4'h0;
                    rx_clk_edge_level <= 1'b0;
                end else begin
                    // 鏃堕挓娌夸釜鏁板姞1
                    rx_clk_edge_cnt <= rx_clk_edge_cnt + 1'b1;
                    // 浜х敓涓婂崌娌胯剦鍐?
                    rx_clk_edge_level <= 1'b1;
                end
            end else begin
                rx_clk_edge_level <= 1'b0;
            end
        end else begin
            rx_clk_edge_cnt <= 4'h0;
            rx_clk_edge_level <= 1'b0;
        end
    end

    // bit搴忓垪
    always @ (posedge clk) begin
        if (rst == 1'b0) begin
            rx_data <= 8'h0;
            rx_over <= 1'b0;
        end else begin
            if (rx_start == 1'b1) begin
                // 涓婂崌娌?
                if (rx_clk_edge_level == 1'b1) begin
                    case (rx_clk_edge_cnt)
                        // 璧峰浣?
                        1: begin

                        end
                        // 鏁版嵁浣?
                        2, 3, 4, 5, 6, 7, 8, 9: begin
                            rx_data[rx_clk_edge_cnt - 2] <= rx_q1;
                            // 鏈?鍚庝竴浣嶆帴鏀跺畬鎴愶紝缃綅鎺ユ敹瀹屾垚鏍囧織
                            if (rx_clk_edge_cnt == 4'h9) begin
                                rx_over <= 1'b1;
                            end
                        end
                    endcase
                end
            end else begin
                rx_data <= 8'h0;
                rx_over <= 1'b0;
            end
        end
    end

endmodule
