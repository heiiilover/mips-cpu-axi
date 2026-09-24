`ifndef KS2025_MIPS_DEFS_VH
`define KS2025_MIPS_DEFS_VH

// ALU operation codes.  These are internal micro-operations, not ISA opcodes.
`define ALU_PASS_B  6'd0
`define ALU_ADD     6'd1
`define ALU_SUB     6'd2
`define ALU_AND     6'd3
`define ALU_OR      6'd4
`define ALU_XOR     6'd5
`define ALU_NOR     6'd6
`define ALU_SLT     6'd7
`define ALU_SLTU    6'd8
`define ALU_SLL     6'd9
`define ALU_SRL     6'd10
`define ALU_SRA     6'd11
`define ALU_LUI     6'd12

// Result source selected in EX.
`define RES_ALU     3'd0
`define RES_LINK    3'd1
`define RES_HI      3'd2
`define RES_LO      3'd3
`define RES_CP0     3'd4

// Memory operation carried through the pipeline.
`define MEM_NONE    4'd0
`define MEM_LB      4'd1
`define MEM_LBU     4'd2
`define MEM_LH      4'd3
`define MEM_LHU     4'd4
`define MEM_LW      4'd5
`define MEM_SB      4'd6
`define MEM_SH      4'd7
`define MEM_SW      4'd8

// Control-transfer kind.  All transfers retain the architectural delay slot.
`define BR_NONE     4'd0
`define BR_EQ       4'd1
`define BR_NE       4'd2
`define BR_GEZ      4'd3
`define BR_GTZ      4'd4
`define BR_LEZ      4'd5
`define BR_LTZ      4'd6
`define BR_J        4'd7
`define BR_JR       4'd8

// HI/LO update operation.
`define HILO_NONE   4'd0
`define HILO_MTHI   4'd1
`define HILO_MTLO   4'd2
`define HILO_MULT   4'd3
`define HILO_MULTU  4'd4
`define HILO_DIV    4'd5
`define HILO_DIVU   4'd6

// Six bits leave one explicit sentinel distinct from interrupt code zero.
`define EXC_INT     6'd0
`define EXC_ADEL    6'd4
`define EXC_ADES    6'd5
`define EXC_SYS     6'd8
`define EXC_BP      6'd9
`define EXC_RI      6'd10
`define EXC_OV      6'd12
`define EXC_NONE    6'd63

`define RESET_PC    32'hbfc0_0000
`define EXC_VECTOR  32'hbfc0_0380

`endif
