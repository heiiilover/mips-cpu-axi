`timescale 1ns / 1ps
`include "mips_defs.vh"

module execute_unit(
    input  wire [31:0] pc,
    input  wire [31:0] rs_value,
    input  wire [31:0] rt_value,
    input  wire [31:0] immediate,
    input  wire [4:0]  shamt,
    input  wire [5:0]  alu_op,
    input  wire         alu_src_imm,
    input  wire         shift_variable,
    input  wire [2:0]   result_sel,
    input  wire [31:0]  cp0_value,
    input  wire [31:0]  hi_value,
    input  wire [31:0]  lo_value,
    input  wire [3:0]   hilo_op,
    input  wire         trap_overflow,
    output reg  [31:0]  result,
    output wire [31:0]  effective_addr,
    output reg          overflow,
    output reg          hilo_we,
    output reg  [31:0]  hilo_hi,
    output reg  [31:0]  hilo_lo
);
    wire [31:0] operand_b = alu_src_imm ? immediate : rt_value;
    wire [4:0] shift_amount = shift_variable ? rs_value[4:0] : shamt;
    reg [31:0] alu_result;
    reg [63:0] product;

    assign effective_addr = rs_value + immediate;

    always @(*) begin
        alu_result = 32'b0;
        case (alu_op)
            `ALU_PASS_B: alu_result = operand_b;
            `ALU_ADD:    alu_result = rs_value + operand_b;
            `ALU_SUB:    alu_result = rs_value - operand_b;
            `ALU_AND:    alu_result = rs_value & operand_b;
            `ALU_OR:     alu_result = rs_value | operand_b;
            `ALU_XOR:    alu_result = rs_value ^ operand_b;
            `ALU_NOR:    alu_result = ~(rs_value | operand_b);
            `ALU_SLT:    alu_result = {31'b0, $signed(rs_value) < $signed(operand_b)};
            `ALU_SLTU:   alu_result = {31'b0, rs_value < operand_b};
            `ALU_SLL:    alu_result = rt_value << shift_amount;
            `ALU_SRL:    alu_result = rt_value >> shift_amount;
            `ALU_SRA:    alu_result = $signed(rt_value) >>> shift_amount;
            `ALU_LUI:    alu_result = {immediate[15:0], 16'b0};
            default:     alu_result = 32'b0;
        endcase

        overflow = 1'b0;
        if (trap_overflow && alu_op == `ALU_ADD)
            overflow = (~(rs_value[31] ^ operand_b[31])) &
                       (alu_result[31] ^ rs_value[31]);
        else if (trap_overflow && alu_op == `ALU_SUB)
            overflow = (rs_value[31] ^ operand_b[31]) &
                       (alu_result[31] ^ rs_value[31]);

        case (result_sel)
            `RES_LINK: result = pc + 32'd8;
            `RES_HI:   result = hi_value;
            `RES_LO:   result = lo_value;
            `RES_CP0:  result = cp0_value;
            default:   result = alu_result;
        endcase

        hilo_we = 1'b0;
        hilo_hi = hi_value;
        hilo_lo = lo_value;
        product = 64'b0;
        case (hilo_op)
            `HILO_MTHI: begin
                hilo_we = 1'b1;
                hilo_hi = rs_value;
            end
            `HILO_MTLO: begin
                hilo_we = 1'b1;
                hilo_lo = rs_value;
            end
            `HILO_MULT: begin
                product = $signed(rs_value) * $signed(rt_value);
                hilo_we = 1'b1;
                hilo_hi = product[63:32];
                hilo_lo = product[31:0];
            end
            `HILO_MULTU: begin
                product = rs_value * rt_value;
                hilo_we = 1'b1;
                hilo_hi = product[63:32];
                hilo_lo = product[31:0];
            end
            // DIV/DIVU are handled by iterative_divider in pipeline_core so
            // synthesis never infers a long combinational divide path.
            `HILO_DIV:  begin end
            `HILO_DIVU: begin end
            default: begin end
        endcase
    end
endmodule
