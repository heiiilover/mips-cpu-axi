`timescale 1ns / 1ps
`include "mips_defs.vh"

// In-order static five-stage MIPS core: IF, ID, EX, MEM and WB.
// The external memories use the one-cycle synchronous SRAM convention from
// func_test_v0.01.  All architectural state changes occur at WB, while MEM is
// the single precise-exception arbitration point.
module pipeline_core(
    input  wire        clk,
    input  wire        resetn,
    input  wire [5:0]  ext_int,
    input  wire        external_hold,

    output wire        inst_en,
    output wire [31:0] inst_vaddr,
    input  wire [31:0] inst_rdata,

    output wire        data_en,
    output wire [3:0]  data_wen,
    output wire [31:0] data_vaddr,
    output wire [31:0] data_wdata,
    input  wire [31:0] data_rdata,

    output reg  [31:0] debug_wb_pc,
    output reg  [3:0]  debug_wb_rf_wen,
    output reg  [4:0]  debug_wb_rf_wnum,
    output reg  [31:0] debug_wb_rf_wdata
);
    // ------------------------------------------------------------------
    // IF response tracking and IF/ID register
    // ------------------------------------------------------------------
    reg [31:0] fetch_pc;
    reg [31:0] request_pc_d;
    reg        request_valid_d;

    reg        if_id_valid;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;
    reg        if_id_delay_slot;
    reg [5:0]  if_id_exc;
    reg [31:0] if_id_badaddr;

    assign inst_vaddr = fetch_pc;

    // ------------------------------------------------------------------
    // Decode
    // ------------------------------------------------------------------
    wire [4:0] id_rs;
    wire [4:0] id_rt;
    wire id_uses_rs;
    wire id_uses_rt;
    wire [5:0] id_alu_op;
    wire id_alu_src_imm;
    wire id_shift_variable;
    wire [31:0] id_immediate;
    wire [2:0] id_result_sel;
    wire id_gpr_we;
    wire [4:0] id_gpr_dst;
    wire [3:0] id_mem_op;
    wire [3:0] id_branch_op;
    wire id_link;
    wire [3:0] id_hilo_op;
    wire id_cp0_read;
    wire id_cp0_write;
    wire [4:0] id_cp0_addr;
    wire id_eret;
    wire id_trap_overflow;
    wire [5:0] id_decode_exc;

    decode_unit u_decode(
        .instr(if_id_instr),
        .rs(id_rs), .rt(id_rt),
        .uses_rs(id_uses_rs), .uses_rt(id_uses_rt),
        .alu_op(id_alu_op), .alu_src_imm(id_alu_src_imm),
        .shift_variable(id_shift_variable), .immediate(id_immediate),
        .result_sel(id_result_sel), .gpr_we(id_gpr_we), .gpr_dst(id_gpr_dst),
        .mem_op(id_mem_op), .branch_op(id_branch_op), .link(id_link),
        .hilo_op(id_hilo_op), .cp0_read(id_cp0_read),
        .cp0_write(id_cp0_write), .cp0_addr(id_cp0_addr),
        .eret(id_eret), .trap_overflow(id_trap_overflow),
        .decode_exc(id_decode_exc)
    );

    // ------------------------------------------------------------------
    // ID/EX register
    // ------------------------------------------------------------------
    reg        id_ex_valid;
    reg [31:0] id_ex_pc;
    reg        id_ex_delay_slot;
    reg [31:0] id_ex_rs_value;
    reg [31:0] id_ex_rt_value;
    reg [31:0] id_ex_immediate;
    reg [4:0]  id_ex_shamt;
    reg [5:0]  id_ex_alu_op;
    reg        id_ex_alu_src_imm;
    reg        id_ex_shift_variable;
    reg [2:0]  id_ex_result_sel;
    reg        id_ex_gpr_we;
    reg [4:0]  id_ex_gpr_dst;
    reg [3:0]  id_ex_mem_op;
    reg [3:0]  id_ex_hilo_op;
    reg [31:0] id_ex_hi_value;
    reg [31:0] id_ex_lo_value;
    reg        id_ex_cp0_write;
    reg [4:0]  id_ex_cp0_addr;
    reg [31:0] id_ex_cp0_value;
    reg        id_ex_eret;
    reg        id_ex_trap_overflow;
    reg [5:0]  id_ex_exc;
    reg [31:0] id_ex_badaddr;

    // ------------------------------------------------------------------
    // EX/MEM register
    // ------------------------------------------------------------------
    reg        ex_mem_valid;
    reg [31:0] ex_mem_pc;
    reg        ex_mem_delay_slot;
    reg [31:0] ex_mem_result;
    reg        ex_mem_gpr_we;
    reg [4:0]  ex_mem_gpr_dst;
    reg [3:0]  ex_mem_mem_op;
    reg [31:0] ex_mem_addr;
    reg        ex_mem_hilo_we;
    reg [31:0] ex_mem_hilo_hi;
    reg [31:0] ex_mem_hilo_lo;
    reg        ex_mem_cp0_write;
    reg [4:0]  ex_mem_cp0_addr;
    reg [31:0] ex_mem_cp0_wdata;
    reg        ex_mem_eret;
    reg [5:0]  ex_mem_exc;
    reg [31:0] ex_mem_badaddr;

    // ------------------------------------------------------------------
    // MEM/WB register and architectural HI/LO
    // ------------------------------------------------------------------
    reg        mem_wb_valid;
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_result;
    reg        mem_wb_gpr_we;
    reg [4:0]  mem_wb_gpr_dst;
    reg        mem_wb_hilo_we;
    reg [31:0] mem_wb_hilo_hi;
    reg [31:0] mem_wb_hilo_lo;
    reg        mem_wb_cp0_write;
    reg [4:0]  mem_wb_cp0_addr;
    reg [31:0] mem_wb_cp0_wdata;

    reg [31:0] hi_arch;
    reg [31:0] lo_arch;
    wire pipeline_hold;

    // ------------------------------------------------------------------
    // Writeback and register-file reads
    // ------------------------------------------------------------------
    wire wb_gpr_commit = !pipeline_hold && mem_wb_valid && mem_wb_gpr_we &&
                         (mem_wb_gpr_dst != 5'd0);
    wire wb_hilo_commit = !pipeline_hold && mem_wb_valid && mem_wb_hilo_we;
    wire wb_cp0_commit = !pipeline_hold && mem_wb_valid && mem_wb_cp0_write;

    wire [31:0] rf_rs_data;
    wire [31:0] rf_rt_data;
    regfile u_regfile(
        .clk(clk), .resetn(resetn),
        .we(wb_gpr_commit), .waddr(mem_wb_gpr_dst), .wdata(mem_wb_result),
        .raddr1(id_rs), .raddr2(id_rt),
        .rdata1(rf_rs_data), .rdata2(rf_rt_data)
    );

    // ------------------------------------------------------------------
    // CP0
    // ------------------------------------------------------------------
    wire [31:0] cp0_read_data;
    wire cp0_interrupt_pending;
    wire [31:0] cp0_epc;
    wire [31:0] cp0_status;
    wire [31:0] cp0_cause;
    wire mem_sync_exception = ex_mem_valid && (ex_mem_exc != `EXC_NONE);
    wire mem_interrupt = ex_mem_valid && (ex_mem_exc == `EXC_NONE) &&
                         cp0_interrupt_pending && !ex_mem_eret;
    wire mem_exception = mem_sync_exception || mem_interrupt;
    wire [5:0] mem_exception_code = mem_sync_exception ? ex_mem_exc : `EXC_INT;
    wire mem_eret = ex_mem_valid && ex_mem_eret && !mem_exception;

    cp0_regs u_cp0(
        .clk(clk), .resetn(resetn), .ext_int(ext_int),
        .read_addr(id_cp0_addr), .read_data(cp0_read_data),
        .wb_we(wb_cp0_commit), .wb_addr(mem_wb_cp0_addr),
        .wb_data(mem_wb_cp0_wdata),
        .exception_valid(!pipeline_hold && mem_exception),
        .exception_code(mem_exception_code), .exception_pc(ex_mem_pc),
        .exception_delay_slot(ex_mem_delay_slot),
        .exception_badaddr(ex_mem_badaddr),
        .eret_commit(!pipeline_hold && mem_eret),
        .interrupt_pending(cp0_interrupt_pending), .epc_value(cp0_epc),
        .status_value(cp0_status), .cause_value(cp0_cause)
    );

    // ------------------------------------------------------------------
    // Execute and memory formatting
    // ------------------------------------------------------------------
    wire [31:0] ex_result;
    wire [31:0] ex_effective_addr;
    wire ex_overflow;
    wire ex_hilo_we;
    wire [31:0] ex_hilo_hi;
    wire [31:0] ex_hilo_lo;
    wire ex_is_div;
    wire divider_busy;
    wire divider_valid;
    wire [31:0] divider_quotient;
    wire [31:0] divider_remainder;
    wire divider_start;
    wire divider_accept;
    wire divider_cancel;
    wire divide_wait;

    execute_unit u_execute(
        .pc(id_ex_pc), .rs_value(id_ex_rs_value), .rt_value(id_ex_rt_value),
        .immediate(id_ex_immediate), .shamt(id_ex_shamt),
        .alu_op(id_ex_alu_op), .alu_src_imm(id_ex_alu_src_imm),
        .shift_variable(id_ex_shift_variable), .result_sel(id_ex_result_sel),
        .cp0_value(id_ex_cp0_value), .hi_value(id_ex_hi_value),
        .lo_value(id_ex_lo_value), .hilo_op(id_ex_hilo_op),
        .trap_overflow(id_ex_trap_overflow), .result(ex_result),
        .effective_addr(ex_effective_addr), .overflow(ex_overflow),
        .hilo_we(ex_hilo_we), .hilo_hi(ex_hilo_hi), .hilo_lo(ex_hilo_lo)
    );

    assign ex_is_div = id_ex_valid &&
        (id_ex_hilo_op == `HILO_DIV || id_ex_hilo_op == `HILO_DIVU);
    assign divider_start = ex_is_div && !divider_busy && !divider_valid &&
                           !external_hold && !mem_exception && !mem_eret;
    assign divider_accept = ex_is_div && divider_valid && !external_hold &&
                            !mem_exception && !mem_eret;
    assign divider_cancel = !resetn || mem_exception || mem_eret;
    assign divide_wait = ex_is_div && !divider_valid && !mem_exception && !mem_eret;
    assign pipeline_hold = external_hold || divide_wait;

    iterative_divider u_divider(
        .clk(clk), .resetn(resetn), .start(divider_start),
        .signed_mode(id_ex_hilo_op == `HILO_DIV),
        .dividend(id_ex_rs_value), .divisor(id_ex_rt_value),
        .accept(divider_accept), .cancel(divider_cancel),
        .busy(divider_busy), .valid(divider_valid),
        .quotient(divider_quotient), .remainder(divider_remainder)
    );

    wire ex_hilo_we_final = ex_is_div ? divider_valid : ex_hilo_we;
    wire [31:0] ex_hilo_hi_final = ex_is_div ? divider_remainder : ex_hilo_hi;
    wire [31:0] ex_hilo_lo_final = ex_is_div ? divider_quotient : ex_hilo_lo;

    wire ex_access_en;
    wire [3:0] ex_write_strobe;
    wire [31:0] ex_physical_addr_unused;
    wire [31:0] ex_write_data;
    wire [31:0] ex_load_unused;
    wire [5:0] ex_align_exc;
    memory_access_unit u_ex_memory_format(
        .mem_op(id_ex_mem_op), .virtual_addr(ex_effective_addr),
        .store_value(id_ex_rt_value), .read_word(data_rdata),
        .access_en(ex_access_en), .write_strobe(ex_write_strobe),
        .physical_addr(ex_physical_addr_unused), .write_data(ex_write_data),
        .load_data(ex_load_unused), .align_exc(ex_align_exc)
    );

    wire mem_access_unused;
    wire [3:0] mem_strobe_unused;
    wire [31:0] mem_paddr_unused;
    wire [31:0] mem_wdata_unused;
    wire [31:0] mem_load_data;
    wire [5:0] mem_align_unused;
    memory_access_unit u_mem_load_format(
        .mem_op(ex_mem_mem_op), .virtual_addr(ex_mem_addr),
        .store_value(32'b0), .read_word(data_rdata),
        .access_en(mem_access_unused), .write_strobe(mem_strobe_unused),
        .physical_addr(mem_paddr_unused), .write_data(mem_wdata_unused),
        .load_data(mem_load_data), .align_exc(mem_align_unused)
    );

    wire id_ex_has_load = (id_ex_mem_op == `MEM_LB)  ||
                          (id_ex_mem_op == `MEM_LBU) ||
                          (id_ex_mem_op == `MEM_LH)  ||
                          (id_ex_mem_op == `MEM_LHU) ||
                          (id_ex_mem_op == `MEM_LW);
    wire ex_mem_has_load = (ex_mem_mem_op == `MEM_LB)  ||
                           (ex_mem_mem_op == `MEM_LBU) ||
                           (ex_mem_mem_op == `MEM_LH)  ||
                           (ex_mem_mem_op == `MEM_LHU) ||
                           (ex_mem_mem_op == `MEM_LW);
    wire [31:0] ex_mem_forward_value = ex_mem_has_load ? mem_load_data : ex_mem_result;

    // A synchronous SRAM samples these EX-stage signals on the same edge that
    // captures EX/MEM, making its read word available throughout MEM.
    assign data_en = resetn && id_ex_valid && ex_access_en &&
                     (id_ex_exc == `EXC_NONE) && !ex_overflow &&
                     !mem_exception && !mem_eret;
    assign data_wen = data_en ? ex_write_strobe : 4'b0000;
    assign data_vaddr = ex_effective_addr;
    assign data_wdata = ex_write_data;

    // ------------------------------------------------------------------
    // Forwarding into ID and hazard detection
    // ------------------------------------------------------------------
    wire ex_can_forward = id_ex_valid && id_ex_gpr_we && !id_ex_has_load &&
                          (id_ex_gpr_dst != 5'd0);
    wire mem_can_forward = ex_mem_valid && ex_mem_gpr_we &&
                           (ex_mem_gpr_dst != 5'd0) && !mem_exception;
    wire wb_can_forward = mem_wb_valid && mem_wb_gpr_we &&
                          (mem_wb_gpr_dst != 5'd0);

    wire [31:0] id_rs_value =
        (ex_can_forward  && id_ex_gpr_dst  == id_rs) ? ex_result :
        (mem_can_forward && ex_mem_gpr_dst == id_rs) ? ex_mem_forward_value :
        (wb_can_forward  && mem_wb_gpr_dst == id_rs) ? mem_wb_result : rf_rs_data;
    wire [31:0] id_rt_value =
        (ex_can_forward  && id_ex_gpr_dst  == id_rt) ? ex_result :
        (mem_can_forward && ex_mem_gpr_dst == id_rt) ? ex_mem_forward_value :
        (wb_can_forward  && mem_wb_gpr_dst == id_rt) ? mem_wb_result : rf_rt_data;

    wire load_use_hazard = if_id_valid && id_ex_valid && id_ex_has_load &&
        id_ex_gpr_we && (id_ex_gpr_dst != 5'd0) &&
        ((id_uses_rs && id_rs == id_ex_gpr_dst) ||
         (id_uses_rt && id_rt == id_ex_gpr_dst));

    // Serialize CP0 writes.  This inexpensive barrier also makes software
    // interrupt and ERET timing deterministic without a second CP0 bypass net.
    wire cp0_write_inflight =
        (id_ex_valid && id_ex_cp0_write) ||
        (ex_mem_valid && ex_mem_cp0_write) ||
        (mem_wb_valid && mem_wb_cp0_write);
    wire id_stall = load_use_hazard || (if_id_valid && cp0_write_inflight);

    wire [31:0] id_hi_value =
        (id_ex_valid && ex_hilo_we_final) ? ex_hilo_hi_final :
        (ex_mem_valid && ex_mem_hilo_we) ? ex_mem_hilo_hi :
        (mem_wb_valid && mem_wb_hilo_we) ? mem_wb_hilo_hi : hi_arch;
    wire [31:0] id_lo_value =
        (id_ex_valid && ex_hilo_we_final) ? ex_hilo_lo_final :
        (ex_mem_valid && ex_mem_hilo_we) ? ex_mem_hilo_lo :
        (mem_wb_valid && mem_wb_hilo_we) ? mem_wb_hilo_lo : lo_arch;

    // ------------------------------------------------------------------
    // ID-stage branch resolution with one architectural delay slot
    // ------------------------------------------------------------------
    reg id_branch_taken_raw;
    reg [31:0] id_branch_target;
    always @(*) begin
        id_branch_taken_raw = 1'b0;
        id_branch_target = if_id_pc + 32'd4 + (id_immediate << 2);
        case (id_branch_op)
            `BR_EQ:  id_branch_taken_raw = (id_rs_value == id_rt_value);
            `BR_NE:  id_branch_taken_raw = (id_rs_value != id_rt_value);
            `BR_GEZ: id_branch_taken_raw = !id_rs_value[31];
            `BR_GTZ: id_branch_taken_raw = !id_rs_value[31] && (id_rs_value != 32'b0);
            `BR_LEZ: id_branch_taken_raw = id_rs_value[31] || (id_rs_value == 32'b0);
            `BR_LTZ: id_branch_taken_raw = id_rs_value[31];
            `BR_J: begin
                id_branch_taken_raw = 1'b1;
                id_branch_target = {if_id_pc[31:28], if_id_instr[25:0], 2'b00};
            end
            `BR_JR: begin
                id_branch_taken_raw = 1'b1;
                id_branch_target = id_rs_value;
            end
            default: begin end
        endcase
    end

    wire id_instruction_clean = (if_id_exc == `EXC_NONE) &&
                                (id_decode_exc == `EXC_NONE);
    wire id_is_control = if_id_valid && id_instruction_clean &&
                         (id_branch_op != `BR_NONE);
    wire id_branch_taken = id_is_control && !id_stall && id_branch_taken_raw;

    // Stop the RAM from consuming a new address on a redirect edge.  The
    // already-returned instruction is still latched as the branch delay slot.
    assign inst_en = resetn && !pipeline_hold && !id_stall &&
                     !mem_exception && !mem_eret && !id_branch_taken;

    // ------------------------------------------------------------------
    // Pipeline state updates
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            fetch_pc <= `RESET_PC;
            request_pc_d <= 32'b0;
            request_valid_d <= 1'b0;
            if_id_valid <= 1'b0;
            if_id_pc <= 32'b0;
            if_id_instr <= 32'b0;
            if_id_delay_slot <= 1'b0;
            if_id_exc <= `EXC_NONE;
            if_id_badaddr <= 32'b0;

            id_ex_valid <= 1'b0;
            id_ex_pc <= 32'b0;
            id_ex_delay_slot <= 1'b0;
            id_ex_rs_value <= 32'b0;
            id_ex_rt_value <= 32'b0;
            id_ex_immediate <= 32'b0;
            id_ex_shamt <= 5'b0;
            id_ex_alu_op <= `ALU_ADD;
            id_ex_alu_src_imm <= 1'b0;
            id_ex_shift_variable <= 1'b0;
            id_ex_result_sel <= `RES_ALU;
            id_ex_gpr_we <= 1'b0;
            id_ex_gpr_dst <= 5'b0;
            id_ex_mem_op <= `MEM_NONE;
            id_ex_hilo_op <= `HILO_NONE;
            id_ex_hi_value <= 32'b0;
            id_ex_lo_value <= 32'b0;
            id_ex_cp0_write <= 1'b0;
            id_ex_cp0_addr <= 5'b0;
            id_ex_cp0_value <= 32'b0;
            id_ex_eret <= 1'b0;
            id_ex_trap_overflow <= 1'b0;
            id_ex_exc <= `EXC_NONE;
            id_ex_badaddr <= 32'b0;

            ex_mem_valid <= 1'b0;
            ex_mem_pc <= 32'b0;
            ex_mem_delay_slot <= 1'b0;
            ex_mem_result <= 32'b0;
            ex_mem_gpr_we <= 1'b0;
            ex_mem_gpr_dst <= 5'b0;
            ex_mem_mem_op <= `MEM_NONE;
            ex_mem_addr <= 32'b0;
            ex_mem_hilo_we <= 1'b0;
            ex_mem_hilo_hi <= 32'b0;
            ex_mem_hilo_lo <= 32'b0;
            ex_mem_cp0_write <= 1'b0;
            ex_mem_cp0_addr <= 5'b0;
            ex_mem_cp0_wdata <= 32'b0;
            ex_mem_eret <= 1'b0;
            ex_mem_exc <= `EXC_NONE;
            ex_mem_badaddr <= 32'b0;

            mem_wb_valid <= 1'b0;
            mem_wb_pc <= 32'b0;
            mem_wb_result <= 32'b0;
            mem_wb_gpr_we <= 1'b0;
            mem_wb_gpr_dst <= 5'b0;
            mem_wb_hilo_we <= 1'b0;
            mem_wb_hilo_hi <= 32'b0;
            mem_wb_hilo_lo <= 32'b0;
            mem_wb_cp0_write <= 1'b0;
            mem_wb_cp0_addr <= 5'b0;
            mem_wb_cp0_wdata <= 32'b0;

            hi_arch <= 32'b0;
            lo_arch <= 32'b0;
            debug_wb_pc <= 32'b0;
            debug_wb_rf_wen <= 4'b0;
            debug_wb_rf_wnum <= 5'b0;
            debug_wb_rf_wdata <= 32'b0;
        end else begin
            debug_wb_rf_wen <= 4'b0000;
            if (!pipeline_hold) begin
                // WB is the only architectural commit point.
                if (wb_hilo_commit) begin
                    hi_arch <= mem_wb_hilo_hi;
                    lo_arch <= mem_wb_hilo_lo;
                end
                if (wb_gpr_commit) begin
                    debug_wb_pc <= mem_wb_pc;
                    debug_wb_rf_wen <= 4'b1111;
                    debug_wb_rf_wnum <= mem_wb_gpr_dst;
                    debug_wb_rf_wdata <= mem_wb_result;
                end

                if (mem_exception || mem_eret) begin
                    // The MEM instruction does not retire.  All younger state
                    // is invalidated before it can reach an architectural port.
                    mem_wb_valid <= 1'b0;
                    ex_mem_valid <= 1'b0;
                    id_ex_valid <= 1'b0;
                    if_id_valid <= 1'b0;
                    request_valid_d <= 1'b0;
                    fetch_pc <= mem_exception ? `EXC_VECTOR : cp0_epc;
                end else begin
                    // MEM -> WB
                    mem_wb_valid <= ex_mem_valid;
                    mem_wb_pc <= ex_mem_pc;
                    mem_wb_result <= ex_mem_has_load ? mem_load_data : ex_mem_result;
                    mem_wb_gpr_we <= ex_mem_gpr_we;
                    mem_wb_gpr_dst <= ex_mem_gpr_dst;
                    mem_wb_hilo_we <= ex_mem_hilo_we;
                    mem_wb_hilo_hi <= ex_mem_hilo_hi;
                    mem_wb_hilo_lo <= ex_mem_hilo_lo;
                    mem_wb_cp0_write <= ex_mem_cp0_write;
                    mem_wb_cp0_addr <= ex_mem_cp0_addr;
                    mem_wb_cp0_wdata <= ex_mem_cp0_wdata;

                    // EX -> MEM
                    ex_mem_valid <= id_ex_valid;
                    ex_mem_pc <= id_ex_pc;
                    ex_mem_delay_slot <= id_ex_delay_slot;
                    ex_mem_result <= ex_result;
                    ex_mem_gpr_we <= id_ex_gpr_we;
                    ex_mem_gpr_dst <= id_ex_gpr_dst;
                    ex_mem_mem_op <= id_ex_mem_op;
                    ex_mem_addr <= ex_effective_addr;
                    ex_mem_hilo_we <= ex_hilo_we_final;
                    ex_mem_hilo_hi <= ex_hilo_hi_final;
                    ex_mem_hilo_lo <= ex_hilo_lo_final;
                    ex_mem_cp0_write <= id_ex_cp0_write;
                    ex_mem_cp0_addr <= id_ex_cp0_addr;
                    ex_mem_cp0_wdata <= id_ex_rt_value;
                    ex_mem_eret <= id_ex_eret;
                    ex_mem_badaddr <= (id_ex_exc != `EXC_NONE) ? id_ex_badaddr : ex_effective_addr;
                    if (id_ex_exc != `EXC_NONE)
                        ex_mem_exc <= id_ex_exc;
                    else if (ex_overflow)
                        ex_mem_exc <= `EXC_OV;
                    else
                        ex_mem_exc <= ex_align_exc;

                    if (id_stall) begin
                        // Older stages continue; ID receives one bubble while
                        // the fetched instruction and its pending response hold.
                        id_ex_valid <= 1'b0;
                    end else begin
                        // ID -> EX
                        id_ex_valid <= if_id_valid;
                        id_ex_pc <= if_id_pc;
                        id_ex_delay_slot <= if_id_delay_slot;
                        id_ex_rs_value <= id_rs_value;
                        id_ex_rt_value <= id_rt_value;
                        id_ex_immediate <= id_immediate;
                        id_ex_shamt <= if_id_instr[10:6];
                        id_ex_alu_op <= id_alu_op;
                        id_ex_alu_src_imm <= id_alu_src_imm;
                        id_ex_shift_variable <= id_shift_variable;
                        id_ex_result_sel <= id_result_sel;
                        id_ex_gpr_we <= id_gpr_we;
                        id_ex_gpr_dst <= id_gpr_dst;
                        id_ex_mem_op <= id_mem_op;
                        id_ex_hilo_op <= id_hilo_op;
                        id_ex_hi_value <= id_hi_value;
                        id_ex_lo_value <= id_lo_value;
                        id_ex_cp0_write <= id_cp0_write;
                        id_ex_cp0_addr <= id_cp0_addr;
                        id_ex_cp0_value <= cp0_read_data;
                        id_ex_eret <= id_eret;
                        id_ex_trap_overflow <= id_trap_overflow;
                        id_ex_exc <= (if_id_exc != `EXC_NONE) ? if_id_exc : id_decode_exc;
                        id_ex_badaddr <= if_id_badaddr;

                        // Consume the current SRAM response into IF/ID.
                        if_id_valid <= request_valid_d;
                        if_id_pc <= request_pc_d;
                        if_id_instr <= inst_rdata;
                        if_id_delay_slot <= id_is_control;
                        if_id_exc <= request_valid_d && (request_pc_d[1:0] != 2'b00) ?
                                     `EXC_ADEL : `EXC_NONE;
                        if_id_badaddr <= request_pc_d;

                        if (id_branch_taken) begin
                            // No new request was issued on this edge; the
                            // response just consumed is the sole delay slot.
                            request_valid_d <= 1'b0;
                            fetch_pc <= id_branch_target;
                        end else begin
                            request_pc_d <= fetch_pc;
                            request_valid_d <= 1'b1;
                            fetch_pc <= fetch_pc + 32'd4;
                        end
                    end
                end
            end
        end
    end
endmodule
