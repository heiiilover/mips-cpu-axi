`timescale 1ns / 1ps

// AXI/cache top level required by func_test_v0.01/soc_axi_func.
module mycpu_top(
    input  wire [5:0]  ext_int,
    input  wire        aclk,
    input  wire        aresetn,

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
    output wire        bready,

    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_wen,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);
    wire core_inst_en;
    wire [31:0] core_inst_vaddr;
    wire [31:0] core_inst_rdata;
    wire core_data_en;
    wire [3:0] core_data_wen;
    wire [31:0] core_data_vaddr;
    wire [31:0] core_data_wdata;
    wire [31:0] core_data_rdata;
    wire core_hold;

    pipeline_core u_core(
        .clk(aclk), .resetn(aresetn), .ext_int(ext_int),
        .external_hold(core_hold),
        .inst_en(core_inst_en), .inst_vaddr(core_inst_vaddr),
        .inst_rdata(core_inst_rdata),
        .data_en(core_data_en), .data_wen(core_data_wen),
        .data_vaddr(core_data_vaddr), .data_wdata(core_data_wdata),
        .data_rdata(core_data_rdata),
        .debug_wb_pc(debug_wb_pc), .debug_wb_rf_wen(debug_wb_rf_wen),
        .debug_wb_rf_wnum(debug_wb_rf_wnum),
        .debug_wb_rf_wdata(debug_wb_rf_wdata)
    );

    wire mem_req_valid;
    wire mem_req_ready;
    wire mem_req_write;
    wire [31:0] mem_req_addr;
    wire [7:0] mem_req_len;
    wire [31:0] mem_req_wdata;
    wire [3:0] mem_req_wstrb;
    wire mem_read_valid;
    wire [31:0] mem_read_data;
    wire mem_read_last;
    wire mem_write_done;

    cached_axi_bridge u_cache_bridge(
        .clk(aclk), .resetn(aresetn),
        .core_inst_en(core_inst_en), .core_inst_vaddr(core_inst_vaddr),
        .core_inst_rdata(core_inst_rdata),
        .core_data_en(core_data_en), .core_data_wen(core_data_wen),
        .core_data_vaddr(core_data_vaddr), .core_data_wdata(core_data_wdata),
        .core_data_rdata(core_data_rdata), .core_hold(core_hold),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write), .mem_req_addr(mem_req_addr),
        .mem_req_len(mem_req_len), .mem_req_wdata(mem_req_wdata),
        .mem_req_wstrb(mem_req_wstrb), .mem_read_valid(mem_read_valid),
        .mem_read_data(mem_read_data), .mem_read_last(mem_read_last),
        .mem_write_done(mem_write_done)
    );

    axi_master u_axi_master(
        .clk(aclk), .resetn(aresetn),
        .req_valid(mem_req_valid), .req_ready(mem_req_ready),
        .req_write(mem_req_write), .req_addr(mem_req_addr), .req_len(mem_req_len),
        .req_wdata(mem_req_wdata), .req_wstrb(mem_req_wstrb),
        .read_valid(mem_read_valid), .read_data(mem_read_data),
        .read_last(mem_read_last), .write_done(mem_write_done),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache), .arprot(arprot),
        .arvalid(arvalid), .arready(arready), .rid(rid), .rdata(rdata),
        .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache), .awprot(awprot),
        .awvalid(awvalid), .awready(awready), .wid(wid), .wdata(wdata),
        .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready)
    );
endmodule
