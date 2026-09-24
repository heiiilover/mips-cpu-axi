`timescale 1ns / 1ps
`include "mips_defs.vh"

// Minimal MIPS32 system-control block required by the 89-point package.
// Implemented registers: BadVAddr, Count, Compare, Status, Cause, EPC,
// PRId and Config.  Unsupported register numbers read as zero.
module cp0_regs(
    input  wire        clk,
    input  wire        resetn,
    input  wire [5:0]  ext_int,
    input  wire [4:0]  read_addr,
    output reg  [31:0] read_data,
    input  wire        wb_we,
    input  wire [4:0]  wb_addr,
    input  wire [31:0] wb_data,
    input  wire        exception_valid,
    input  wire [5:0]  exception_code,
    input  wire [31:0] exception_pc,
    input  wire        exception_delay_slot,
    input  wire [31:0] exception_badaddr,
    input  wire        eret_commit,
    output wire        interrupt_pending,
    output wire [31:0] epc_value,
    output wire [31:0] status_value,
    output wire [31:0] cause_value
);
    reg [31:0] badvaddr;
    reg [31:0] count;
    reg [31:0] compare;
    reg [31:0] status;
    reg [31:0] cause;
    reg [31:0] epc;
    reg        timer_pending;

    wire [5:0] hw_pending = {ext_int[5] | timer_pending, ext_int[4:0]};
    wire [7:0] pending_masked = cause[15:8] & status[15:8];

    assign interrupt_pending = status[0] && !status[1] && (|pending_masked);
    assign epc_value = epc;
    assign status_value = status;
    assign cause_value = cause;

    always @(*) begin
        case (read_addr)
            5'd8:  read_data = badvaddr;
            5'd9:  read_data = count;
            5'd11: read_data = compare;
            5'd12: read_data = status;
            5'd13: read_data = cause;
            5'd14: read_data = epc;
            5'd15: read_data = 32'h0001_8000;
            5'd16: read_data = 32'h0000_0080; // MIPS32, little-endian, no MMU
            default: read_data = 32'b0;
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            badvaddr <= 32'b0;
            count <= 32'b0;
            compare <= 32'b0;
            status <= 32'h0040_0000; // BEV=1 selects the bootstrap vector
            cause <= 32'b0;
            epc <= 32'b0;
            timer_pending <= 1'b0;
        end else begin
            count <= count + 32'd1;
            cause[15:10] <= hw_pending;
            cause[30] <= timer_pending;

            if (compare != 32'b0 && count == compare)
                timer_pending <= 1'b1;

            if (wb_we) begin
                case (wb_addr)
                    5'd9: count <= wb_data;
                    5'd11: begin
                        compare <= wb_data;
                        timer_pending <= 1'b0;
                        cause[30] <= 1'b0;
                    end
                    5'd12: status <= wb_data;
                    5'd13: cause[9:8] <= wb_data[9:8];
                    5'd14: epc <= wb_data;
                    default: begin end
                endcase
            end

            if (eret_commit) begin
                status[1] <= 1'b0;
            end

            if (exception_valid) begin
                if (!status[1]) begin
                    epc <= exception_delay_slot ? exception_pc - 32'd4 : exception_pc;
                    cause[31] <= exception_delay_slot;
                end
                status[1] <= 1'b1;
                cause[6:2] <= exception_code[4:0];
                if (exception_code == `EXC_ADEL || exception_code == `EXC_ADES)
                    badvaddr <= exception_badaddr;
            end
        end
    end
endmodule
