`timescale 1ns/1ps // unit/precision

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline registers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module  PipelineReg #(
  parameter WIDTH = 1
  )(
  input  logic                clk,
  input  logic                rst,
  input  logic                clr,
  input  logic                EN,
  input  logic [ WIDTH-1 :0 ] dIn,
  output logic [ WIDTH-1 :0 ] dOut
);
  always_ff@( posedge clk or posedge rst )
  begin
    if( rst )
    begin
      dOut  <= 0;
    end else
    if( EN ) begin
      dOut  <= ( clr ) ? ( 0 ) : ( dIn );
    end
  end
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Function calculating rounded-to-up base-2 logarithm
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
 // `define CLOG2(x) \
    // (x < 2) ? 1 : \
    // (x < 4) ? 2 : \
    // (x < 8) ? 3 : \
    // (x < 16) ? 4 : \
    // (x < 32) ? 5 : \
    // (x < 64) ? 6 : \
    // ..etc, as far as you need to go..
    // (x = 4294967296) ? 32 : -1
    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Button debouncer with input synchronizer
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module  DeBounce#(
    parameter TOLERANCE_TICKS = 5
  )( 
  input  logic       Clk,
  input  logic      Srst,
  input  logic    di_Key,
  output logic    do_Key,
  output logic  do_Press,
  output logic  do_DePrs
  
);

  // checking for parameters legality
  generate
    if ( TOLERANCE_TICKS < 5 ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      DeBounce__Error_in_module__Wrong_parameters non_existing_module();
    end
  endgenerate
  
  localparam LOGWIDTH = $clog2(TOLERANCE_TICKS); // Systemverilog 2005; if not supported uncomment define
  logic   [ LOGWIDTH - 1 : 0 ]   Cnt;
  logic   [            2 : 0 ]   Out;
  logic                          dKey0, dKey1;
  assign { do_Key, do_Press, do_DePrs } = Out;  
  
  //Synchronizer logic
  always_ff@(posedge Clk or posedge Srst) begin
    if(Srst) begin
      dKey0 <= 1'b0;
      dKey1 <= 1'b0;
    end else begin
      dKey0 <= di_Key;
      dKey1 <= dKey0;
    end
  end 
  
  enum int unsigned { S0 = 0, S1 = 5, S2 = 4, S3 = 6, S4 = 1, S5 = 2 } state, next_state;
  
  always_comb begin : next_state_logic
    next_state = S0;
    case(state)
      S0: next_state = (           dKey1  ==  1'b1 ) ? ( S1 ) : ( S0 );
      S1: next_state = S2;
      S2: next_state = ( Cnt > TOLERANCE_TICKS - 3 ) ? ( S3 ) : ( S2 );
      S3: next_state = (           dKey1  ==  1'b0 ) ? ( S4 ) : ( S3 );
      S4: next_state = S5;
      S5: next_state = ( Cnt > TOLERANCE_TICKS - 3 ) ? ( S0 ) : ( S5 );
    endcase
  end
  
  always_comb begin
    case(state)
      S0: Out = 3'b000;
      S1: Out = 3'b110;
      S2: Out = 3'b100;
      S3: Out = 3'b100;
      S4: Out = 3'b001;
      S5: Out = 3'b000;
    endcase
  end
  
  always_ff@(posedge Clk or posedge Srst) begin
    if(Srst)
      state <= S0;
    else
      state <= next_state;
  end
  
  always_ff@(posedge Clk or posedge Srst) begin
    if(Srst)
      Cnt <= 0;
    else
      Cnt <= ( state == S1 || state == S4 ) ? ( 0 ) : ( Cnt + 1'b1 );
  end
  
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Button debouncer with input synchronizer, Modification not needed for reset, intended to use for global reset input
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module  DeBounce_Rst#(
    parameter TOLERANCE_TICKS = 5
  )( 
  input  logic       Clk,
  input  logic    di_Key,
  output logic    do_rst  
);

  // checking for parameters legality
  generate
    if ( TOLERANCE_TICKS < 5 ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      DeBounce__Error_in_module__Wrong_parameters non_existing_module();
    end
  endgenerate
  
  localparam LOGWIDTH = $clog2(TOLERANCE_TICKS); // Systemverilog 2005; if not supported uncomment define
  logic   [ LOGWIDTH - 1 : 0 ]   Cnt;
  logic                          dKey0, dKey1;  
  
  //Synchronizer logic
  always_ff@(posedge Clk) begin
    dKey0 <= di_Key;
    dKey1 <= dKey0;
  end 
  
  enum int unsigned { S0 = 1, S1 = 0 } state, next_state;
  
  always_comb begin : next_state_logic
    next_state = S0;
    case(state)
      S0: next_state = ( Cnt > TOLERANCE_TICKS - 3 ) ? ( S1 ) : ( S0 );
      S1: next_state = S1;
    endcase
  end
  
  always_comb begin
    case(state)
      S0: do_rst = 1'b1;
      S1: do_rst = 1'b0;
    endcase
  end
  
  always_ff@(posedge Clk or posedge dKey1 ) begin
    if( dKey1 )
      state <= S0;
    else
      state <= next_state;
  end
  
  always_ff@(posedge Clk or posedge dKey1 ) begin
    if( dKey1 )
      Cnt <= 0;
    else
      Cnt <= Cnt + 1'b1 ;
  end
  
endmodule


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Debouncer testbench
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module Testbench_DeBounce#(
  parameter TOLERANCE_TICKS = 5
  )(
);
  localparam LOGWIDTH = $clog2(TOLERANCE_TICKS); // Systemverilog 2005; if not supported uncomment define
  
  logic clk, Srst;
  
  logic key_In;
  
  logic key_out,     Press_out,    DePress_out;
  logic key_out_ex,  Press_out_ex, DePress_out_ex;
  
  logic [ 4*4 - 1 :0] testvectors[10000:0]; 
  logic [ 31:0]        vectornum, errors;
  logic [ LOGWIDTH - 1    :0] bit_cnt; 
  
  logic  [11:0] tr;
  
  // instantiate under test
  DeBounce #(
      .TOLERANCE_TICKS ( TOLERANCE_TICKS )
    ) dut (
      .Clk      (         clk ), 
      .Srst     (        Srst ), 
      .di_Key   (      key_In ), 
      .do_Key   (     key_out ), 
      .do_Press (   Press_out ), 
      .do_DePrs ( DePress_out )  
    );
  
  // generate clock
  always  begin
      clk=0; #5; clk=1; #5;
  end
  
  // at start, load vectors and pulse Srst
  initial
    begin
      $readmemh("../../Source/Common/test_DeBounce.tv",testvectors);
      vectornum = 0; errors = 0; bit_cnt = 0;
      Srst = 1; #27; Srst=0;
    end 
      
  // apply test vectors on rising edge of clk
  always@(posedge clk)
    begin
      // format b_b_b_b
      #1; { tr[11:9], key_In, tr[8:6], key_out_ex, tr[5:3], Press_out_ex, tr[2:0], DePress_out_ex} = testvectors[ vectornum ];
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( ~Srst ) begin // skip during reset
      if( ( key_out != key_out_ex ) || ( Press_out != Press_out_ex ) || ( DePress_out != DePress_out_ex ) ) begin
        $display( "Error: step %d", vectornum );
        $display( " legend:  key_In  key_out,     Press_out,    DePress_out");
        $display( " outputs  = %b, %b, %b, %b", key_In,  key_out,     Press_out,    DePress_out    );
        $display( " expected = %b, %b, %b, %b", key_In,  key_out_ex,  Press_out_ex, DePress_out_ex );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
       $display( "%d tests complete with %d errors", vectornum, errors );
       $finish;
      end
    end
    
endmodule