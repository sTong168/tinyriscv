`include "../../shared/defines.v"

// RV32I core with explicit completion handling for external accesses.
module cpu3_tinyriscv(
    input wire clk,
    input wire rst,

    output wire[`MemAddrBus] rib_ex_addr_o,
    input wire[`MemBus] rib_ex_data_i,
    output wire[`MemBus] rib_ex_data_o,
    output wire rib_ex_req_o,
    output wire rib_ex_we_o,
    input wire rib_ex_done_i,

    output wire[`MemAddrBus] rib_pc_addr_o,
    output wire rib_pc_req_o,
    input wire[`MemBus] rib_pc_data_i,
    input wire rib_pc_done_i,
    input wire rib_hold_flag_i,
    output wire sid_start_o,
    input wire sid_done_i,
    output wire rt_start_o,
    input wire rt_done_i,
    input wire[7:0] i2c_temp_data_i,
    output wire send_if_start_o,
    input wire send_if_done_i,
    output wire[7:0] if_data_o,
    // shared regs interface
    output wire              reg_we_o,
    output wire[`RegAddrBus] reg_waddr_o,
    output wire[`RegBus]     reg_wdata_o,
    output wire[`RegAddrBus] reg_raddr1_o,
    output wire[`RegAddrBus] reg_raddr2_o,
    input wire[`RegBus]     reg_rdata1_i,
    input wire[`RegBus]     reg_rdata2_i,
    input wire              reg_hold_i,
    input wire              reg_write_ack_i,
    output wire             reg_read_req_o,
    input wire              reg_read_ack_i,
    output wire             reg_read_consume_o
    );

    wire[`InstAddrBus] pc_pc_o;
    wire[`InstBus] if_inst_o;
    wire[`InstAddrBus] if_inst_addr_o;

    wire[`RegAddrBus] id_reg1_raddr_o;
    wire[`RegAddrBus] id_reg2_raddr_o;
    wire[`InstBus] id_inst_o;
    wire[`RegBus] id_reg1_rdata_o;
    wire[`RegBus] id_reg2_rdata_o;
    wire id_reg_we_o;
    wire[`RegAddrBus] id_reg_waddr_o;
    wire[`MemAddrBus] id_op1_o;
    wire[`MemAddrBus] id_op2_o;
    wire[`MemAddrBus] id_op1_jump_o;
    wire[`MemAddrBus] id_op2_jump_o;

    wire[`InstBus] ie_inst_o;
    wire ie_reg_we_o;
    wire[`RegAddrBus] ie_reg_waddr_o;
    wire[`RegBus] ie_reg1_rdata_o;
    wire[`RegBus] ie_reg2_rdata_o;
    wire[`MemAddrBus] ie_op1_o;
    wire[`MemAddrBus] ie_op2_o;
    wire[`MemAddrBus] ie_op1_jump_o;
    wire[`MemAddrBus] ie_op2_jump_o;

    wire[`MemBus] ex_mem_wdata_o;
    wire[`MemAddrBus] ex_mem_raddr_o;
    wire[`MemAddrBus] ex_mem_waddr_o;
    wire ex_mem_we_o;
    wire ex_mem_req_o;
    wire[`RegBus] ex_reg_wdata_o;
    wire ex_reg_we_o;
    wire[`RegAddrBus] ex_reg_waddr_o;
    wire ex_hold_flag_o;
    wire ex_jump_flag_o;
    wire[`InstAddrBus] ex_jump_addr_o;

    wire[`Hold_Flag_Bus] ctrl_hold_flag_o;
    wire ctrl_jump_flag_o;
    wire[`InstAddrBus] ctrl_jump_addr_o;

    reg mem_pending;
    reg pending_we;
    reg pending_load;
    reg[`MemAddrBus] pending_addr;
    reg[`MemBus] pending_wdata;
    reg[`RegAddrBus] pending_waddr;
    reg[2:0] pending_funct3;
    reg pc_fetch_pending;
    reg redirect_pending;
    reg[`InstAddrBus] redirect_addr;
    reg decode_pending;
    reg[`InstBus] decode_inst_q;
    reg[`InstAddrBus] decode_addr_q;
    reg reg_write_pending;
    reg reg_write_sample_wait;
    reg[`RegAddrBus] reg_write_waddr_q;
    reg[`RegBus] reg_write_wdata_q;
    // A local peripheral can acknowledge a request in the same cycle. Only
    // stall the pipeline while an access is still outstanding; treating every
    // RIB request as a stall would discard the instruction behind a one-cycle
    // UART write (the IF test writes UART before initializing x31).
    wire mem_hold = mem_pending ||
                    ((ex_mem_req_o == `RIB_REQ) && !rib_ex_done_i);
    wire write_capture;
    wire base_pipeline_hold = mem_hold || reg_hold_i ||
                              reg_write_pending || write_capture ||
                              reg_write_sample_wait;
    wire decode_wait = decode_pending && !reg_read_ack_i;
    wire pipeline_hold = base_pipeline_hold || decode_wait;
    wire fetch_allowed = !pipeline_hold &&
                          (ctrl_hold_flag_o < `Hold_Id) &&
                          (ex_jump_flag_o == `JumpDisable) &&
                          (rib_hold_flag_i == `HoldDisable);
    // A branch can be resolved while the sequential instruction fetch is
    // already in flight. That response belongs to the old path and must not
    // be inserted into IF/ID after the PC has been redirected.
    wire fetch_valid = rib_pc_done_i && !pipeline_hold &&
                       (ctrl_hold_flag_o < `Hold_Id) &&
                       (ctrl_jump_flag_o == `JumpDisable) &&
                       !redirect_pending;

    // Decode is split around the shared register-file read.  The fetched
    // instruction is latched once, the top level performs one shared read
    // transaction, and ID/EX consumes the same instruction exactly once when
    // the response is available.
    wire[`InstBus] decode_input_inst = decode_pending ? decode_inst_q : if_inst_o;
    wire[`InstAddrBus] decode_input_addr = decode_pending ? decode_addr_q : if_inst_addr_o;
    wire decode_commit = decode_pending && reg_read_ack_i &&
                         !base_pipeline_hold &&
                         (ctrl_hold_flag_o < `Hold_Id);
    wire decode_preserve = decode_pending && !decode_commit;

    wire bus_pending = mem_pending;
    assign rib_ex_addr_o = bus_pending ? pending_addr :
                           ((ex_mem_we_o == `WriteEnable) ?
                            ex_mem_waddr_o : ex_mem_raddr_o);
    assign rib_ex_data_o = bus_pending ? pending_wdata : ex_mem_wdata_o;
    assign rib_ex_req_o = bus_pending || (ex_mem_req_o == `RIB_REQ);
    assign rib_ex_we_o = bus_pending ? pending_we : ex_mem_we_o;
    assign rib_pc_addr_o = pc_pc_o;
    assign rib_pc_req_o = !ctrl_jump_flag_o &&
                          (pc_fetch_pending || fetch_allowed);

    function[31:0] load_result;
        input[2:0] funct3;
        input[1:0] addr_index;
        input[31:0] data;
        begin
            case (funct3)
                `INST_LB: begin
                    case (addr_index)
                        2'b00: load_result = {{24{data[7]}}, data[7:0]};
                        2'b01: load_result = {{24{data[15]}}, data[15:8]};
                        2'b10: load_result = {{24{data[23]}}, data[23:16]};
                        default: load_result = {{24{data[31]}}, data[31:24]};
                    endcase
                end
                `INST_LH: begin
                    if (addr_index == 2'b00)
                        load_result = {{16{data[15]}}, data[15:0]};
                    else
                        load_result = {{16{data[31]}}, data[31:16]};
                end
                `INST_LW: load_result = data;
                `INST_LBU: begin
                    case (addr_index)
                        2'b00: load_result = {24'h0, data[7:0]};
                        2'b01: load_result = {24'h0, data[15:8]};
                        2'b10: load_result = {24'h0, data[23:16]};
                        default: load_result = {24'h0, data[31:24]};
                    endcase
                end
                `INST_LHU: begin
                    if (addr_index == 2'b00)
                        load_result = {16'h0, data[15:0]};
                    else
                        load_result = {16'h0, data[31:16]};
                end
                default: load_result = data;
            endcase
        end
    endfunction

    wire normal_reg_we = ex_reg_we_o && !mem_pending &&
                         ((ex_mem_req_o == `RIB_NREQ) || rib_ex_done_i);
    wire pending_reg_we = mem_pending && rib_ex_done_i && pending_load;
    wire writeback_we = normal_reg_we || pending_reg_we;
    wire[`RegAddrBus] writeback_waddr = pending_reg_we ?
                                        pending_waddr : ex_reg_waddr_o;
    wire[`RegBus] writeback_wdata = pending_reg_we ?
                                    load_result(pending_funct3,
                                                pending_addr[1:0],
                                                rib_ex_data_i) :
                                    ex_reg_wdata_o;
    assign write_capture = writeback_we && !reg_write_pending &&
                           (writeback_waddr != `ZeroReg);

    // Forward the result being written back directly into the decode stage.
    // This removes the same-edge register-file read/write dependency that can
    // violate setup in a timed gate-level simulation.
    wire[`RegBus] id_reg1_rdata_fwd =
        (writeback_we && (writeback_waddr != `ZeroReg) &&
         (writeback_waddr == id_reg1_raddr_o)) ?
            writeback_wdata : reg_rdata1_i;
    wire[`RegBus] id_reg2_rdata_fwd =
        (writeback_we && (writeback_waddr != `ZeroReg) &&
         (writeback_waddr == id_reg2_raddr_o)) ?
            writeback_wdata : reg_rdata2_i;

    // Register the writeback inside CPU3 and hold it until the shared file
    // acknowledges the commit.  The top level therefore samples a bus that
    // has been stable for a full cycle instead of the same edge that changes
    // ID/EX and the combinational execute result.
    assign reg_we_o = reg_write_pending;
    assign reg_waddr_o = reg_write_waddr_q;
    assign reg_wdata_o = reg_write_wdata_q;
    assign reg_raddr1_o = id_reg1_raddr_o;
    assign reg_raddr2_o = id_reg2_raddr_o;
    assign reg_read_req_o = decode_pending && !reg_read_ack_i;
    assign reg_read_consume_o = decode_commit;
    wire gated_jump_flag = ex_jump_flag_o && !mem_pending && !ex_mem_req_o;
    wire pc_jump_flag = (gated_jump_flag &&
                         (!pc_fetch_pending || rib_pc_done_i)) ||
                        (redirect_pending && rib_pc_done_i);
    wire[`InstAddrBus] pc_jump_addr = redirect_pending ?
                                      redirect_addr : ex_jump_addr_o;

    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            mem_pending <= 1'b0;
            pending_we <= `WriteDisable;
            pending_load <= 1'b0;
            pending_addr <= `ZeroWord;
            pending_wdata <= `ZeroWord;
            pending_waddr <= `ZeroReg;
            pending_funct3 <= 3'b000;
            pc_fetch_pending <= 1'b0;
            redirect_pending <= 1'b0;
            redirect_addr <= `ZeroWord;
            decode_pending <= 1'b0;
            decode_inst_q <= `INST_NOP;
            decode_addr_q <= `ZeroWord;
            reg_write_pending <= 1'b0;
            reg_write_sample_wait <= 1'b0;
            reg_write_waddr_q <= `ZeroReg;
            reg_write_wdata_q <= `ZeroWord;
        end else begin
            if (gated_jump_flag && pc_fetch_pending && !rib_pc_done_i) begin
                redirect_pending <= 1'b1;
                redirect_addr <= ex_jump_addr_o;
            end else if (redirect_pending && rib_pc_done_i) begin
                redirect_pending <= 1'b0;
            end

            if (mem_pending) begin
                if (rib_ex_done_i) begin
                    mem_pending <= 1'b0;
                end
            end else if ((ex_mem_req_o == `RIB_REQ) && !rib_ex_done_i) begin
                mem_pending <= 1'b1;
                pending_we <= ex_mem_we_o;
                pending_load <= !ex_mem_we_o;
                pending_addr <= (ex_mem_we_o == `WriteEnable) ?
                                ex_mem_waddr_o : ex_mem_raddr_o;
                pending_wdata <= ex_mem_wdata_o;
                pending_waddr <= ex_reg_waddr_o;
                pending_funct3 <= ie_inst_o[14:12];
            end

            if (gated_jump_flag || rib_pc_done_i) begin
                pc_fetch_pending <= 1'b0;
            end else if (!pc_fetch_pending && fetch_allowed) begin
                pc_fetch_pending <= 1'b1;
            end

            if (decode_pending) begin
                if (decode_commit)
                    decode_pending <= 1'b0;
            end else if ((if_inst_o != `INST_NOP) &&
                         !base_pipeline_hold &&
                         (ctrl_hold_flag_o < `Hold_Id) &&
                         (ctrl_jump_flag_o == `JumpDisable)) begin
                decode_pending <= 1'b1;
                decode_inst_q <= if_inst_o;
                decode_addr_q <= if_inst_addr_o;
            end

            if (reg_write_pending) begin
                if (reg_write_ack_i)
                    reg_write_pending <= 1'b0;
            end else if (reg_write_sample_wait) begin
                reg_write_sample_wait <= 1'b0;
                reg_write_pending <= 1'b1;
            end else if (writeback_we && (writeback_waddr != `ZeroReg)) begin
                reg_write_sample_wait <= 1'b1;
                reg_write_waddr_q <= writeback_waddr;
                reg_write_wdata_q <= writeback_wdata;
            end

        end
    end

    cpu3_pc_reg u_pc_reg(
        .clk(clk),
        .rst(rst),
        .jump_flag_i(pc_jump_flag),
        .jump_addr_i(pc_jump_addr),
        .hold_flag_i(ctrl_hold_flag_o),
        .fetch_done_i(fetch_valid),
        .pc_o(pc_pc_o)
    );

    cpu3_ctrl u_ctrl(
        .jump_flag_i(gated_jump_flag),
        .jump_addr_i(ex_jump_addr_o),
        .hold_flag_ex_i(ex_hold_flag_o),
        .hold_flag_mem_i(pipeline_hold),
        .hold_flag_rib_i(rib_hold_flag_i),
        .hold_flag_o(ctrl_hold_flag_o),
        .jump_flag_o(ctrl_jump_flag_o),
        .jump_addr_o(ctrl_jump_addr_o)
    );

    cpu3_if_id u_if_id(
        .clk(clk),
        .rst(rst),
        .inst_i(rib_pc_data_i),
        .inst_addr_i(pc_pc_o),
        .hold_flag_i(ctrl_hold_flag_o),
        .inst_valid_i(fetch_valid),
        .preserve_i(decode_preserve),
        .inst_o(if_inst_o),
        .inst_addr_o(if_inst_addr_o)
    );

    cpu3_id u_id(
        .inst_i(decode_input_inst),
        .inst_addr_i(decode_input_addr),
        .reg1_rdata_i(id_reg1_rdata_fwd),
        .reg2_rdata_i(id_reg2_rdata_fwd),
        .reg1_raddr_o(id_reg1_raddr_o),
        .reg2_raddr_o(id_reg2_raddr_o),
        .inst_o(id_inst_o),
        .reg1_rdata_o(id_reg1_rdata_o),
        .reg2_rdata_o(id_reg2_rdata_o),
        .reg_we_o(id_reg_we_o),
        .reg_waddr_o(id_reg_waddr_o),
        .op1_o(id_op1_o),
        .op2_o(id_op2_o),
        .op1_jump_o(id_op1_jump_o),
        .op2_jump_o(id_op2_jump_o)
    );

    cpu3_id_ex u_id_ex(
        .clk(clk),
        .rst(rst),
        .inst_i(id_inst_o),
        .reg_we_i(id_reg_we_o),
        .reg_waddr_i(id_reg_waddr_o),
        .reg1_rdata_i(id_reg1_rdata_o),
        .reg2_rdata_i(id_reg2_rdata_o),
        .op1_i(id_op1_o),
        .op2_i(id_op2_o),
        .op1_jump_i(id_op1_jump_o),
        .op2_jump_i(id_op2_jump_o),
        .hold_flag_i(decode_commit ? ctrl_hold_flag_o : `Hold_Id),
        .preserve_i(write_capture || reg_write_sample_wait),
        .op1_o(ie_op1_o),
        .op2_o(ie_op2_o),
        .op1_jump_o(ie_op1_jump_o),
        .op2_jump_o(ie_op2_jump_o),
        .inst_o(ie_inst_o),
        .reg_we_o(ie_reg_we_o),
        .reg_waddr_o(ie_reg_waddr_o),
        .reg1_rdata_o(ie_reg1_rdata_o),
        .reg2_rdata_o(ie_reg2_rdata_o)
    );

    cpu3_ex u_ex(
        .inst_i(ie_inst_o),
        .reg_we_i(ie_reg_we_o),
        .reg_waddr_i(ie_reg_waddr_o),
        .reg1_rdata_i(ie_reg1_rdata_o),
        .reg2_rdata_i(ie_reg2_rdata_o),
        .op1_i(ie_op1_o),
        .op2_i(ie_op2_o),
        .op1_jump_i(ie_op1_jump_o),
        .op2_jump_i(ie_op2_jump_o),
        .mem_rdata_i(rib_ex_data_i),
        .mem_wdata_o(ex_mem_wdata_o),
        .mem_raddr_o(ex_mem_raddr_o),
        .mem_waddr_o(ex_mem_waddr_o),
        .mem_we_o(ex_mem_we_o),
        .mem_req_o(ex_mem_req_o),
        .reg_wdata_o(ex_reg_wdata_o),
        .reg_we_o(ex_reg_we_o),
        .reg_waddr_o(ex_reg_waddr_o),
        .hold_flag_o(ex_hold_flag_o),
        .jump_flag_o(ex_jump_flag_o),
        .jump_addr_o(ex_jump_addr_o),
        .sid_start_o(sid_start_o),
        .sid_done_i(sid_done_i),
         .rt_start_o(rt_start_o),
         .rt_done_i(rt_done_i),
         .i2c_temp_data_i(i2c_temp_data_i),
         .send_if_start_o(send_if_start_o),
         .send_if_done_i(send_if_done_i),
         .if_data_o(if_data_o)
     );

endmodule
