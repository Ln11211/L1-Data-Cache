`timescale 1ns / 1ps
module cache_dm(data,req,rst,clk,wsel,addr,we,oe);
  localparam ADDR_BITS = 16;
  localparam OFFSET_BITS = 6;   // 64B line
  localparam INDEX_BITS = 7;   // 8KB / 64B = 128 lines in total
  localparam TAG_BITS = ADDR_BITS - INDEX_BITS - OFFSET_BITS; //which is 3 bits for tag
  localparam LINES = 128;

  inout [31:0] data;
  input [ADDR_BITS-1:0] addr;
  input [3:0] wsel;
  input we, clk, oe, rst, req;

  reg [7:0] mem  [0:LINES-1][0:63];
  reg [TAG_BITS-1:0] tags  [0:LINES-1];
  reg valid [0:LINES-1];
  reg dirty [0:LINES-1];

  reg [INDEX_BITS-1:0] m_idx;
  reg [TAG_BITS-1:0]   m_tag_old, m_tag_new;
  reg wb_start, ld_start;  
  reg wb_armed;
  reg [31:0] tmp;
  wire [INDEX_BITS-1:0] index = addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
  wire [OFFSET_BITS-1:0] offset = addr[OFFSET_BITS-1:0];
  wire [TAG_BITS-1:0] tag = addr[ADDR_BITS-1 : ADDR_BITS - TAG_BITS];
  reg mem_req; 
  reg mem_wr;    
  reg [ADDR_BITS-1:0]  mem_addr;  
  reg [63:0] mem_wdata_reg;
  wire mem_ready;  
  wire mem_rvalid; 
  wire [63:0] mem_rdata;
  integer i,j;

  mem64_bram_ip #(.ADDR_BITS(ADDR_BITS)) u_mem (
    .clk(clk), .rst(rst),
    .req(mem_req), .wr(mem_wr),
    .addr(mem_addr), .wdata(mem_wdata_reg),
    .ready(mem_ready), .rvalid(mem_rvalid), .rdata(mem_rdata)
  );

  reg [2:0]  beat;
  wire       last_beat = (beat == 3'd7);
  reg [1:0]  next_state, curr_state;
  localparam IDLE=2'b00, WRITEBACK=2'b01, LOAD=2'b10, SERVE=2'b11;

  // check if hit or not based on index
  wire hit = valid[index%LINES] && (tags[index%LINES] == tag);

  function [63:0] pack_line(input [INDEX_BITS-1:0] idx, input [2:0] beat_i);
    reg [63:0] tmp64; integer bb;
    begin
      tmp64 = 64'd0;
      for (bb = 0; bb < 8; bb = bb + 1)
        tmp64[8*bb +: 8] = mem[idx][beat_i*8 + bb];
      pack_line = tmp64;
    end
  endfunction

  task write_line(input [INDEX_BITS-1:0] idx, input [2:0] beat_i, input [63:0] din);
    integer bb;
    begin
      for (bb = 0; bb < 8; bb = bb + 1)
        mem[idx%LINES][beat_i*8 + bb] <= din[8*bb +: 8];
    end
  endtask

  always @(posedge rst) begin
    for (i = 0; i < LINES; i = i + 1) begin
      for (j = 0; j < 64; j = j + 1) mem[i][j] <= 8'h00;
      valid[i] <= 1'b0;
      dirty[i] <= 1'b0;
      tags[i]  <= {TAG_BITS{1'b0}};
    end
    beat <= 3'd0;
    mem_req <= 1'b0;
    mem_wr <= 1'b0;
    mem_addr <= {ADDR_BITS{1'b0}};
    mem_wdata_reg <= 64'd0;
    next_state <= IDLE;
    tmp <= 32'd0;
    wb_start <= 1'b0;
    ld_start <= 1'b0;
    wb_armed <= 1'b0;
  end

  always @(posedge clk or posedge rst) begin
    if (rst) curr_state <= IDLE;
    else curr_state <= next_state;
  end

  always @(posedge clk) begin
    case (curr_state)
      IDLE: begin
        mem_req  <= 1'b0;
        if (req) begin
          if (hit) begin
            if (we) begin
              // write hit 
              if (wsel[0]) mem[index%LINES][offset+0] <= data[7:0];
              if (wsel[1]) mem[index%LINES][offset+1] <= data[15:8];
              if (wsel[2]) mem[index%LINES][offset+2] <= data[23:16];
              if (wsel[3]) mem[index%LINES][offset+3] <= data[31:24];
              dirty[index%LINES] <= 1'b1;
              valid[index%LINES] <= 1'b1;
              next_state <= IDLE;
            end else begin
              // read hit
              if (valid[index%LINES]) begin
                tmp <= { mem[index%LINES][offset+3], mem[index%LINES][offset+2],
                         mem[index%LINES][offset+1], mem[index%LINES][offset+0] };
              end
              next_state <= SERVE;
            end
          end else begin
            //$display("[%0t] it was a miss, execution came here tag=%0h idx=%0d, offset=%0d-> %s",
                     //$time, tag, index, offset, (valid[index%LINES]&&dirty[index%LINES])?"  WB":" LOAD");
            m_idx <= index;
            m_tag_old <= tags[index%LINES];
            m_tag_new <= tag;
            valid[index%LINES] <= 1'b0;     //marking the line dirty
            beat <= 3'd0;
            if (valid[index%LINES] && dirty[index%LINES]) begin
              wb_start <= 1'b1;     
              ld_start <= 1'b0;
              mem_wr <= 1'b1;
              next_state <= WRITEBACK;
            end else begin
              wb_start <= 1'b0;
              ld_start <= 1'b1;    
              mem_wr <= 1'b0;
              next_state <= LOAD;
            end
          end
        end
      end

      WRITEBACK: begin
        if (wb_start) begin
          wb_start <= 1'b0;
          wb_armed <= 1'b1;                           
          beat <= 3'd0;
          mem_wdata_reg <= pack_line(m_idx, 3'd0);         
          mem_addr <= { m_tag_old, m_idx, {OFFSET_BITS{1'b0}} };
          mem_wr  <= 1'b1;

        end else if (wb_armed) begin
          wb_armed <= 1'b0;
          mem_req <= 1'b1;                                

        end else if (mem_req && mem_ready) begin
          if (last_beat) begin
            mem_req <= 1'b0;      
            dirty[m_idx] <= 1'b0;
            ld_start <= 1'b1;      
            next_state <= LOAD;
            beat <= 3'd0;
          end else begin
            beat <= beat + 3'd1;
            mem_wdata_reg <= pack_line(m_idx, beat + 3'd1); 
          end
        end
      end

      LOAD: begin
        if (!mem_req && ld_start) begin
          mem_wr <= 1'b0;
          mem_addr <= { m_tag_new, m_idx, {OFFSET_BITS{1'b0}} };
          mem_req <= 1'b1;
          beat <= 3'd0;
          ld_start <= 1'b0;
        end else begin
          if (mem_rvalid && mem_req) begin
            write_line(m_idx, beat, mem_rdata);
            if (last_beat) begin
              mem_req <= 1'b0;
              tags[m_idx] <= m_tag_new;
              valid[m_idx] <= 1'b1;
              dirty[m_idx] <= 1'b0;
              next_state <= IDLE;
              beat <= 3'd0;
            end else begin
              beat <= beat + 3'd1;
            end
          end
        end
      end

      SERVE: begin
        mem_req <= 1'b0;
        next_state <= IDLE;
      end

      default: begin
        mem_req <= 1'b0;
        next_state <= IDLE;
      end
    endcase
  end
assign data = (oe & !we) ? tmp : 32'bz;
endmodule