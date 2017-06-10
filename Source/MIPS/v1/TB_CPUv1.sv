////// List of commands: ////////////////////////////
// registers: s0-s7(0x10-0x17), t0-t9(0x8-0xF)
// command  format                            comments          description
// add      000000ssssstttttddddd00000100000                    rd = rs + rt
// sub      000000ssssstttttddddd00000100010                    rd = rs - rt
// and      000000ssssstttttddddd00000100100                    rd = rs & rt
// or       000000ssssstttttddddd00000100101                    rd = rs | rt
// slt      000000ssssstttttddddd00000101010                    rd = rs < rt
//
// lw       100011ssssstttttImmmmmmmmmmmmmmm                    [rt] = [Address(rs)]
// sw       101011ssssstttttImmmmmmmmmmmmmmm                    [Address(rs)] = [rt]
//
// beq      000100ssssstttttLabeeeeeeeeeeeel
// 
// addi     001000ssssstttttSignimmmmmmmmmmm                     rs=rt+signimm
// j        000010Addddddddddddddddddddddddr
/////////////////////////////////////////////////////

`timescale 1ns/1ps // unit/precision
/////////////////////////////////////////////////////
// Testbench for simple single-cycle integer MIPS CPU
/////////////////////////////////////////////////////
module Testbench_CPUv1 #(
  parameter LOGWIDTH = 5    //32-bit
  )();
  logic                        clk, reset;
  
  logic [2**LOGWIDTH - 1 : 0] dWD,  dWDex;
  logic [2**LOGWIDTH - 1 : 0] dADR, dADRex;
  logic                       cMW,  cMWex;
  
  logic [ 31 : 0 ]             vectornum, errors;
  logic [ ( 2 * ( 2**LOGWIDTH ) ) + 4 - 1 : 0 ] testvectors[ 10000 : 0 ]; // dWD, dADR, cMW
  
  logic [2:0]                 tr;
  
  // instantiate under test
  CPUv1 dut ( 
    .clk          (clk), 
    .ci_rst       (reset),
    .writedata    (dWD), 
    .adr          (dADR),
    .memwrite     (cMW)
  );
  
  // generate clock
  always
    begin
      clk = 1; #5; clk = 0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/MIPS/test_CPUv1.tv",testvectors);
      vectornum = 0; errors = 0;
      reset = 0; #3 reset = 1; #20; reset = 0;
    end 
  
  // apply test vectors on rising edge of clk
  always@(posedge clk)
    begin
      #1; { dWDex, dADRex, tr[2:0], cMWex } = testvectors[ vectornum ]; // format hhhhhhhh_hhhhhhhh_b
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( ~reset ) begin // skip during reset
      if( ( dWD != dWDex ) || ( dADR != dADRex ) || ( cMW != cMWex ) ) begin
        $display( "Error: step %d", vectornum );
        $display( " legend:    writedat, address,  MemWrite");
        $display( " outputs  = %h, %h, %b", dWD,    dADR,   cMW   );
        $display( " expected = %h, %h, %b", dWDex,  dADRex, cMWex );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
       $display( "%d tests complete with %d errors", vectornum, errors );
       $finish;
      end
    end
    
endmodule