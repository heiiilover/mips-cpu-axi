`timescale 1ns / 1ps

// One-transaction AXI3 master.  Read transactions may contain a short INCR
// burst; writes are single-beat write-through operations.  Address and data
// channels are tracked independently as required by AXI.
module axi_master(
    input  wire        clk,
    input  wire        resetn,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire        req_write,
    input  wire [31:0] req_addr,
    input  wire [7:0]  req_len,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wstrb,
    output wire        read_valid,
    output wire [31:0] read_data,
    output wire        read_last,
    output wire        write_done,

    output wire [3:0]  arid,
    output wire [31:0] araddr,
    output wire [7:0]  arlen,
    output wire [2:0]  arsize,
    output wire [1:0]  arburst,
    output wire [1:0]  arlock,
    output wire [3:0]  arcache,
    output wire [2:0]  arprot,
    output wire        arvalid,
    input  wire        arready,
    input  wire [3:0]  rid,
    input  wire [31:0] rdata,
    input  wire [1:0]  rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,

    output wire [3:0]  awid,
    output wire [31:0] awaddr,
    output wire [7:0]  awlen,
    output wire [2:0]  awsize,
    output wire [1:0]  awburst,
    output wire [1:0]  awlock,
    output wire [3:0]  awcache,
    output wire [2:0]  awprot,
    output wire        awvalid,
    input  wire        awready,
    output wire [3:0]  wid,
    output wire [31:0] wdata,
    output wire [3:0]  wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,
    input  wire [3:0]  bid,
    input  wire [1:0]  bresp,
    input  wire        bvalid,
    output wire        bready
);
    localparam ST_IDLE = 3'd0;
    localparam ST_AR   = 3'd1;
    localparam ST_R    = 3'd2;
    localparam ST_AW_W = 3'd3;
    localparam ST_B    = 3'd4;

    reg [2:0] state;
    reg [31:0] addr_q;
    reg [7:0] len_q;
    reg [31:0] wdata_q;
    reg [3:0] wstrb_q;
    reg aw_done;
    reg w_done;

    assign req_ready = (state == ST_IDLE);
    assign arvalid = (state == ST_AR);
    assign rready = (state == ST_R);
    assign awvalid = (state == ST_AW_W) && !aw_done;
    assign wvalid = (state == ST_AW_W) && !w_done;
    assign bready = (state == ST_B);

    assign read_valid = (state == ST_R) && rvalid;
    assign read_data = rdata;
    assign read_last = rlast;
    assign write_done = (state == ST_B) && bvalid;

    assign arid = 4'd0;
    assign araddr = addr_q;
    assign arlen = len_q;
    assign arsize = 3'd2;
    assign arburst = 2'b01;
    assign arlock = 2'b00;
    assign arcache = 4'b0011;
    assign arprot = 3'b000;

    assign awid = 4'd0;
    assign awaddr = addr_q;
    assign awlen = 8'd0;
    assign awsize = 3'd2;
    assign awburst = 2'b01;
    assign awlock = 2'b00;
    assign awcache = 4'b0011;
    assign awprot = 3'b000;
    assign wid = 4'd0;
    assign wdata = wdata_q;
    assign wstrb = wstrb_q;
    assign wlast = 1'b1;

    always @(posedge clk) begin
        if (!resetn) begin
            state <= ST_IDLE;
            addr_q <= 32'b0;
            len_q <= 8'b0;
            wdata_q <= 32'b0;
            wstrb_q <= 4'b0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    if (req_valid) begin
                        addr_q <= req_addr;
                        len_q <= req_len;
                        wdata_q <= req_wdata;
                        wstrb_q <= req_wstrb;
                        state <= req_write ? ST_AW_W : ST_AR;
                    end
                end
                ST_AR: begin
                    if (arready)
                        state <= ST_R;
                end
                ST_R: begin
                    if (rvalid && rlast)
                        state <= ST_IDLE;
                end
                ST_AW_W: begin
                    if (awvalid && awready)
                        aw_done <= 1'b1;
                    if (wvalid && wready)
                        w_done <= 1'b1;
                    if ((aw_done || (awvalid && awready)) &&
                        (w_done || (wvalid && wready)))
                        state <= ST_B;
                end
                ST_B: begin
                    if (bvalid)
                        state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    // IDs and response codes are intentionally consumed but not used: this
    // master permits only one outstanding transaction, so ordering is fixed.
    wire unused_response = ^{rid, rresp, bid, bresp};
endmodule
