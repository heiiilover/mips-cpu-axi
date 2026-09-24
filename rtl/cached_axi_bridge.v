`timescale 1ns / 1ps

// Blocking Harvard cache layer for the five-stage core.
// - 2 KiB direct-mapped I-cache, four words per line
// - 2 KiB direct-mapped D-cache, write-through/no-write-allocate
// - kseg0 is cached; kseg1 and device addresses are uncached
// A central queue retains simultaneous I and D misses before serializing them
// onto the single AXI read channel.
module cached_axi_bridge(
    input  wire        clk,
    input  wire        resetn,

    input  wire        core_inst_en,
    input  wire [31:0] core_inst_vaddr,
    output reg  [31:0] core_inst_rdata,
    input  wire        core_data_en,
    input  wire [3:0]  core_data_wen,
    input  wire [31:0] core_data_vaddr,
    input  wire [31:0] core_data_wdata,
    output reg  [31:0] core_data_rdata,
    output wire        core_hold,

    output wire        mem_req_valid,
    input  wire        mem_req_ready,
    output wire        mem_req_write,
    output wire [31:0] mem_req_addr,
    output wire [7:0]  mem_req_len,
    output wire [31:0] mem_req_wdata,
    output wire [3:0]  mem_req_wstrb,
    input  wire        mem_read_valid,
    input  wire [31:0] mem_read_data,
    input  wire        mem_read_last,
    input  wire        mem_write_done
);
    localparam LINES = 128;
    localparam S_IDLE = 3'd0;
    localparam S_I_FILL = 3'd1;
    localparam S_I_UNC  = 3'd2;
    localparam S_D_FILL = 3'd3;
    localparam S_D_UNC  = 3'd4;
    localparam S_D_WRITE= 3'd5;

    reg ic_valid [0:LINES-1];
    reg [20:0] ic_tag [0:LINES-1];
    reg [31:0] ic_w0 [0:LINES-1];
    reg [31:0] ic_w1 [0:LINES-1];
    reg [31:0] ic_w2 [0:LINES-1];
    reg [31:0] ic_w3 [0:LINES-1];

    reg dc_valid [0:LINES-1];
    reg [20:0] dc_tag [0:LINES-1];
    reg [31:0] dc_w0 [0:LINES-1];
    reg [31:0] dc_w1 [0:LINES-1];
    reg [31:0] dc_w2 [0:LINES-1];
    reg [31:0] dc_w3 [0:LINES-1];

    function [31:0] direct_map;
        input [31:0] virtual_addr;
        begin
            direct_map = (virtual_addr[31:30] == 2'b10) ?
                         {3'b000, virtual_addr[28:0]} : virtual_addr;
        end
    endfunction

    function [31:0] merge_bytes;
        input [31:0] old_word;
        input [31:0] new_word;
        input [3:0] strobe;
        begin
            merge_bytes[7:0]   = strobe[0] ? new_word[7:0]   : old_word[7:0];
            merge_bytes[15:8]  = strobe[1] ? new_word[15:8]  : old_word[15:8];
            merge_bytes[23:16] = strobe[2] ? new_word[23:16] : old_word[23:16];
            merge_bytes[31:24] = strobe[3] ? new_word[31:24] : old_word[31:24];
        end
    endfunction

    wire [31:0] i_paddr = direct_map(core_inst_vaddr);
    wire [31:0] d_paddr = direct_map(core_data_vaddr);
    wire i_cacheable = (core_inst_vaddr[31:29] == 3'b100);
    wire d_cacheable = (core_data_vaddr[31:29] == 3'b100);
    wire [6:0] i_index = i_paddr[10:4];
    wire [6:0] d_index = d_paddr[10:4];
    wire [1:0] i_word = i_paddr[3:2];
    wire [1:0] d_word = d_paddr[3:2];
    wire i_hit = i_cacheable && ic_valid[i_index] && ic_tag[i_index] == i_paddr[31:11];
    wire d_hit = d_cacheable && dc_valid[d_index] && dc_tag[d_index] == d_paddr[31:11];

    reg i_pending;
    reg [31:0] i_pending_addr;
    reg i_pending_cacheable;
    reg [6:0] i_pending_index;
    reg [20:0] i_pending_tag;
    reg [1:0] i_pending_word;

    reg d_pending;
    reg [31:0] d_pending_addr;
    reg d_pending_write;
    reg d_pending_cacheable;
    reg [6:0] d_pending_index;
    reg [20:0] d_pending_tag;
    reg [1:0] d_pending_word;
    reg [31:0] d_pending_wdata;
    reg [3:0] d_pending_wstrb;

    reg [2:0] service;
    reg [1:0] beat_count;
    reg [31:0] fill0, fill1, fill2, fill3;

    assign core_hold = i_pending || d_pending || (service != S_IDLE);

    // Data traffic has priority so that an older MEM-stage instruction cannot
    // be starved by the speculative fetch stream.
    wire choose_d = (service == S_IDLE) && d_pending;
    wire choose_i = (service == S_IDLE) && !d_pending && i_pending;
    assign mem_req_valid = choose_d || choose_i;
    assign mem_req_write = choose_d && d_pending_write;
    assign mem_req_addr = choose_d ?
        (d_pending_write ? {d_pending_addr[31:2],2'b00} :
         (d_pending_cacheable ? {d_pending_addr[31:4],4'b0000} : {d_pending_addr[31:2],2'b00})) :
        (i_pending_cacheable ? {i_pending_addr[31:4],4'b0000} : {i_pending_addr[31:2],2'b00});
    assign mem_req_len = ((choose_d && !d_pending_write && d_pending_cacheable) ||
                          (choose_i && i_pending_cacheable)) ? 8'd3 : 8'd0;
    assign mem_req_wdata = d_pending_wdata;
    assign mem_req_wstrb = d_pending_wstrb;

    integer k;
    reg [31:0] hit_word;
    always @(*) begin
        case (i_word)
            2'd0: hit_word = ic_w0[i_index];
            2'd1: hit_word = ic_w1[i_index];
            2'd2: hit_word = ic_w2[i_index];
            default: hit_word = ic_w3[i_index];
        endcase
    end

    reg [31:0] d_hit_word;
    always @(*) begin
        case (d_word)
            2'd0: d_hit_word = dc_w0[d_index];
            2'd1: d_hit_word = dc_w1[d_index];
            2'd2: d_hit_word = dc_w2[d_index];
            default: d_hit_word = dc_w3[d_index];
        endcase
    end

    always @(posedge clk) begin
        if (!resetn) begin
            i_pending <= 1'b0;
            d_pending <= 1'b0;
            service <= S_IDLE;
            beat_count <= 2'b0;
            core_inst_rdata <= 32'b0;
            core_data_rdata <= 32'b0;
            fill0 <= 32'b0; fill1 <= 32'b0; fill2 <= 32'b0; fill3 <= 32'b0;
            for (k = 0; k < LINES; k = k + 1) begin
                ic_valid[k] <= 1'b0;
                dc_valid[k] <= 1'b0;
            end
        end else begin
            // New CPU requests are sampled only when no blocked transaction is
            // outstanding.  On the sampling edge the core may still advance;
            // core_hold becomes active immediately afterwards on a miss.
            if (!core_hold) begin
                if (core_inst_en) begin
                    if (i_hit) begin
                        core_inst_rdata <= hit_word;
                    end else begin
                        i_pending <= 1'b1;
                        i_pending_addr <= i_paddr;
                        i_pending_cacheable <= i_cacheable;
                        i_pending_index <= i_index;
                        i_pending_tag <= i_paddr[31:11];
                        i_pending_word <= i_word;
                    end
                end

                if (core_data_en) begin
                    if (core_data_wen == 4'b0000) begin
                        if (d_hit) begin
                            core_data_rdata <= d_hit_word;
                        end else begin
                            d_pending <= 1'b1;
                            d_pending_addr <= d_paddr;
                            d_pending_write <= 1'b0;
                            d_pending_cacheable <= d_cacheable;
                            d_pending_index <= d_index;
                            d_pending_tag <= d_paddr[31:11];
                            d_pending_word <= d_word;
                            d_pending_wdata <= 32'b0;
                            d_pending_wstrb <= 4'b0;
                        end
                    end else begin
                        // Write-through and no-write-allocate.  A hit is merged
                        // locally before the AXI response is awaited.
                        if (d_hit) begin
                            case (d_word)
                                2'd0: dc_w0[d_index] <= merge_bytes(dc_w0[d_index], core_data_wdata, core_data_wen);
                                2'd1: dc_w1[d_index] <= merge_bytes(dc_w1[d_index], core_data_wdata, core_data_wen);
                                2'd2: dc_w2[d_index] <= merge_bytes(dc_w2[d_index], core_data_wdata, core_data_wen);
                                2'd3: dc_w3[d_index] <= merge_bytes(dc_w3[d_index], core_data_wdata, core_data_wen);
                            endcase
                        end
                        d_pending <= 1'b1;
                        d_pending_addr <= d_paddr;
                        d_pending_write <= 1'b1;
                        d_pending_cacheable <= d_cacheable;
                        d_pending_index <= d_index;
                        d_pending_tag <= d_paddr[31:11];
                        d_pending_word <= d_word;
                        d_pending_wdata <= core_data_wdata;
                        d_pending_wstrb <= core_data_wen;
                    end
                end
            end

            if (mem_req_valid && mem_req_ready) begin
                beat_count <= 2'b0;
                if (choose_d) begin
                    if (d_pending_write)
                        service <= S_D_WRITE;
                    else if (d_pending_cacheable)
                        service <= S_D_FILL;
                    else
                        service <= S_D_UNC;
                end else if (choose_i) begin
                    service <= i_pending_cacheable ? S_I_FILL : S_I_UNC;
                end
            end

            if (mem_read_valid) begin
                case (service)
                    S_I_FILL: begin
                        case (beat_count)
                            2'd0: begin fill0 <= mem_read_data; ic_w0[i_pending_index] <= mem_read_data; end
                            2'd1: begin fill1 <= mem_read_data; ic_w1[i_pending_index] <= mem_read_data; end
                            2'd2: begin fill2 <= mem_read_data; ic_w2[i_pending_index] <= mem_read_data; end
                            2'd3: begin fill3 <= mem_read_data; ic_w3[i_pending_index] <= mem_read_data; end
                        endcase
                        if (mem_read_last) begin
                            ic_valid[i_pending_index] <= 1'b1;
                            ic_tag[i_pending_index] <= i_pending_tag;
                            case (i_pending_word)
                                2'd0: core_inst_rdata <= (beat_count == 2'd0) ? mem_read_data : fill0;
                                2'd1: core_inst_rdata <= (beat_count == 2'd1) ? mem_read_data : fill1;
                                2'd2: core_inst_rdata <= (beat_count == 2'd2) ? mem_read_data : fill2;
                                2'd3: core_inst_rdata <= mem_read_data;
                            endcase
                            i_pending <= 1'b0;
                            service <= S_IDLE;
                        end else begin
                            beat_count <= beat_count + 2'd1;
                        end
                    end
                    S_I_UNC: if (mem_read_last) begin
                        core_inst_rdata <= mem_read_data;
                        i_pending <= 1'b0;
                        service <= S_IDLE;
                    end
                    S_D_FILL: begin
                        case (beat_count)
                            2'd0: begin fill0 <= mem_read_data; dc_w0[d_pending_index] <= mem_read_data; end
                            2'd1: begin fill1 <= mem_read_data; dc_w1[d_pending_index] <= mem_read_data; end
                            2'd2: begin fill2 <= mem_read_data; dc_w2[d_pending_index] <= mem_read_data; end
                            2'd3: begin fill3 <= mem_read_data; dc_w3[d_pending_index] <= mem_read_data; end
                        endcase
                        if (mem_read_last) begin
                            dc_valid[d_pending_index] <= 1'b1;
                            dc_tag[d_pending_index] <= d_pending_tag;
                            case (d_pending_word)
                                2'd0: core_data_rdata <= (beat_count == 2'd0) ? mem_read_data : fill0;
                                2'd1: core_data_rdata <= (beat_count == 2'd1) ? mem_read_data : fill1;
                                2'd2: core_data_rdata <= (beat_count == 2'd2) ? mem_read_data : fill2;
                                2'd3: core_data_rdata <= mem_read_data;
                            endcase
                            d_pending <= 1'b0;
                            service <= S_IDLE;
                        end else begin
                            beat_count <= beat_count + 2'd1;
                        end
                    end
                    S_D_UNC: if (mem_read_last) begin
                        core_data_rdata <= mem_read_data;
                        d_pending <= 1'b0;
                        service <= S_IDLE;
                    end
                    default: begin end
                endcase
            end

            if (mem_write_done && service == S_D_WRITE) begin
                d_pending <= 1'b0;
                service <= S_IDLE;
            end
        end
    end
endmodule
