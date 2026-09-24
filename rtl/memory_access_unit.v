`timescale 1ns / 1ps
`include "mips_defs.vh"

module memory_access_unit(
    input  wire [3:0]  mem_op,
    input  wire [31:0] virtual_addr,
    input  wire [31:0] store_value,
    input  wire [31:0] read_word,
    output reg         access_en,
    output reg  [3:0]  write_strobe,
    output wire [31:0] physical_addr,
    output reg  [31:0] write_data,
    output reg  [31:0] load_data,
    output reg  [5:0]  align_exc
);
    wire kseg_direct = (virtual_addr[31:30] == 2'b10);
    assign physical_addr = kseg_direct ? {3'b000, virtual_addr[28:0]} : virtual_addr;

    reg [7:0] selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        access_en = (mem_op != `MEM_NONE);
        write_strobe = 4'b0000;
        write_data = store_value;
        align_exc = `EXC_NONE;

        case (virtual_addr[1:0])
            2'd0: selected_byte = read_word[7:0];
            2'd1: selected_byte = read_word[15:8];
            2'd2: selected_byte = read_word[23:16];
            default: selected_byte = read_word[31:24];
        endcase
        selected_half = virtual_addr[1] ? read_word[31:16] : read_word[15:0];

        case (mem_op)
            `MEM_LB:  load_data = {{24{selected_byte[7]}}, selected_byte};
            `MEM_LBU: load_data = {24'b0, selected_byte};
            `MEM_LH:  load_data = {{16{selected_half[15]}}, selected_half};
            `MEM_LHU: load_data = {16'b0, selected_half};
            `MEM_LW:  load_data = read_word;
            default:  load_data = 32'b0;
        endcase

        case (mem_op)
            `MEM_SB: begin
                write_strobe = 4'b0001 << virtual_addr[1:0];
                write_data = {4{store_value[7:0]}};
            end
            `MEM_SH: begin
                write_strobe = virtual_addr[1] ? 4'b1100 : 4'b0011;
                write_data = {2{store_value[15:0]}};
            end
            `MEM_SW: begin
                write_strobe = 4'b1111;
                write_data = store_value;
            end
            default: begin end
        endcase

        if ((mem_op == `MEM_LW) && (virtual_addr[1:0] != 2'b00))
            align_exc = `EXC_ADEL;
        else if ((mem_op == `MEM_LH || mem_op == `MEM_LHU) && virtual_addr[0])
            align_exc = `EXC_ADEL;
        else if ((mem_op == `MEM_SW) && (virtual_addr[1:0] != 2'b00))
            align_exc = `EXC_ADES;
        else if ((mem_op == `MEM_SH) && virtual_addr[0])
            align_exc = `EXC_ADES;

        if (align_exc != `EXC_NONE) begin
            access_en = 1'b0;
            write_strobe = 4'b0000;
        end
    end
endmodule
