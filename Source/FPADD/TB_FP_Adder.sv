`timescale 1ns/1ps // unit/precision
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// FPAdder testbench
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module Testbench_FPAdder #(
  parameter LOGWIDTH = 5
  )(); 
  
  logic                         clk, reset;
  
  logic [ 2**LOGWIDTH - 1 : 0 ] a,b;
  logic [ 2**LOGWIDTH - 1 : 0 ] y, yexpected;
  logic                         add_n;
  
  logic [ 31 : 0 ]              vectornum, errors;
  
  logic [  2 : 0 ]              tr;
  
  logic [ 2**LOGWIDTH*3 + 4 -1 :0] testvectors[10000:0];
  
  // instantiate under test
  FPAdder #( // 32 bit IEEE754 floating point adder LITTLE-ENDIAN/BIG-ENDIAN - to check initial schemes
   .LOGWIDTH(5), .EXPWIDTH(8), .MANTWIDTH(23) // 32-bit IEEE754, 64-bit IEEE754 is #(6, 11, 52)
  ) dut (
    .diA      (     a ),
    .diB      (     b ),
              
    .ciADD_n  ( add_n ),
              
    .doY      (     y )
  );
  
  // generate clock  
  always
    begin
      clk=1; #5; clk=0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/FPADD/test.tv",testvectors); // Format: hhhhhhhh_hhhhhhhh_b_hhhhhhhh
      vectornum = 0; errors = 0;
      reset = 1; #27; reset=0;
    end 
  
  // apply test vectors on rising edge of clk
  always@(posedge clk)
  begin
      #1; { a, b, tr[2:0], add_n, yexpected } = testvectors[ vectornum ];
  end
  
  // check at falling edge of clk
  always@(negedge clk)
    if(~reset) begin // skip during reset
      if(yexpected != y) begin
        $display("Error: vectornum %d", vectornum );
        $display(" inputs = %h, %h, %d", a, b, add_n );
        $display(" outputs = %h (%h expected)", y, yexpected );
        errors += 1;
      end
      vectornum += 1;
      if(testvectors[vectornum][0] === 1'bx) begin
        $display("%d tests complete with %d errors", vectornum, errors);
        $finish;
      end
    end
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// CVT converter testbench
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module Testbench_FP_CVT #(
  parameter LOGWIDTH = 5
  )(); 
  
  logic                         clk, reset;
  
  logic [ 2**LOGWIDTH - 1 : 0 ] a;
  logic [ 2**LOGWIDTH - 1 : 0 ] y, yexpected;
  logic                         NAN, NAN_ex;
  logic                         INF, INF_ex;
  logic                         cWay, cENA;
  
  logic [ 31 : 0 ]              vectornum, errors;
  
  logic [ 11 : 0 ]              tr;
  
  logic [ 2**LOGWIDTH*3 + 4 -1 :0] testvectors[10000:0];
  
  // instantiate under test
   CVT_FP #(5,8,23) dut (
  .diA      (     a ),
  .ciWay    (  cWay ), // 0 for word-to-float
  .ciENA    (  cENA ),
  .doY      (     y ),
  .doNAN    (   NAN ),
  .doINF    (   INF )
  );

  // generate clock  
  always
    begin
      clk=1; #5; clk=0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/FPADD/CVT.tv",testvectors); // Format:
      vectornum = 0; errors = 0;
      reset = 1; #27; reset=0;
    end 
  
  // apply test vectors on rising edge of clk
  always@(posedge clk)
  begin
      // format: hhhhhhhh_b_b_yyyyyyyy_b_b
      #1; { a, tr[11:9], cWay, tr[8:6], cENA, yexpected, tr[5:3], NAN_ex, tr[2:0], INF_ex } = testvectors[ vectornum ];
  end
  
  // check at falling edge of clk
  always@(negedge clk)
    if(~reset) begin // skip during reset
      if( ( yexpected != y) || ( NAN_ex != NAN ) || ( INF_ex != INF ) ) begin
        $display("Error: vectornum %d", vectornum );
        if(cWay) begin // float to word
          $display(" inputs = %h, %b, %b", a, cWay, cENA );
          $display(" outputs, NAN INF = %b %b (%b %b expected)", NAN, INF, NAN_ex, INF_ex );
          $display(" outputs, hex     = %h (%h expected)", y, yexpected );
          $display(" outputs, decimal = %d (%d expected)", y, yexpected );
        end else begin
          $display(" inputs = %h(%d), %b, %b", a, a, cWay, cENA );
          $display(" outputs, NAN INF = %b %b (%b %b expected)", NAN, INF, NAN_ex, INF_ex );
          $display(" outputs, hex     = %h (%h expected)", y, yexpected );
          $display(" outputs, decimal = %f (%f expected)", y, yexpected );    
        end
        errors += 1;
      end
      vectornum += 1;
      if(testvectors[vectornum][7:0] === 8'hxx) begin
        $display("%d tests complete with %d errors", vectornum, errors);
        $finish;
      end
    end
endmodule
