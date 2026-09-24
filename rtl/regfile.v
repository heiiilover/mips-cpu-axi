`timescale 1ns / 1ps

// Two asynchronous read ports and one synchronous write port.  Explicit
// write-through keeps decode deterministic when WB and ID use the same GPR.
module regfile(
    input  wire        clk,
    input  wire        resetn,
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata1,
    output wire [31:0] rdata2
);
    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    assign rdata1 = (raddr1 == 5'd0) ? 32'b0 :
                    (we && waddr == raddr1 && waddr != 5'd0) ? wdata : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'b0 :
                    (we && waddr == raddr2 && waddr != 5'd0) ? wdata : regs[raddr2];
endmodule
