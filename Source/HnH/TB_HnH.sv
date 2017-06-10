`timescale 1ns/1ps // unit/precision
///////////////////////////////////////////////
//-
///////////////////////////////////////////////

module Testbench_PC #(
  parameter LOGWIDTH = 4
  )();
  logic clk, reset;
  
  logic Cin;
  logic [ 2**LOGWIDTH - 1 : 0]                 dut_a;
                                               
  logic [ LOGWIDTH - 1    : 0]                 dut_y, dut_y_expected;
  logic                                        dut_error, dut_error_expected;
  
  logic [ 31 : 0 ]                             vectornum, errors;
  logic [ 2**LOGWIDTH + LOGWIDTH + 1 - 1  : 0] testvectors[10000:0]; 
  //logic [5:0] Garbage;
  
  // instantiate under test
  priority_coder  #(LOGWIDTH) dut(  .di_a(dut_a), .do_y(dut_y), .co_err(dut_error)  );
  
  // generate clock
  always
    begin
      clk=1; #5; clk=0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial 
    begin
      $readmemb("../../Source/ALU/test_PC.tv",testvectors);
      vectornum = 0; errors = 0;
      reset = 1; #27; reset=0;
    end 
    
  // apply test vectors on rising edge of clk
  always @( posedge clk )
    begin
      #1; { dut_a, dut_y_expected, dut_error_expected } = testvectors[vectornum];//string format: bbbbbbbbbbbbbbbb_bbbb_b
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( !reset ) begin // skip during reset
      if( dut_y_expected != dut_y ) begin
        $display( "Error: inputs = %b", dut_a );
        $display( " outputs = %b (%b expected)", dut_y, dut_y_expected );
        errors += 1;
      end
      if( dut_error != dut_error_expected ) begin
        $display( "Error: inputs = %b", dut_a );
        $display( " outputs_error = %b (%b expected)", dut_error, dut_error_expected );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
        $display( "%d tests complete with %d errors", vectornum, errors );
        $finish;
      end
    end
    
endmodule

///////////////////////////////////////////////
//-
///////////////////////////////////////////////
module Testbench_NMUX #(
  parameter input_width = 4
  )();
  logic                                              clk, reset;
       
  logic [ 2**input_width - 1 : 0 ]                   dIn;
  logic [ input_width - 1    : 0 ]                   cSel;
       
  logic                                              y, yexpected;
  logic [ 31 : 0 ]                                   vectornum, errors;
  
  logic [ 2**input_width + input_width + 1 - 1 : 0 ] testvectors[10000:0]; // Total width = input_width + 1 for yexprcted
  
  // instantiate under test
  N_MUX   #input_width  dut ( .In(dIn), .Sel(cSel), .Out(y) );
  
  // generate clock
  always
    begin
      clk = 1; #5; clk = 0; #5;
    end
  // at start, load vectors and pulse reset
  
  initial
    begin
      $readmemb( "../../Source/ALU/test_MUX.tv", testvectors );
      vectornum = 0; errors = 0;
      reset = 1; #27; reset = 0;
    end 
  
  // apply test vectors on rising edge of clk
  always @( posedge clk )
    begin
      #1; { dIn, cSel, yexpected } = testvectors[ vectornum ]; //string format: bbbbbbbbbbbbbbbb_bbbb_b
    end
    
  // check at falling edge of clk
  always @( negedge clk )
    if( ~reset ) begin // skip during reset
      if( yexpected != y ) begin
        $display( "Error: inputs = %b, %d", dIn, cSel );
        $display( " outputs = %b (%b expected)", y, yexpected );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
        $display( "%d tests complete with %d errors", vectornum, errors );
        $finish;
      end
    end
    
endmodule

///////////////////////////////////////////////
//-
///////////////////////////////////////////////
module Testbench_Comps #(
  parameter LOGWIDTH = 4
  )();
  logic clk, reset;
  
  logic [ 2**LOGWIDTH - 1 : 0 ]                       dut_a, dut_b;
  logic [ 2 : 0 ]                                     y, yexpected;
  logic [ 31 : 0 ]                                    vectornum, errors;
  logic [ 2**LOGWIDTH + 2**LOGWIDTH + 3 * 4 - 1 :0 ]  testvectors[ 10000 : 0 ];
  logic [ 8 : 0 ]                                     G;                          // garbage
  
  // instantiate under test
  comparators   #LOGWIDTH dut ( .A(dut_a),  .B(dut_b),  .ne( y[2] ),  .le( y[1] ),  .mo( y[0] ) );
  
  // generate clock
  always
    begin
      clk = 1; #5; clk = 0; #5;
    end
    
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/ALU/test_Comps.tv",testvectors);
      vectornum = 0; errors = 0;
      reset = 1; #27; reset = 0;
    end 
    
  // apply test vectors on rising edge of clk
  always @( posedge clk )
    begin
      #1; { dut_a, dut_b, G[ 8 : 6 ], yexpected[ 2 ], G[ 5 : 3 ], yexpected[ 1 ], G[ 2 : 0 ], yexpected[ 0 ] } = testvectors[ vectornum ]; // format: hhhh_hhhh_bbb ( a_b_ne.le.mo )
    end
    
  // check at falling edge of clk
  always @( negedge clk )
    if( ~reset ) begin // skip during reset
      if( yexpected != y ) begin
        $display( "Error: inputs = %h, %h", dut_a, dut_b );
        $display( " outputs = %b (%b expected)", y, yexpected );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
        $display( "%d tests complete with %d errors", vectornum, errors );
        $finish;
      end
    end
    
endmodule
