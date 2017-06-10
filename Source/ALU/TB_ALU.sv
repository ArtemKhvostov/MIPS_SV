`timescale 1ns/1ps // unit/precision
///////////////////////////////////////////////
//-
///////////////////////////////////////////////
module Testbench_ALU #(
  parameter LOGWIDTH = 5    //32-bit
  )();
  logic                        clk, reset;
  
  logic [2**LOGWIDTH - 1 : 0]  dA, dB, dS, dSexpected;
  logic [2:0]                  cF, cS, cSexpected;
  
  logic [ 31 : 0 ]             vectornum, errors;
  logic [ ( 3 * ( 2**LOGWIDTH ) ) + 4*3 + 4*3 - 1 : 0 ] testvectors[ 10000 : 0 ]; // dA, dB, cF, dSexpected, cSexpected
  
  logic [17:0]                 tr;
  
  // instantiate under test
  ALU #( 
    .LOGWIDTH ( LOGWIDTH   ) 
  ) dut ( 
    .A        ( dA         ),
    .B        ( dB         ),
    
    .F        ( cF         ),
    
    .Y        ( dS         ),
    
    .Cout     ( cS[2]      ), 
    .Oflow    ( cS[1]      ),
    .Zero     ( cS[0]      )
  );
  // generate clock
  always
    begin
      clk = 1; #5; clk = 0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/ALU/test_ALU.tv",testvectors);
      vectornum = 0; errors = 0;
      reset = 1; #27; reset = 0;
    end 
  
  // apply test vectors on rising edge of clk
  always@(posedge clk)
    begin
      #1; { dA, dB,
              tr[2:0], cF[2],
              tr[5:3], cF[1],
              tr[8:6], cF[0],
              dSexpected,
              tr[11:9 ], cSexpected[2],
              tr[14:12], cSexpected[1],
              tr[17:15], cSexpected[0] } = testvectors[ vectornum ]; // format hhhhhhhh_hhhhhhhh_bbb_hhhhhhhh_bbb
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( ~reset ) begin // skip during reset
      if( dSexpected != dS ) begin
        $display( "Error: inputs = %h, %h, %b", dA, dB, cF );
        $display( " outputs = %h (%h expected) ( %b and %b )", dS, dSexpected, dS, dSexpected );
        errors += 1;
      end
      if( cSexpected != cS ) begin
        $display( "Error: inputs = %h, %h, %b", dA, dB, cF );
        $display( " outputs = %b (%b expected)", cS, cSexpected );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
        $display( "%d tests complete with %d errors", vectornum, errors );
        $finish;
      end
    end
    
endmodule