`timescale 1ns / 1ps

// 32-cycle restoring divider. Result-valid is held until accept, allowing an
// unrelated AXI/cache stall to overlap calculation without losing the result.
module iterative_divider(
    input  wire        clk,
    input  wire        resetn,
    input  wire        start,
    input  wire        signed_mode,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    input  wire        accept,
    input  wire        cancel,
    output reg         busy,
    output reg         valid,
    output reg  [31:0] quotient,
    output reg  [31:0] remainder
);
    reg [63:0] work;
    reg [31:0] divisor_abs;
    reg [5:0] count;
    reg quotient_negative;
    reg remainder_negative;

    wire [31:0] dividend_abs = (signed_mode && dividend[31]) ?
                               (~dividend + 32'd1) : dividend;
    wire [31:0] divisor_abs_in = (signed_mode && divisor[31]) ?
                                 (~divisor + 32'd1) : divisor;

    reg [63:0] shifted;
    reg [63:0] next_work;
    always @(*) begin
        shifted = work << 1;
        next_work = shifted;
        if (shifted[63:32] >= divisor_abs) begin
            next_work[63:32] = shifted[63:32] - divisor_abs;
            next_work[0] = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!resetn || cancel) begin
            busy <= 1'b0;
            valid <= 1'b0;
            quotient <= 32'b0;
            remainder <= 32'b0;
            work <= 64'b0;
            divisor_abs <= 32'b0;
            count <= 6'b0;
            quotient_negative <= 1'b0;
            remainder_negative <= 1'b0;
        end else begin
            if (accept)
                valid <= 1'b0;

            if (start && !busy && !valid) begin
                if (divisor == 32'b0) begin
                    busy <= 1'b0;
                    valid <= 1'b1;
                    quotient <= (signed_mode && dividend[31]) ? 32'd1 : 32'hffff_ffff;
                    remainder <= dividend;
                end else begin
                    work <= {32'b0, dividend_abs};
                    divisor_abs <= divisor_abs_in;
                    count <= 6'd0;
                    quotient_negative <= signed_mode && (dividend[31] ^ divisor[31]);
                    remainder_negative <= signed_mode && dividend[31];
                    busy <= 1'b1;
                    valid <= 1'b0;
                end
            end else if (busy) begin
                work <= next_work;
                if (count == 6'd31) begin
                    busy <= 1'b0;
                    valid <= 1'b1;
                    quotient <= quotient_negative ? (~next_work[31:0] + 32'd1) : next_work[31:0];
                    remainder <= remainder_negative ? (~next_work[63:32] + 32'd1) : next_work[63:32];
                end else begin
                    count <= count + 6'd1;
                end
            end
        end
    end
endmodule
