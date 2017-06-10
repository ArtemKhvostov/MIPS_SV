// SystemVerilog HDL
// IEEE-754 conversion module
//
// Special values:
// number  Sign  Exp   Fraction
// *       X     000   non-zero   : Non-strict, zero or less-than-required-limit small value
// 0       X     000   000000
// inf     0     111   000000
// -inf    1     111   000000
// NaN     x     111   non-zero
  
// cvt.s.w    $fd, $fs        convert from int to float       FPA modified operation, Oie=30d, bypass the FPA_Exp   2-ticks
// cvt.w.s    $fd, $fs        convert from float to int       FPA modified operation, Mantissa shift by (31 - Exp), 
//                                                                      Inv+1, bypass remaining adder and FPA_Out   2-ticks

  
`timescale 1ns/1ps // unit/precision
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// CVT_FP top module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module CVT_FP #( 
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754, 64-bit IEEE754 is #(6, 11, 52)
  )(                                  
  input  logic [2**LOGWIDTH-1:0]  diA,
                                  
  input  logic                    ciWay, // 0 for word-to-float
  input  logic                    ciENA,
                                  
  output logic [2**LOGWIDTH-1:0]  doY,
  output logic                    doNAN,
  output logic                    doINF
);
 
  // checking for parameters legality
  generate
    if ( 2**LOGWIDTH != MANTWIDTH + EXPWIDTH +1 ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      FPAdder__Error_in_module__Wrong_parameters non_existing_module();
    end
  endgenerate
  
  logic  [ 2**LOGWIDTH-1  :0 ]  dYsw, dYws;
  logic                         dNAN, dINF;
  CVT_FP_SW   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  cvt_conv_sw (  diA, dYsw,  );
  CVT_FP_WS   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  cvt_conv_ws (  diA, dYws, dNAN, dINF );
  
  assign doNAN = ( ciWay ) ? ( dNAN ) : ( 1'b0 );
  assign doINF = ( ciWay ) ? ( dINF ) : ( 1'b0 );
  assign doY   = ( ciWay ) ? ( dYws ) : ( dYsw );
  
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// // IEEE754 integer to float converter
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////      
module CVT_FP_SW #( 
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754, 64-bit IEEE754 is #(6, 11, 52)
  )(                                  
  input  logic [2**LOGWIDTH-1:0]  diA,                                  
  output logic [2**LOGWIDTH-1:0]  doY,
  output logic                    coZero
);
  // Sign
  logic  dSign;
  assign dSign = diA[2**LOGWIDTH-1];
  localparam integer    DivLogWidth = $clog2(EXPWIDTH+1); // SystemVerilog - 2005
  
  // absolute value
  logic  [ 2**LOGWIDTH  -1:0 ] dA_abs, dA_abs_pre;
  inc_prefix  #(LOGWIDTH) inc1( .A(~diA), .S(dA_abs_pre), .Cout());
  assign dA_abs = ( dSign ) ? ( dA_abs_pre ) : ( diA );
  
  // mantissa and exponent logic    
  logic                         cZero;                    // Full zero output;
  logic [ LOGWIDTH-1 : 0 ]      cFirstSign;
  priority_coder  #(LOGWIDTH) dut(  .di_a(  dA_abs ), .do_y(cFirstSign),  .co_err(cZero)  );
  
  ////Mantissa output computation
  logic [    LOGWIDTH  -1:0 ] cMantShift;
  logic [ 2**LOGWIDTH  -1:0 ] dOim;
  sum_prefix  #($clog2(LOGWIDTH)) ShiftSP( .Cin(1'b1), .A(2**LOGWIDTH-2), .B(~cFirstSign), .S(cMantShift), .Cout() );
  assign  dOim = (                     cZero ) ? ( {2**LOGWIDTH{1'b0}}  ) : // Zero value exception
                 ( dA_abs[ 2**LOGWIDTH - 1 ] ) ? (          dA_abs >> 1 ) : 
                                                 ( dA_abs << cMantShift ) ; 
  
  //// checking for parameters legality
  generate
    if ( LOGWIDTH +1 > EXPWIDTH ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      FPAdder__Error_in_module__Implementation_restriction non_existing_module();
    end
  endgenerate
  
  //// output exponent is ( input expoent - doOee );
  //logic [ EXPWIDTH    -1 : 0 ]  dOee;
  //assign  dOee = { {EXPWIDTH-LOGWIDTH{cMantShift[LOGWIDTH-1]}}, cMantShift };   
  
  // Output logic
  
  // Mantissa rounding 
  logic  [ MANTWIDTH + 1 : 0 ] dOm, dOm_pre;
  inc_prefix #($clog2(MANTWIDTH + 2)) inc2( .A(dOim[ 2**LOGWIDTH - 1 : 2**LOGWIDTH - MANTWIDTH - 2 ]), .S(dOm_pre), .Cout() );
  assign dOm = ( dOim[ 2**LOGWIDTH - MANTWIDTH - 3 ] ) ? ( dOm_pre ) :
                                                         ( dOim[ 2**LOGWIDTH - 1 : 2**LOGWIDTH - MANTWIDTH - 2 ]     ) ;
               
  // Exponent calculation
  logic [ EXPWIDTH : 0 ] dOe_pre, dOe_pre1, dOe_pre2;
  //assign dOe_pre = { 1'b0, diOie } - { diOee[EXPWIDTH -1], diOee } + dOm[ MANTWIDTH + 1]; //Changed to custom logic 
  //sum_prefix #(DivLogWidth) outSP( .Cin(1'b1), .A( 2**(EXPWIDTH-1) + 2**LOGWIDTH - 2 ), .B( ~{ dOee[EXPWIDTH -1], dOee }), .S(dOe_pre1), .Cout() );
  sum_prefix #(DivLogWidth) outSP( .Cin(1'b0), .A( 2**(EXPWIDTH-1) -1 ), .B( { {(2**DivLogWidth-LOGWIDTH){1'b0}}, cFirstSign } ), .S(dOe_pre1), .Cout() );
  inc_prefix #(DivLogWidth) outIP( .A(dOe_pre1), .S(dOe_pre2), .Cout() );
  assign dOe_pre = ( dOm[ MANTWIDTH + 1] ) ? ( dOe_pre2 ) : ( dOe_pre1 );
  
  
  
  // Exception checking
  assign coZero  = ( dOe_pre[ EXPWIDTH : EXPWIDTH -1 ] == 2'b11 ) || ( cZero );
  
  // Output exponent
  logic  [ EXPWIDTH -1 : 0 ] dOe;
  assign dOe = ( coZero ) ? (         {EXPWIDTH{1'b0}} ) : // Zero
                            ( dOe_pre[EXPWIDTH -1 : 0] ) ;
  
  // Output mantissa
  logic  [ MANTWIDTH  -1:0 ] dYm;
  assign dYm = ( coZero ) ? (        {MANTWIDTH{1'b0}} ) :
                            ( dOm[ MANTWIDTH - 1 : 0 ] ) ;
  //output
  assign  doY = { dSign, dOe, dYm };
  
endmodule
 
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// // IEEE754 float to integer converter
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module CVT_FP_WS #( 
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754, 64-bit IEEE754 is #(6, 11, 52)
  )(                                  
  input  logic [2**LOGWIDTH-1:0]  diA,                                  
  output logic [2**LOGWIDTH-1:0]  doY,
  output logic                    doNAN,
  output logic                    doInf
);
  // Input decode
  logic                        dSign;
  logic                        cZero;
  logic                        cInf;
  logic [    EXPWIDTH  -1: 0 ]  dAe; // Exponent
  logic [   MANTWIDTH  -1: 0 ]  dAm_pre; // Mantissa w/o leading 1
  logic [      MANTWIDTH : 0 ]  dAm; // Mantissa
  assign  dSign   = diA[ 2**LOGWIDTH-1 ];
  assign  dAe     = diA[ 2**LOGWIDTH-1 -1 : MANTWIDTH ];
  assign  dAm_pre = diA[ MANTWIDTH-1 : 0 ];
  assign  cZero   = ~|( { dAe, dAm_pre } );
  assign  cInf    = ( &dAe ) && ( ~|dAm_pre );
  assign  doNAN   = ( &dAe ) && (  |dAm_pre );
  assign  dAm     = ( cZero ) ? 0 : { 1'b1, dAm_pre };
  
  localparam integer    DivLogWidth = $clog2(EXPWIDTH+1); // SystemVerilog - 2005
  
  logic [ 2**DivLogWidth -1 : 0 ] dAe_ext;
  logic [ 2**DivLogWidth -1 : 0 ] dVal;
  logic [ EXPWIDTH-1        : 0 ] dAe_n;
  logic                           Cout; 

  // preprocess to feed adder
  //assign  dAe_n  = ~dAe; // +1 is in Cin of Adder
  //assign  dAe_ext   = { {2**DivLogWidth-EXPWIDTH  {1'b1}}, dAe_n }; // sign extend
  assign  dAe_ext   = { {2**DivLogWidth-EXPWIDTH  {1'b0}}, dAe }; // sign extend
  
  // adder  
  sum_prefix  #DivLogWidth  fpa_exp_sub_SP ( .Cin( 1'b0 ), .A( dAe_ext ), .B(  - 2**(EXPWIDTH-1) + 1 - ( 2**LOGWIDTH -2 ) ), .S( dVal ), .Cout( Cout )  ); 
  
  // postprocess to get sum and val signals
  logic                          cSign_exp;
  logic [ 2**LOGWIDTH -1 : 0 ]  dAmExt; 
  logic [ 2**LOGWIDTH    : 0 ]  dAm_mod1_pre;
  logic [ 2**LOGWIDTH -1 : 0 ]  dAm_mod1;
  logic [ 2* (2**LOGWIDTH -1) : 0 ]  dAm_mod2;
  logic [ 2**LOGWIDTH -1 : 0 ]  dAmo, dAmo_pre, dAmo_inc, dAmo_neg;
  logic                         cZero1;
  
  assign  cSign_exp       = dVal[2**DivLogWidth-1];
  
  assign  dAmExt   = { 1'b0, dAm, { EXPWIDTH-1 {1'b0} } };
  
  assign  dAm_mod1_pre = ( dAmExt >> ~dVal[LOGWIDTH-1:0] );
  assign  dAm_mod1     = dAm_mod1_pre[2**LOGWIDTH  :  1];
  assign  dAm_mod2 =  { {(2**LOGWIDTH-1){1'b0}}, dAmExt } << dVal[LOGWIDTH-1:0];
  assign  dAmo_pre     = ( cSign_exp ) ? dAm_mod1 : dAm_mod2[ 2**LOGWIDTH -1 : 0 ];   
  inc_prefix #(LOGWIDTH) incAMOrnd ( .A(dAmo_pre), .S(dAmo_inc), .Cout() );
  assign  dAmo     = ( cSign_exp && dAm_mod1_pre[0]) ? dAmo_inc : dAmo_pre;
  
  assign  cZero1   = cSign_exp && (~&(dVal[ 2**DivLogWidth -1 : LOGWIDTH ]));

  // output
  inc_prefix #(LOGWIDTH) incAMO ( .A(~dAmo), .S(dAmo_neg), .Cout() );
  assign  doInf = cInf || 
                  ( ( !cSign_exp ) && ( |dAm_mod2[ 2* (2**LOGWIDTH -1) : 2**LOGWIDTH ] ) ) ||
                  (   !dSign && !cSign_exp && dAm_mod2[ 2**LOGWIDTH-1 ] );
  assign  doY   = ( cZero1 ) ? ( 0        ) : 
                  ( dSign  ) ? ( dAmo_neg ) : ( dAmo );
  
endmodule