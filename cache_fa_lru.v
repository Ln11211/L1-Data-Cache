`timescale 1ns/1ps
module cache_fa_lru(
  inout  [31:0] data,
  input  [15:0] addr,
  input  [3:0]  wsel,
  input we, clk, oe, rst, req
);
  localparam ADDR_BITS   = 16;
  localparam OFFSET_BITS = 6;
  localparam LINE_BYTES  = 64;
  localparam LINES = 128;
  localparam TAG_BITS = ADDR_BITS - OFFSET_BITS;

  reg [31:0] tmp;
  reg [7:0]  mem [0:LINES-1][0:LINE_BYTES-1];
  reg [TAG_BITS-1:0] tags [0:LINES-1];
  reg [ADDR_BITS-1:0] base [0:LINES-1];
  reg valid [0:LINES-1];
  reg dirty [0:LINES-1];
  reg [15:0] age [0:LINES-1];
  reg [15:0] time_ctr;
  wire [OFFSET_BITS-1:0] off_w  = addr[OFFSET_BITS-1:0];
  wire [TAG_BITS-1:0] tag_w  = addr[ADDR_BITS-1:OFFSET_BITS];
  wire [ADDR_BITS-1:0] base_w = {addr[ADDR_BITS-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
  reg mem_req;
  reg mem_wr;
  reg [ADDR_BITS-1:0] mem_addr;
  reg [63:0] mem_wdata_reg;
  wire mem_ready;
  wire mem_rvalid;
  wire [63:0] mem_rdata;

  mem64_bram_ip #(.ADDR_BITS(ADDR_BITS)) u_mem (
    .clk   (clk),
    .rst   (rst),
    .req   (mem_req),
    .wr    (mem_wr),
    .addr  (mem_addr),
    .wdata (mem_wdata_reg),
    .ready (mem_ready),
    .rvalid(mem_rvalid),
    .rdata (mem_rdata)
  );

  function [63:0] pack_line(input integer way, input [2:0] beat_i);
    integer b; reg [63:0] t;
    begin
      t = 64'd0;
      for (b=0;b<8;b=b+1) t[8*b +: 8] = mem[way][beat_i*8 + b];
      pack_line = t;
    end
  endfunction

  task write_line(input integer way, input [2:0] beat_i, input [63:0] din);
    integer b;
    begin
      for (b=0;b<8;b=b+1) mem[way][beat_i*8 + b] <= din[8*b +: 8];
    end
  endtask

  reg hit;
  reg [6:0] hit_way;
  integer  w;
  always @* begin
    hit = 1'b0;
    hit_way = 7'd0;
    for (w=0; w<LINES; w=w+1) begin
      if (!hit && valid[w] && (tags[w] == tag_w)) begin
        hit = 1'b1;
        hit_way = w[6:0];
      end
    end
  end

  reg  inv_found;
  reg [6:0] inv_way;
  integer k;
  always @* begin
    inv_found = 1'b0;
    inv_way   = 7'd0;
    for (k=0; k<LINES; k=k+1) begin
      if (!inv_found && !valid[k]) begin
        inv_found = 1'b1;
        inv_way   = k[6:0];
      end
    end
  end

  reg [TAG_BITS-1:0] m_tag;
  reg [ADDR_BITS-1:0]m_base;
  reg [5:0]  m_off;
  reg m_is_write;
  reg [3:0] m_wsel;
  reg [31:0] m_wdata;
  reg [6:0] vict;
  reg [2:0] beat;
  wire last_beat = (beat==3'd7);
  reg [1:0] state, nstate;
  localparam IDLE=2'b00, WB=2'b01, LD=2'b10, SERVE=2'b11;

  integer i,j;
  always @(posedge rst) begin
    for (i=0;i<LINES;i=i+1) begin
      valid[i] <= 1'b0;
      dirty[i] <= 1'b0;
      tags[i]  <= {TAG_BITS{1'b0}};
      base[i]  <= {ADDR_BITS{1'b0}};
      age[i]   <= 16'd0;
      for (j=0;j<LINE_BYTES;j=j+1) mem[i][j] <= 8'h00;
    end
    tmp  <= 32'd0;
    mem_req <= 1'b0;
    mem_wr <= 1'b0;
    mem_addr <= {ADDR_BITS{1'b0}};
    mem_wdata_reg <= 64'd0;
    beat <= 3'd0;
    vict <= 7'd0;
    m_tag <= {TAG_BITS{1'b0}};
    m_base <= {ADDR_BITS{1'b0}};
    m_off <= 6'd0;
    m_is_write <= 1'b0;
    m_wsel <= 4'b0;
    m_wdata <= 32'd0;
    time_ctr <= 16'd0;
    state<= IDLE; nstate <= IDLE;
  end

  always @(posedge clk or posedge rst) begin
    if (rst) state <= IDLE; else state <= nstate;
  end
  always @(posedge clk) begin
    nstate <= state;
    case (state)
      IDLE: begin
        mem_req <= 1'b0;
        if (req) begin
          if (hit) begin
            time_ctr <= time_ctr + 16'd1;
            if (we) begin
              if (wsel[0]) mem[hit_way][off_w+0] <= data[7:0];
              if (wsel[1]) mem[hit_way][off_w+1] <= data[15:8];
              if (wsel[2]) mem[hit_way][off_w+2] <= data[23:16];
              if (wsel[3]) mem[hit_way][off_w+3] <= data[31:24];
              dirty[hit_way] <= 1'b1;
              age[hit_way] <= time_ctr + 16'd1;
              nstate <= IDLE;
            end else begin
              tmp <= { mem[hit_way][off_w+3], mem[hit_way][off_w+2],
                                 mem[hit_way][off_w+1], mem[hit_way][off_w+0] };
              age[hit_way] <= time_ctr + 16'd1;
              nstate <= SERVE;
            end
          end else begin
            m_tag <= tag_w;
            m_base <= base_w;
            m_off <= off_w;
            m_is_write <= we;
            m_wsel <= wsel;
            m_wdata <= data;
            begin : pick_victim
              integer m;
              reg [6:0] lru_way;
              reg [15:0] lru_time;
              reg [6:0] chosen_v;
              if (inv_found) begin
                chosen_v = inv_way;
              end else begin
                lru_way  = 7'd0;
                lru_time = 16'hFFFF;
                for (m=0; m<LINES; m=m+1) begin
                  if (valid[m]) begin
                    if (age[m] < lru_time) begin
                      lru_time = age[m];
                      lru_way  = m[6:0];
                    end
                  end
                end
                chosen_v = lru_way;
              end
              vict <= chosen_v;
              beat <= 3'd0;
              if (!inv_found && valid[chosen_v] && dirty[chosen_v]) begin
                mem_wr <= 1'b1;
                mem_addr <= base[chosen_v];
                mem_wdata_reg <= pack_line(chosen_v, 3'd0);
                mem_req <= 1'b1;
                nstate <= WB;
              end else begin
                mem_wr <= 1'b0;
                mem_addr<= base_w;
                mem_req <= 1'b1;
                nstate <= LD;
              end
            end
          end
        end
      end
      WB: begin
        if (mem_req && mem_ready) begin
          if (last_beat) begin
            mem_req <= 1'b0;
            dirty[vict] <= 1'b0;
            beat <= 3'd0;
            mem_wr <= 1'b0;
            mem_addr <= m_base;
            mem_req <= 1'b1;
            nstate <= LD;
          end else begin
            beat <= beat + 3'd1;
            mem_wdata_reg <= pack_line(vict, beat + 3'd1);
          end
        end
      end
      LD: begin
        if (mem_req && mem_rvalid) begin
          write_line(vict, beat, mem_rdata);
          if (last_beat) begin
            mem_req <= 1'b0;
            tags[vict] <= m_tag;
            base[vict] <= m_base;
            valid[vict] <= 1'b1;
            dirty[vict] <= 1'b0;
            beat <= 3'd0;
            time_ctr <= time_ctr + 16'd1;
            age[vict] <= time_ctr + 16'd1;
            if (!m_is_write) begin
              tmp <= { mem[vict][m_off+3], mem[vict][m_off+2],
                          mem[vict][m_off+1], mem[vict][m_off+0] };
              nstate <= SERVE;
            end else begin
              if (m_wsel[0]) mem[vict][m_off+0] <= m_wdata[7:0];
              if (m_wsel[1]) mem[vict][m_off+1] <= m_wdata[15:8];
              if (m_wsel[2]) mem[vict][m_off+2] <= m_wdata[23:16];
              if (m_wsel[3]) mem[vict][m_off+3] <= m_wdata[31:24];
              dirty[vict] <= 1'b1;
              time_ctr <= time_ctr + 16'd1;
              age[vict] <= time_ctr + 16'd1;
              nstate <= IDLE;
            end
          end else begin
            beat <= beat + 3'd1;
          end
        end
      end
      SERVE: begin
        nstate <= IDLE;
      end
      default: nstate <= IDLE;
    endcase
  end
    assign data = (oe & !we) ? tmp : 32'bz;
endmodule