////// List of commands: ////////////////////////////
//// Integer instructions
// registers: s0-s7(0x10-0x17), t0-t9(0x8-0xF)
// command  format                               comments          description
// add      000000 sssss ttttt ddddd 00000100000                   rd = rs + rt
// sub      000000 sssss ttttt ddddd 00000100010                   rd = rs - rt
// and      000000 sssss ttttt ddddd 00000100100                   rd = rs & rt
// or       000000 sssss ttttt ddddd 00000100101                   rd = rs | rt
// slt      000000 sssss ttttt ddddd 00000101010                   rd = rs < rt
//
// lw       100011 sssss ttttt Offseeeeeeeeeeet                    [rt] = [Offset(rs)]
// sw       101011 sssss ttttt Offseeeeeeeeeeet                    [Offset(rs)] = [rt]
//
// beq      000100 sssss ttttt Labeeeeeeeeeeeel
//
// addi     001000 sssss ttttt Signimmmmmmmmmmm                     rt=rs+signimm
// j        000010 Addddddddddddddddddddddddr
//
//// Floating point instructions
// command  format                               comments          description
// add.s    010001 10000 ttttt sssss ddddd 000000                  fd = fs + ft
// sub.s    010001 10000 ttttt sssss ddddd 000001                  fd = fs - ft
//
// lwc1     110001 sssss ttttt Offseeeeeeeeeeet                    [ft] = [Offset(rs)]
// swc1     111001 sssss ttttt Offseeeeeeeeeeet                    [Offset(rs)] = [ft]
//
// mtc1     010001 00100 sssss ddddd 00000 000000                  move to $f
// mfc1     010001 00000 ddddd sssss 00000 000000                  move from $f
//                                                        
// cvt.s.w  010001 10000 00000 sssss ddddd 100000                  convert from int to float
// cvt.w.s  010001 10000 00000 sssss ddddd 100100                  convert from float to int
//                                                        
// c.lt.s   010001 10000 ttttt sssss 00000 111100                  less than
// c.le.s   010001 10000 ttttt sssss 00000 111110                  less or equal
// c.eq.s   010001 10000 ttttt sssss 00000 110010                  equal
//                                                        
// bc1t     010001 01000 00001 Labeeeeeeeeeeeel                    branch if previous is true
// bc1f     010001 01000 00000 Labeeeeeeeeeeeel                    branch if previous is false
//
// resume
// Opcode(31:26) is 010001 for all FP instructions except lwc1/swc1;
// lwc1/swc1 are similar to lw/sw except different register set and opcode
// For other instructions:
//        R-type (all except bc1* and mtc1/mfc1):  RS(25:21)=10000; then ft, fs, fd, FUNCT. Exception: for c.*.s: ft, fd, 00000, FUNCT ?!?!?!
//        mtc1: RS = 00100 ; other fields are unknown!!!
//        mfc1: RS = 00000 ; other fields are unknown!!!
//        bc1*: RS = 01000 ; RT = 0000*; than Label; (I-type) 
//
// 1) If Instr[30] than Coprocessor operation 
// 2) If Opcode 11x001 than lwc1/swc1, use integer operation but FP source/target ( treat by existing CU )
// 3) If Opcode 010001 than register only operation
//
// ALU operation on add.s, sub.s, c.*.s
//
// register addresses:
//         names   source/destination
// [25:21]     rs; f:x;  r:s
// [20:16] ft; rt; f:sd; r:sd
// [15:11] fs; rd; f:sd; r:d
// [10: 6] fd      f:d;  r:x
//
// FP stalls:
//# cmd          | similar to                   | resume
//---------------+------------------------------+----------------
//1 add.s/sub.s  | lw                           | lwstall(FP) enable by FPALUenE along with MemtoRegE
//2 lwc1         | lw                           | 
//3 swc1         | sw                           | not needed?
//4 mtc1/mfc1    | special                      | MoveStall = |( ( ( Sources = WriteReg ) && RegWrite )[E,M])
//5 cvt          | R but don't care RD2 (Ft/Xt) | 
//6 compare      | lw                           | same as #1
//7 bc1*         | beq                          | Branchstall(FP) = FPBranchD && ( FPALUenE || FPALUenM )
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ns/1ps // unit/precision
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Testbench for simple single-cycle integer MIPS CPU
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
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
    .diInstAddr   ( 32'h0 ),
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