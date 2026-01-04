`timescale 1ns/1ps
module mem64_bram_ip #(
  parameter ADDR_BITS = 16   // 64KB byte-addressed space
)(
  input  wire                 clk,
  input  wire                 rst,
  input  wire                 req,        // keep high during burst
  input  wire                 wr,         // 1 = writeback burst, 0 = fill burst
  input  wire [ADDR_BITS-1:0] addr,       // line-aligned (offset[5:0] = 0)
  input  wire [63:0]          wdata,      // write beat data
  output reg                  ready,      // 1 pulse per write beat
  output reg                  rvalid,     // 1 pulse per read beat
  output reg  [63:0]          rdata       // read beat data
);
  localparam OFFSET_BITS    = 6;                     // 64 B line
  localparam BRAM_ADDR_BITS = ADDR_BITS - 3;         // 64-bit word address

  // burst bookkeeping
  reg                 in_burst;
  reg [2:0]           beat;
  reg [ADDR_BITS-1:0] base;                          // latched line base
  reg                 mode_wr;                       // latched wr for entire burst

  // BRAM control signals
  reg                 ena, enb;
  reg  [7:0]          wea;
  reg  [BRAM_ADDR_BITS-1:0] addra, addrb;
  reg  [63:0]         dina;
  wire [63:0]         doutb;

  // Calculate word address for current beat
  wire [BRAM_ADDR_BITS-1:0] word_addr = base[ADDR_BITS-1:3] + beat;

  // Generated IP (use your instance name)
  blk_mem_gen_0 u_bram (
    .clka  (clk),
    .ena   (ena),
    .wea   (wea),
    .addra (addra),
    .dina  (dina),

    .clkb  (clk),
    .enb   (enb),
    .addrb (addrb),
    .doutb (doutb)
  );

  always @(posedge clk) begin
    if (rst) begin
      ready    <= 1'b0;
      rvalid   <= 1'b0;
      rdata    <= 64'd0;
      in_burst <= 1'b0;
      beat     <= 3'd0;
      base     <= {ADDR_BITS{1'b0}};
      mode_wr  <= 1'b0;
      ena      <= 1'b0;  enb <= 1'b0;  wea <= 8'h00;
      addra    <= {BRAM_ADDR_BITS{1'b0}};
      addrb    <= {BRAM_ADDR_BITS{1'b0}};
      dina     <= 64'd0;
    end else begin
      // defaults each cycle
      ready  <= 1'b0;
      rvalid <= 1'b0;
      ena    <= 1'b0;
      enb    <= 1'b0;
      wea    <= 8'h00;

      if (req) begin
        if (!in_burst) begin
          // Start of a new burst: latch base + mode, clear beat
          in_burst <= 1'b1;
          base     <= {addr[ADDR_BITS-1:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
          mode_wr  <= wr;             // latch write/read mode for entire burst
          beat     <= 3'd0;

          // No ready/rvalid this same cycle; first beat comes next cycle
        end else begin
          // In an active burst: emit one beat using latched mode
          if (mode_wr) begin
            // WRITE beat on Port A
            ena   <= 1'b1;
            wea   <= 8'hFF;           // write all 8 bytes
            addra <= word_addr;
            dina  <= wdata;
            ready <= 1'b1;
          end else begin
            // READ beat on Port B
            enb    <= 1'b1;
            addrb  <= word_addr;
            rdata  <= doutb;          // assume unregistered; adjust if IP is registered
            rvalid <= 1'b1;
          end

          if (beat == 3'd7) begin
            in_burst <= 1'b0;         // last beat this cycle
          end else begin
            beat <= beat + 3'd1;
          end
        end
      end else begin
        // req low: force idle
        in_burst <= 1'b0;
      end
    end
  end
endmodule