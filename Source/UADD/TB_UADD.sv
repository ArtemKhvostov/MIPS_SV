`timescale 1ns/1ps // unit/precision
/////////////////////////////////////////////////////
module Testbench_UnsignedAdders #(
  parameter LOGWIDTH = 5
  )();
  logic clk, reset;
  logic Cin;
  logic [ 2**LOGWIDTH - 1:0]           a,b;
  logic [ 2**LOGWIDTH - 1:0]           y_SP, y_RCA, y_ISP, yexpected, y_Inc_expected;
  logic                                overflow_SP, overflow_RCA, overflow_ISP, ofexpected;
  logic [31:0]                         vectornum, errors;
  logic [ 2**LOGWIDTH*3 - 1 + 2 * 4:0] testvectors[10000:0]; //[2**LOGWIDTH*3-1:0] testvectors[10000:0]; 
  logic [5:0]                          Garbage;
  
  // instantiate under test
  sum_prefix  #(LOGWIDTH) dutSP(  .Cin(Cin),  .A(a),  .B(b),  .S(y_SP),  .Cout(overflow_SP)  );
  RCAdder     #(LOGWIDTH) dutRCA( .Cin(Cin),  .A(a),  .B(b),  .S(y_RCA), .Cout(overflow_RCA) );
  inc_prefix  #(LOGWIDTH) dutISP(             .A(b),          .S(y_ISP), .Cout(overflow_ISP) );
  
  // generate clock
  always
    begin
      clk=1; #5; clk=0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/UADD/test_UADD.tv",testvectors);
      vectornum = 0; errors = 0;
      reset = 1; #27; reset=0;
    end 
  
  // apply test vectors on rising edge of clk
  always @( posedge clk )
    begin
      //#1; { Cin, a, b, yexpected} = testvectors[vectornum];//string format:hhhhhhhh_hhhhhhhh_hhhhhhhh
      #1; { Garbage[2:0], Cin, a, b, yexpected, Garbage[5:3], ofexpected } = testvectors[vectornum];//string format:h_hhhhhhhh_hhhhhhhh_hhhhhhhh_h
      y_Inc_expected = b+1;
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( !reset ) begin // skip during reset
      if( yexpected != y_SP ) begin
        $display( "Error_SumPrefix: inputs = %h,%h", a, b );
        $display( " outputs = %h (%h expected)", y_SP, yexpected );
        errors += 1;
      end
      if( ofexpected != overflow_SP ) begin
        $display( "Error_SumPrefix: inputs = %d,%d", a, b );
        $display( " outputs_overflow = %d (%d expected)", overflow_SP, ofexpected );
        errors += 1;
      end
      if( yexpected != y_RCA ) begin
        $display( "Error_RCA: inputs = %h,%h", a, b );
        $display( " outputs = %h (%h expected)", y_RCA, yexpected );
        errors += 1;
      end
      if( y_Inc_expected != y_ISP ) begin
        $display( "Error_ISP: input = %h", a );
        $display( " outputs = %h (%h expected)", y_ISP, y_Inc_expected );
        errors += 1;
      end
      if( ofexpected != overflow_RCA ) begin
        $display( "Error_RCA: inputs = %d,%d", a, b );
        $display( " outputs_overflow = %d (%d expected)", overflow_RCA, ofexpected );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[vectornum][0] === 1'bx ) begin
        $display( "%d tests complete with %d errors", vectornum, errors );
        $finish;
      end
    end
    
endmodule
