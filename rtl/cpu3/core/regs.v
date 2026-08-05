 /*                                                                      
 Copyright 2019 Blue Liang, liangkangnan@163.com
                                                                         
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

`include "defines.v"

// ͨ�üĴ���ģ��
module cpu3_regs(

    input wire clk,
    input wire rst,

    output wire over,         // �����Ƿ�����ź�
    output wire succ,         // �����Ƿ�ɹ��ź�

    // from ex
    input wire we_i,                      // д�Ĵ�����־
    input wire[`RegAddrBus] waddr_i,      // д�Ĵ�����ַ
    input wire[`RegBus] wdata_i,          // д�Ĵ�������

    // from id
    input wire[`RegAddrBus] raddr1_i,     // ���Ĵ���1��ַ

    // to id
    output reg[`RegBus] rdata1_o,         // ���Ĵ���1����

    // from id
    input wire[`RegAddrBus] raddr2_i,     // ���Ĵ���2��ַ

    // to id
    output reg[`RegBus] rdata2_o         // ���Ĵ���2����

    );

    reg[`RegBus] regs[0:`RegNum - 1];

    // д�Ĵ���
    always @ (posedge clk) begin
        if (rst == `RstDisable) begin
            // ����exģ��д����
            if ((we_i == `WriteEnable) && (waddr_i != `ZeroReg)) begin
                regs[waddr_i] <= wdata_i;
            end
        end
    end

    // ���Ĵ���1
    always @ (*) begin
        if (raddr1_i == `ZeroReg) begin
            rdata1_o = `ZeroWord;
        // �������ַ����д��ַ����������д��������ֱ�ӷ���д����
        end else if (raddr1_i == waddr_i && we_i == `WriteEnable) begin
            rdata1_o = wdata_i;
        end else begin
            rdata1_o = regs[raddr1_i];
        end
    end

    // ���Ĵ���2
    always @ (*) begin
        if (raddr2_i == `ZeroReg) begin
            rdata2_o = `ZeroWord;
        // �������ַ����д��ַ����������д��������ֱ�ӷ���д����
        end else if (raddr2_i == waddr_i && we_i == `WriteEnable) begin
            rdata2_o = wdata_i;
        end else begin
            rdata2_o = regs[raddr2_i];
        end
    end

    assign over = ~regs[26][0];
    assign succ = ~regs[27][0];

endmodule
