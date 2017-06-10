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
// addi     001000ssssstttttSignimmmmmmmmmmm                     rt=rs+signimm
// j        000010Addddddddddddddddddddddddr
/////////////////////////////////////////////////////

`timescale 1ns/1ps // unit/precision
/////////////////////////////////////////////////////
// Testbench for simple single-cycle integer MIPS CPU
/////////////////////////////////////////////////////
module Testbench_CPU #(
  parameter LOGWIDTH = 5    //32-bit
  )();
  logic                        clk, reset;
  
  logic [2**LOGWIDTH - 1 : 0] dWD_Mem,  dWD_Mem_ex;
  logic [2**LOGWIDTH - 1 : 0] dWD_Reg,  dWD_Reg_ex;
  
  logic [2**LOGWIDTH - 1 : 0] dADR_Mem, dADR_Mem_ex;  
  logic [2**LOGWIDTH - 1 : 0] dADR_Reg, dADR_Reg_ex;
  
  logic                       cMW_Mem,  cMW_Mem_ex;
  logic                       cMW_Reg,  cMW_Reg_ex;
  
  logic [ 31 : 0 ]             vectornum, errors;
  logic [ 2 * ( ( 2 * ( 2**LOGWIDTH ) ) + 4 ) - 1 : 0 ] testvectors[ 10000 : 0 ]; // dWD_Mem, dADR_Mem, cMW_Mem, dWD_Reg, dADR_Reg, cMW_Reg
  
  logic [5:0]                 tr;
  
  // instantiate under test
  CPU dut ( 
    .clk          (   clk ), 
    .ci_rst       ( reset ),
    .ciInstInp    (  1'b0 ),
    .diInstToMem  ( 32'h0 ),
    .diInstAddr   (  8'h0 ),
    .writedataM   (   dWD_Mem ), 
    .adrM         (  dADR_Mem ),
    .memwriteM    (   cMW_Mem ),
    .writedataR   (   dWD_Reg ), 
    .adrR         (  dADR_Reg ),
    .memwriteR    (   cMW_Reg )
  );
  // generate clock
  always
    begin
      clk = 1; #5; clk = 0; #5;
    end
  
  // at start, load vectors and pulse reset
  initial
    begin
      $readmemh("../../Source/MIPS/test_CPU.tv",testvectors);
      vectornum = 0; errors = 0;
      reset = 0; #3 reset = 1; #20; reset = 0;
    end 
  
  // apply test vectors on rising edge of clk
  always@(posedge clk)
    begin
      // format hhhhhhhh_hhhhhhhh_b_hhhhhhhh_hhhhhhhh_b
      #1; { dWD_Mem_ex, dADR_Mem_ex, tr[2:0], cMW_Mem_ex, dWD_Reg_ex, dADR_Reg_ex, tr[5:3], cMW_Reg_ex } = testvectors[ vectornum ];
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( ~reset ) begin // skip during reset
      if( ( dWD_Mem != dWD_Mem_ex ) || ( dADR_Mem != dADR_Mem_ex ) || ( cMW_Mem != cMW_Mem_ex ) ) begin
        $display( "Error: step %d Data memory", vectornum );
        $display( " legend:    writedat, address,  MemWrite");
        $display( " outputs  = %h, %h, %b", dWD_Mem,    dADR_Mem,   cMW_Mem   );
        $display( " expected = %h, %h, %b", dWD_Mem_ex,  dADR_Mem_ex, cMW_Mem_ex );
        errors += 1;
      end
      if( ( dWD_Reg != dWD_Reg_ex ) || ( dADR_Reg != dADR_Reg_ex ) || ( cMW_Reg != cMW_Reg_ex ) ) begin
        $display( "Error: step %d Register file", vectornum );
        $display( " legend:    writedat, address,  MemWrite");
        $display( " outputs  = %h, %h, %b", dWD_Reg,    dADR_Reg,   cMW_Reg   );
        $display( " expected = %h, %h, %b", dWD_Reg_ex,  dADR_Reg_ex, cMW_Reg_ex );
        errors += 1;
      end
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
       $display( "%d tests complete with %d errors", vectornum, errors );
       $finish;
      end
    end
    
endmodule