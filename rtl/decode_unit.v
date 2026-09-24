`timescale 1ns / 1ps
`include "mips_defs.vh"

// ISA decode is deliberately isolated from pipeline control.  Keeping this
// module purely combinational makes the supported instruction set auditable.
module decode_unit(
    input  wire [31:0] instr,
    output wire [4:0]  rs,
    output wire [4:0]  rt,
    output reg          uses_rs,
    output reg          uses_rt,
    output reg  [5:0]   alu_op,
    output reg          alu_src_imm,
    output reg          shift_variable,
    output reg  [31:0]  immediate,
    output reg  [2:0]   result_sel,
    output reg          gpr_we,
    output reg  [4:0]   gpr_dst,
    output reg  [3:0]   mem_op,
    output reg  [3:0]   branch_op,
    output reg          link,
    output reg  [3:0]   hilo_op,
    output reg          cp0_read,
    output reg          cp0_write,
    output reg  [4:0]   cp0_addr,
    output reg          eret,
    output reg          trap_overflow,
    output reg  [5:0]   decode_exc
);
    wire [5:0] op    = instr[31:26];
    wire [5:0] funct = instr[5:0];
    wire [4:0] rd    = instr[15:11];
    wire [4:0] sa    = instr[10:6];
    wire [15:0] imm16 = instr[15:0];

    assign rs = instr[25:21];
    assign rt = instr[20:16];

    always @(*) begin
        uses_rs        = 1'b0;
        uses_rt        = 1'b0;
        alu_op         = `ALU_ADD;
        alu_src_imm    = 1'b0;
        shift_variable = 1'b0;
        immediate      = {{16{imm16[15]}}, imm16};
        result_sel     = `RES_ALU;
        gpr_we         = 1'b0;
        gpr_dst        = rd;
        mem_op         = `MEM_NONE;
        branch_op      = `BR_NONE;
        link           = 1'b0;
        hilo_op        = `HILO_NONE;
        cp0_read       = 1'b0;
        cp0_write      = 1'b0;
        cp0_addr       = rd;
        eret           = 1'b0;
        trap_overflow  = 1'b0;
        decode_exc     = `EXC_RI;

        case (op)
            6'h00: begin
                case (funct)
                    6'h00: if (instr[25:21] == 5'd0) begin // SLL / canonical NOP
                        uses_rt = (rt != 5'd0);
                        alu_op = `ALU_SLL;
                        gpr_we = 1'b1;
                        decode_exc = `EXC_NONE;
                    end
                    6'h02: if (instr[25:21] == 5'd0) begin // SRL
                        uses_rt = 1'b1;
                        alu_op = `ALU_SRL;
                        gpr_we = 1'b1;
                        decode_exc = `EXC_NONE;
                    end
                    6'h03: if (instr[25:21] == 5'd0) begin // SRA
                        uses_rt = 1'b1;
                        alu_op = `ALU_SRA;
                        gpr_we = 1'b1;
                        decode_exc = `EXC_NONE;
                    end
                    6'h04: if (sa == 5'd0) begin // SLLV
                        uses_rs = 1'b1; uses_rt = 1'b1;
                        alu_op = `ALU_SLL; shift_variable = 1'b1;
                        gpr_we = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h06: if (sa == 5'd0) begin // SRLV
                        uses_rs = 1'b1; uses_rt = 1'b1;
                        alu_op = `ALU_SRL; shift_variable = 1'b1;
                        gpr_we = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h07: if (sa == 5'd0) begin // SRAV
                        uses_rs = 1'b1; uses_rt = 1'b1;
                        alu_op = `ALU_SRA; shift_variable = 1'b1;
                        gpr_we = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h08: if (rt == 5'd0 && rd == 5'd0 && sa == 5'd0) begin // JR
                        uses_rs = 1'b1; branch_op = `BR_JR;
                        decode_exc = `EXC_NONE;
                    end
                    6'h09: if (rt == 5'd0 && sa == 5'd0) begin // JALR
                        uses_rs = 1'b1; branch_op = `BR_JR; link = 1'b1;
                        gpr_we = 1'b1; gpr_dst = rd; result_sel = `RES_LINK;
                        decode_exc = `EXC_NONE;
                    end
                    6'h0c: begin decode_exc = `EXC_SYS; end
                    6'h0d: begin decode_exc = `EXC_BP;  end
                    6'h10: if (rs == 5'd0 && rt == 5'd0 && sa == 5'd0) begin // MFHI
                        result_sel = `RES_HI; gpr_we = 1'b1;
                        decode_exc = `EXC_NONE;
                    end
                    6'h11: if (rt == 5'd0 && rd == 5'd0 && sa == 5'd0) begin // MTHI
                        uses_rs = 1'b1; hilo_op = `HILO_MTHI;
                        decode_exc = `EXC_NONE;
                    end
                    6'h12: if (rs == 5'd0 && rt == 5'd0 && sa == 5'd0) begin // MFLO
                        result_sel = `RES_LO; gpr_we = 1'b1;
                        decode_exc = `EXC_NONE;
                    end
                    6'h13: if (rt == 5'd0 && rd == 5'd0 && sa == 5'd0) begin // MTLO
                        uses_rs = 1'b1; hilo_op = `HILO_MTLO;
                        decode_exc = `EXC_NONE;
                    end
                    6'h18: if (rd == 5'd0 && sa == 5'd0) begin // MULT
                        uses_rs = 1'b1; uses_rt = 1'b1; hilo_op = `HILO_MULT;
                        decode_exc = `EXC_NONE;
                    end
                    6'h19: if (rd == 5'd0 && sa == 5'd0) begin // MULTU
                        uses_rs = 1'b1; uses_rt = 1'b1; hilo_op = `HILO_MULTU;
                        decode_exc = `EXC_NONE;
                    end
                    6'h1a: if (rd == 5'd0 && sa == 5'd0) begin // DIV
                        uses_rs = 1'b1; uses_rt = 1'b1; hilo_op = `HILO_DIV;
                        decode_exc = `EXC_NONE;
                    end
                    6'h1b: if (rd == 5'd0 && sa == 5'd0) begin // DIVU
                        uses_rs = 1'b1; uses_rt = 1'b1; hilo_op = `HILO_DIVU;
                        decode_exc = `EXC_NONE;
                    end
                    6'h20: if (sa == 5'd0) begin // ADD
                        uses_rs = 1'b1; uses_rt = 1'b1; alu_op = `ALU_ADD;
                        gpr_we = 1'b1; trap_overflow = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h21: if (sa == 5'd0) begin // ADDU
                        uses_rs = 1'b1; uses_rt = 1'b1; alu_op = `ALU_ADD;
                        gpr_we = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h22: if (sa == 5'd0) begin // SUB
                        uses_rs = 1'b1; uses_rt = 1'b1; alu_op = `ALU_SUB;
                        gpr_we = 1'b1; trap_overflow = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h23: if (sa == 5'd0) begin // SUBU
                        uses_rs = 1'b1; uses_rt = 1'b1; alu_op = `ALU_SUB;
                        gpr_we = 1'b1; decode_exc = `EXC_NONE;
                    end
                    6'h24: if (sa == 5'd0) begin uses_rs=1'b1; uses_rt=1'b1; alu_op=`ALU_AND; gpr_we=1'b1; decode_exc=`EXC_NONE; end
                    6'h25: if (sa == 5'd0) begin uses_rs=1'b1; uses_rt=1'b1; alu_op=`ALU_OR;  gpr_we=1'b1; decode_exc=`EXC_NONE; end
                    6'h26: if (sa == 5'd0) begin uses_rs=1'b1; uses_rt=1'b1; alu_op=`ALU_XOR; gpr_we=1'b1; decode_exc=`EXC_NONE; end
                    6'h27: if (sa == 5'd0) begin uses_rs=1'b1; uses_rt=1'b1; alu_op=`ALU_NOR; gpr_we=1'b1; decode_exc=`EXC_NONE; end
                    6'h2a: if (sa == 5'd0) begin uses_rs=1'b1; uses_rt=1'b1; alu_op=`ALU_SLT; gpr_we=1'b1; decode_exc=`EXC_NONE; end
                    6'h2b: if (sa == 5'd0) begin uses_rs=1'b1; uses_rt=1'b1; alu_op=`ALU_SLTU;gpr_we=1'b1; decode_exc=`EXC_NONE; end
                    default: begin end
                endcase
            end
            6'h01: begin // REGIMM
                uses_rs = 1'b1;
                case (rt)
                    5'h00: begin branch_op=`BR_LTZ; decode_exc=`EXC_NONE; end
                    5'h01: begin branch_op=`BR_GEZ; decode_exc=`EXC_NONE; end
                    5'h10: begin branch_op=`BR_LTZ; link=1'b1; gpr_we=1'b1; gpr_dst=5'd31; result_sel=`RES_LINK; decode_exc=`EXC_NONE; end
                    5'h11: begin branch_op=`BR_GEZ; link=1'b1; gpr_we=1'b1; gpr_dst=5'd31; result_sel=`RES_LINK; decode_exc=`EXC_NONE; end
                    default: begin end
                endcase
            end
            6'h02: begin branch_op=`BR_J; decode_exc=`EXC_NONE; end // J
            6'h03: begin branch_op=`BR_J; link=1'b1; gpr_we=1'b1; gpr_dst=5'd31; result_sel=`RES_LINK; decode_exc=`EXC_NONE; end // JAL
            6'h04: begin uses_rs=1'b1; uses_rt=1'b1; branch_op=`BR_EQ;  decode_exc=`EXC_NONE; end
            6'h05: begin uses_rs=1'b1; uses_rt=1'b1; branch_op=`BR_NE;  decode_exc=`EXC_NONE; end
            6'h06: if (rt == 5'd0) begin uses_rs=1'b1; branch_op=`BR_LEZ; decode_exc=`EXC_NONE; end
            6'h07: if (rt == 5'd0) begin uses_rs=1'b1; branch_op=`BR_GTZ; decode_exc=`EXC_NONE; end
            6'h08: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; trap_overflow=1'b1; decode_exc=`EXC_NONE; end
            6'h09: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h0a: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_SLT; gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h0b: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_SLTU;gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h0c: begin uses_rs=1'b1; alu_src_imm=1'b1; immediate={16'b0,imm16}; alu_op=`ALU_AND; gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h0d: begin uses_rs=1'b1; alu_src_imm=1'b1; immediate={16'b0,imm16}; alu_op=`ALU_OR;  gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h0e: begin uses_rs=1'b1; alu_src_imm=1'b1; immediate={16'b0,imm16}; alu_op=`ALU_XOR; gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h0f: if (rs == 5'd0) begin alu_src_imm=1'b1; immediate={16'b0,imm16}; alu_op=`ALU_LUI; gpr_we=1'b1; gpr_dst=rt; decode_exc=`EXC_NONE; end
            6'h10: begin // COP0 subset used by the functional package
                if (instr == 32'h4200_0018) begin
                    eret = 1'b1;
                    decode_exc = `EXC_NONE;
                end else if (rs == 5'h00 && instr[10:0] == 11'd0) begin
                    cp0_read = 1'b1; cp0_addr = rd;
                    result_sel = `RES_CP0; gpr_we = 1'b1; gpr_dst = rt;
                    decode_exc = `EXC_NONE;
                end else if (rs == 5'h04 && instr[10:0] == 11'd0) begin
                    uses_rt = 1'b1; cp0_write = 1'b1; cp0_addr = rd;
                    decode_exc = `EXC_NONE;
                end
            end
            6'h20: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; mem_op=`MEM_LB;  decode_exc=`EXC_NONE; end
            6'h21: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; mem_op=`MEM_LH;  decode_exc=`EXC_NONE; end
            6'h23: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; mem_op=`MEM_LW;  decode_exc=`EXC_NONE; end
            6'h24: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; mem_op=`MEM_LBU; decode_exc=`EXC_NONE; end
            6'h25: begin uses_rs=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; gpr_we=1'b1; gpr_dst=rt; mem_op=`MEM_LHU; decode_exc=`EXC_NONE; end
            6'h28: begin uses_rs=1'b1; uses_rt=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; mem_op=`MEM_SB; decode_exc=`EXC_NONE; end
            6'h29: begin uses_rs=1'b1; uses_rt=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; mem_op=`MEM_SH; decode_exc=`EXC_NONE; end
            6'h2b: begin uses_rs=1'b1; uses_rt=1'b1; alu_src_imm=1'b1; alu_op=`ALU_ADD; mem_op=`MEM_SW; decode_exc=`EXC_NONE; end
            default: begin end
        endcase
    end
endmodule
