`timescale 1ns/1ps
module cache_tb_lru;

  localparam ADDR_BITS = 16;
  localparam N = 128;
  localparam WORD_BYTES = 4;
  localparam BASE = 16'h0000;
  localparam LINE_BYTES   = 64;
  localparam LINES = 128;
  localparam BEAT_BYTES = 8;
  localparam CACHE_SIZE_BYTES = LINES * LINE_BYTES; 
  localparam MAIN_SIZE_BYTES  = (1 << ADDR_BITS); 

  reg clk = 0; always #5 clk = ~clk; 
  reg rst;
  wire [31:0] data_bus;
  reg drive_en;
  reg  [31:0] data_drv;
  reg req, we, oe;
  reg [3:0] wsel;
  reg [ADDR_BITS-1:0]  addr;
  assign data_bus = drive_en ? data_drv : 32'bz;

  cache_fa_lru dut (
    .data (data_bus),
    .req  (req),
    .rst  (rst),
    .clk  (clk),
    .wsel (wsel),
    .addr (addr),
    .we   (we),
    .oe   (oe)
  );

  integer access_cnt;
  integer miss_cnt;
  integer wb_cnt;
  integer rd_ops, wr_ops;
  integer beat_read_cnt;
  integer beat_write_cnt;
  reg mem_req_q, mem_wr_q;
  reg in_load, in_wb;

  always @(posedge clk) begin
    if (mem_req_q === 1'b0 && dut.mem_req === 1'b1) begin
      if (dut.mem_wr === 1'b0) in_load <= 1'b1;
      else in_wb   <= 1'b1;
    end
    if (in_load && dut.u_mem.rvalid === 1'b1) begin
      miss_cnt <= miss_cnt + 1;
      in_load  <= 1'b0;
    end
    if (in_wb && dut.u_mem.ready === 1'b1) begin
      wb_cnt <= wb_cnt + 1;
      in_wb  <= 1'b0;
    end
    if (dut.mem_req === 1'b0) begin
      in_load <= 1'b0;
      in_wb   <= 1'b0;
    end
    if (dut.u_mem.rvalid === 1'b1) beat_read_cnt  <= beat_read_cnt  + 1;
    if (dut.u_mem.ready  === 1'b1) beat_write_cnt <= beat_write_cnt + 1;
    mem_req_q <= dut.mem_req;
    mem_wr_q  <= dut.mem_wr;
  end

  function [ADDR_BITS-1:0] addr_of;
    input integer i;
    input integer j;
    integer linear;
    begin
      linear  = i*N + j;
      addr_of = BASE + (linear << 2);
    end
  endfunction

  task wait_burst_done;
    integer guard;
    reg seen_high;
    begin
      seen_high = 1'b0;
      guard = 0;
      while (dut.mem_req !== 1'b1 && guard < 2000) begin
        @(negedge clk);
        guard = guard + 1;
      end
      if (dut.mem_req === 1'b1) seen_high = 1'b1;
      guard = 0;
      while (seen_high && dut.mem_req === 1'b1 && guard < 20000) begin
        @(negedge clk);
        guard = guard + 1;
      end
      repeat (2) @(negedge clk);
    end
  endtask

  task cpu_write32;
    input [ADDR_BITS-1:0] A;
    input [31:0] W;
    input [3:0] STRB;
    begin
      wr_ops <= wr_ops + 1;
      access_cnt <= access_cnt + 1;
      @(negedge clk);
      addr <= A;
      wsel <= STRB;
      data_drv <= W;
      drive_en <= 1'b1;
      we <= 1'b1;  oe <= 1'b0;  req <= 1'b1;
      @(posedge clk);
      @(negedge clk) begin req <= 1'b0; drive_en <= 1'b0; end
      wait_burst_done();
    end
  endtask

  task cpu_read32;
    input [ADDR_BITS-1:0] A;
    output [31:0] R;
    begin
      rd_ops <= rd_ops + 1;
      access_cnt <= access_cnt + 1;
      @(negedge clk);
      addr <= A;
      wsel <= 4'b0000;
      drive_en <= 1'b0;
      we <= 1'b0;  oe <= 1'b1;  req <= 1'b1;
      @(posedge clk);
      @(negedge clk) req <= 1'b0;
      wait_burst_done();
      @(negedge clk);
      addr <= A;
      we <= 1'b0;  oe <= 1'b1;  req <= 1'b1;
      @(posedge clk);
      R = data_bus;
      @(negedge clk) begin req <= 1'b0; oe <= 1'b0; end
    end
  endtask

  task reset_dut;
    begin
      req=0; we=0; oe=0; wsel=4'b0; addr={ADDR_BITS{1'b0}};
      drive_en=0; data_drv=32'h0;
      rst = 0; #2; rst = 1; #10; rst = 0;
      repeat (5) @(negedge clk);
    end
  endtask

  task reset_counters;
    begin
      access_cnt=0; miss_cnt=0; wb_cnt=0; rd_ops=0; wr_ops=0;
      beat_read_cnt=0; beat_write_cnt=0;
      mem_req_q=1'b0; mem_wr_q=1'b0; in_load=1'b0; in_wb=1'b0;
    end
  endtask

  integer i, j;
  reg [31:0] val;
  integer c_access, c_miss, c_hits;
  integer c_rd_ops, c_wr_ops;
  integer c_rd_beats, c_wb_beats;
  integer r_access, r_miss, r_hits;
  integer r_rd_ops, r_wr_ops;
  integer r_rd_beats, r_wb_beats;

  task run_column_major;
    begin
      reset_counters();
      for (j=0;j<N;j=j+1) begin
        for (i=0;i<N;i=i+1) begin
          cpu_read32 (addr_of(i,j), val);
          cpu_write32(addr_of(i,j), {2*val}, 4'b1111);
        end
      end
      wait_burst_done(); repeat (4) @(negedge clk);
      c_access = access_cnt;
      c_miss = miss_cnt;
      c_hits = access_cnt - miss_cnt;
      c_rd_ops = rd_ops;
      c_wr_ops = wr_ops;
      c_rd_beats = beat_read_cnt;
      c_wb_beats = beat_write_cnt;
    end
  endtask

  task run_row_major;
    begin
      reset_counters();
      for (i=0;i<N;i=i+1) begin
        for (j=0;j<N;j=j+1) begin
          cpu_read32 (addr_of(i,j), val);
          cpu_write32(addr_of(i,j), {2*val}, 4'b1111);
        end
      end
      wait_burst_done(); repeat (4) @(negedge clk);
      r_access = access_cnt;
      r_miss = miss_cnt;
      r_hits = access_cnt - miss_cnt;
      r_rd_ops = rd_ops;
      r_wr_ops = wr_ops;
      r_rd_beats = beat_read_cnt;
      r_wb_beats = beat_write_cnt;
    end
  endtask

  task print_table;
    real c_hit_rate, r_hit_rate;
    integer c_bus_bytes, r_bus_bytes;
    begin
      c_hit_rate = (c_access>0) ? (100.0*(c_access - c_miss)/c_access) : 0.0;
      r_hit_rate = (r_access>0) ? (100.0*(r_access - r_miss)/r_access) : 0.0;
      c_bus_bytes = (c_rd_beats + c_wb_beats) * BEAT_BYTES;
      r_bus_bytes = (r_rd_beats + r_wb_beats) * BEAT_BYTES;
      $display("");
      $display("+-----------------------------------------------------------------------------+");
      $display("| Cache: %0d bytes (%0d KB) | Main Memory: %0d bytes (%0d KB)                 |",
               CACHE_SIZE_BYTES, CACHE_SIZE_BYTES>>10, MAIN_SIZE_BYTES, MAIN_SIZE_BYTES>>10);
      $display("+----------------+-----------+--------+--------+---------+--------------------+");
      $display("| Pattern        | Accesses  | Misses | Hits   | Hit %%  | Bus traffic (bytes)|");
      $display("+----------------+-----------+--------+--------+---------+--------------------+");
      $display("| Column-major   | %9d | %6d | %6d | %6.2f | %18d  |",
               c_access, c_miss, c_hits, c_hit_rate, c_bus_bytes);
      $display("| Row-major      | %9d | %6d | %6d | %6.2f | %18d  |",
               r_access, r_miss, r_hits, r_hit_rate, r_bus_bytes);
      $display("+----------------+-----------+--------+--------+---------+--------------------+");
      $display("");
    end
  endtask

  initial begin
    reset_dut();
    run_column_major();
    reset_dut();
    run_row_major();
    print_table();
    $finish;
  end
endmodule