// SystemVerilog HDL
// IEEE-754 adder/subtractor module
//
// Special values:
// number  Sign  Exp   Fraction
// *       X     000   non-zero   : Non-strict, zero or less-than-required-limit small value
// 0       X     000   000000
// inf     0     111   000000
// -inf    1     111   000000
// NaN     x     111   non-zero
  
`timescale 1ns/1ps // unit/precision
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// FPAdder top module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module FPAdder #( // 32 bit IEEE754 floating point adder LITTLE-ENDIAN/BIG-ENDIAN - to check initial schemes
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754, 64-bit IEEE754 is #(6, 11, 52)
  )(
  input  logic [2**LOGWIDTH-1:0] diA, diB,
  
  input  logic                   ciADD_n,
  
  output logic [2**LOGWIDTH-1:0] doY
);
  
  // checking for parameters legality
  generate
    if ( 2**LOGWIDTH != MANTWIDTH + EXPWIDTH +1 ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      FPAdder__Error_in_module__Wrong_parameters non_existing_module();
    end
  endgenerate

  // signals in the top module
  logic dAs, dBs; // signs of input signals 
  logic [1:0] cAtype, cBtype; // 00 = normal, 01 = NaN, 10 = inf, 11 = -inf
  logic [ EXPWIDTH    -1 : 0 ]  dAe, dBe; // Exponents of input signals
  logic [      MANTWIDTH : 0 ]  dAm, dBm; // Mantissas of input signals
  logic [ 2**LOGWIDTH -1 : 0 ]  dAmo, dBmo;
  logic [ EXPWIDTH    -1 : 0 ]  dOie, dOee;
  logic dOs; // output sign
  logic [ 2**LOGWIDTH -1 : 0 ]  dOim;
  logic [ EXPWIDTH    -1 : 0 ]  dOe; // output exponent
  logic [ MANTWIDTH   -1 : 0 ]  dOm;
  
  // submodules
  FPA_Input #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_In  (  diA,  diB, ciADD_n, dAs,  dBs,  dAe,  dBe, dAm, dBm );
  FPA_Exp   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_Exp (  dAe,  dBe,     dAm, dBm, dOie, dAmo, dBmo );
  FPA_Add   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_Add ( dAmo, dBmo,     dAs, dBs,  dOs, dOim, dOee );
  FPA_Out   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_Out ( dOie, dOee,    dOim, dOe,  dOm  , );

  // input type decode ( add/sub is already in dBs )
  assign cAtype = ( ~& dAe                  ) ? ( 2'b00 ) :
                  (  | dAm[ MANTWIDTH-1:0 ] ) ? ( 2'b01 ) : ( { 1'b1, dAs } );

  assign cBtype = ( ~& dBe                  ) ? ( 2'b00 ) :
                  (  | dBm[ MANTWIDTH-1:0 ] ) ? ( 2'b01 ) : ( { 1'b1, dBs } );           
  
  // Output assignments
  logic [2**LOGWIDTH-1:0] dYnorm, dYnan, dYpinf, dYninf;
  assign dYnorm = {                             dOs, dOe, dOm } ;
  assign dYnan  = {                         2**LOGWIDTH{1'b1} } ;
  assign dYpinf = { 1'b0, {EXPWIDTH{1'b1}}, {MANTWIDTH{1'b0}} } ;
  assign dYninf = { 1'b1, {EXPWIDTH{1'b1}}, {MANTWIDTH{1'b0}} } ;

  always_comb casex ( { cAtype, cBtype } )
    4'b0000 : doY = dYnorm;
    4'b0010 : doY = dYpinf;
    4'b1000 : doY = dYpinf;
    4'b1010 : doY = dYpinf;
    4'b0011 : doY = dYninf;
    4'b1100 : doY = dYninf;
    4'b1111 : doY = dYninf;
    default : doY = dYnan ;
  endcase
                                                        
endmodule
      
       
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Input signals splitter
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module FPA_Input #(
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754
  )( 
  input   logic [ 2**LOGWIDTH -1 : 0 ]  dA, dB,   // IEEE754 formats
                                                 
  input   logic                         ciADD_n,  // command
  output  logic                         dAs, dBs, // signs

  output  logic [ EXPWIDTH    -1 : 0 ]  dAe, dBe, // Exponents
  output  logic [      MANTWIDTH : 0 ]  dAm, dBm  // Mantissas
);
  assign  dAs = dA[ 2**LOGWIDTH-1 ];
  assign  dBs = ciADD_n ^ dB[ 2**LOGWIDTH-1 ];
  
  assign  dAe = dA[ 2**LOGWIDTH-1 -1 : MANTWIDTH ];
  assign  dBe = dB[ 2**LOGWIDTH-1 -1 : MANTWIDTH ];
  
  assign  dAm = ( |dA[ 2**LOGWIDTH -1 -1 : 0 ] ) ? ( { 1'b1, dA[ MANTWIDTH-1 : 0 ] } ) : ( 0 );
  assign  dBm = ( |dB[ 2**LOGWIDTH -1 -1 : 0 ] ) ? ( { 1'b1, dB[ MANTWIDTH-1 : 0 ] } ) : ( 0 );
endmodule

      
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Exponent computation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module FPA_Exp #( // Exponents are biased!!! 0 is 127 for 32-bit
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754
  )(
  input   logic [    EXPWIDTH -1 : 0 ]  diAe, diBe, // Exponents
  input   logic [      MANTWIDTH : 0 ]  diAm, diBm, // Mantissas
  
  output  logic [    EXPWIDTH -1 : 0 ]  doOie,
  output  logic [ 2**LOGWIDTH -1 : 0 ]  doAmo, doBmo  
);
  localparam integer    DivLogWidth = $clog2(EXPWIDTH+1); // SystemVerilog - 2005
  
  logic [ 2**DivLogWidth -1 : 0 ] dAe, dBe;
  logic [ 2**DivLogWidth -1 : 0 ] dVal;
  logic [ EXPWIDTH-1        : 0 ] diBe_n;
  logic                           Cout; 

  // preprocess to feed adder
  assign  dAe   = { {2**DivLogWidth-EXPWIDTH  {1'b0}}, diAe };
  assign  diBe_n  = ~diBe; // +1 is in Cin of Adder
  assign  dBe   = { {2**DivLogWidth-EXPWIDTH  {1'b1}}, diBe_n }; // sign extend

  // adder
  sum_prefix  #DivLogWidth  fpa_exp_sub_SP ( .Cin( 1'b1 ), .A( dAe ), .B( dBe ), .S( dVal ), .Cout( Cout )  ); 

  // postprocess to get sum and val signals
  logic                          cSign;
  logic [ 2**LOGWIDTH -1 : 0 ]  dAmoExt, dBmoExt; 
  logic [ 2**LOGWIDTH -1 : 0 ]  dAm_mod, dBm_mod, dBm_mod_pre;
  
  assign  cSign       = dVal[2**DivLogWidth-1];
  
  assign  dAmoExt     = { 1'b0, diAm, { 2**LOGWIDTH - MANTWIDTH-1 -1 {1'b0} } };
  assign  dBmoExt     = { 1'b0, diBm, { 2**LOGWIDTH - MANTWIDTH-1 -1 {1'b0} } }; 
  
  assign  dAm_mod     = ( ~&(dVal[ 2**DivLogWidth -1 : LOGWIDTH ]) ) ? ( 0 ) : ( ( dAmoExt >> ~dVal[LOGWIDTH-1:0] ) >> 1 );
  assign  dBm_mod     = (  |(dVal[ 2**DivLogWidth -1 : LOGWIDTH ]) ) ? ( 0 ) : (   dBmoExt >> dVal[LOGWIDTH-1:0]         );

  // output
  assign  doOie = ( cSign ) ? ( diBe )    :
                              ( diAe );
  assign  doAmo = ( cSign ) ? ( dAm_mod ) : 
                              ( dAmoExt );
  assign  doBmo = ( cSign ) ? ( dBmoExt )    : 
                              ( dBm_mod );
endmodule

      
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Adder
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module FPA_Add  #(
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754
  )(
  input   logic [ 2**LOGWIDTH -1 : 0 ]  diAmo, diBmo, // mantissas
  input   logic                         diAs,  diBs,  // signs
  output  logic                         doOs,         // output sign
  output  logic [ 2**LOGWIDTH -1 : 0 ]  doOim,        // output mantissa
  output  logic [ EXPWIDTH    -1 : 0 ]  doOee 
);
  integer i;
  
  logic [ 2**LOGWIDTH-1 : 0 ]   dA, dA_mod, dB, dS, dS_ni, dYraw; // adder main ports
  logic                         cAddOF;                   // Adder overflow
  logic                         cSgnsNOR, cSgnsNAND;      // controls for adder output treating 
  logic                         cNegOF, cPosOF;           // Negative and positive overflow signals
  logic                         cZero;                    // Full zero output;
  logic [ LOGWIDTH-1 : 0 ]      cFirstSign;

  inc_prefix  #(LOGWIDTH) inc0( .A(~diAmo), .S(dA_mod), .Cout());
  assign  dA  = ( diAs ) ? ( dA_mod ) :
                           (  diAmo ) ;
  assign  dB  = ( diBs ) ? ( ( ~diBmo ) ) : // +1 is in Cin
                           ( diBmo );
                           
  sum_prefix  #(LOGWIDTH) dutSP(  .Cin(diBs), .A(dA), .B(dB), .S(dS), .Cout(cAddOF) );

  inc_prefix  #(LOGWIDTH) inc1( .A(~dS), .S(dS_ni), .Cout());
    
  assign  cSgnsNAND = ~&{ dA[2**LOGWIDTH-1], dB[2**LOGWIDTH-1] };
  assign  cSgnsNOR  = ~|{ dA[2**LOGWIDTH-1], dB[2**LOGWIDTH-1] };
  
  assign  cPosOF    =  &{ cSgnsNAND, cSgnsNOR, dS[ 2**LOGWIDTH-1 ] };
  assign  cNegOF    = ~|{ cSgnsNAND, cSgnsNOR, dS[ 2**LOGWIDTH-1 ] };

  // !!! overflow logic: 
  // we use conventional Two's complement inputs. So,
  // inputs output[maxsz]   result
  //  +,x   0           simple positive
  //  +,+   1           positive overflow, treat whole as uint
  //  -,-   0           negative overflow, inverse+1 then treat whole as unit
  //  -,x   1           simple negative, inverse+1 then treat as uint
  //
  always_comb casex ( { dS[2**LOGWIDTH-1], cSgnsNOR, cSgnsNAND } )
    3'b0x1:  begin dYraw = { 1'b0, dS[ 2**LOGWIDTH-2: 0 ]};    doOs = 1'b0;  end //  Simple positive
    3'b111:  begin dYraw = dS;                                 doOs = 1'b0;  end //  Positive Overflow
    3'b000:  begin dYraw = dS_ni;                              doOs = 1'b1;  end //  Negative Overflow
    3'b10x:  begin dYraw = { 1'b0, dS_ni[ 2**LOGWIDTH-2: 0 ]}; doOs = 1'b1;  end //  Simple Negative
    default: begin dYraw = { 2**LOGWIDTH{ 1'bx } };            doOs = 1'bx;  end //  error case
  endcase 
  
  logic  [2**LOGWIDTH-1 : 0] dYraw_rev;
  always_comb begin
    for( i = 0; i < 2**LOGWIDTH; i = i + 1 )
      dYraw_rev[i] = dYraw[ 2**LOGWIDTH-1 - i ];
  end
  
  priority_coder  #(LOGWIDTH) dut(  .di_a(  dYraw ), .do_y(cFirstSign),  .co_err(cZero)  );
  
  //Mantissa output computation
  logic [LOGWIDTH-1:0] cMantShift;
  sum_prefix  #($clog2(LOGWIDTH)) ShiftSP( .Cin(1'b1), .A(2**LOGWIDTH-2), .B(~cFirstSign), .S(cMantShift), .Cout() );
  assign  doOim = (                    cZero ) ? ( {2**LOGWIDTH{1'b0}} ) : // Zero value exception
                  ( dYraw[ 2**LOGWIDTH - 1 ] ) ? (          dYraw >> 1 ) : 
                                                 ( dYraw << cMantShift ) ; 
  
    // checking for parameters legality
  generate
    if ( LOGWIDTH +1 > EXPWIDTH ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      FPAdder__Error_in_module__Implementation_restriction non_existing_module();
    end
  endgenerate
  
  // output exponent is ( input expoent - doOee );
  assign  doOee = { {EXPWIDTH-LOGWIDTH{cMantShift[LOGWIDTH-1]}}, cMantShift };             

endmodule

      
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Rounding and final exponent computation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module FPA_Out #(
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23  // 32-bit IEEE754
  )( 
  input   logic [ EXPWIDTH    -1 : 0 ]  diOie, diOee,
  input   logic [ 2**LOGWIDTH -1 : 0 ]  diOim,
  output  logic [ EXPWIDTH    -1 : 0 ]  doOe,           // output exponent
  output  logic [ MANTWIDTH   -1 : 0 ]  doOm,
  output  logic                         coZero
);
  // Mantissa rounding 
  logic  [ MANTWIDTH + 1 : 0 ] dOm, dOm_pre;
  inc_prefix #($clog2(MANTWIDTH + 2)) inc2( .A(diOim[ 2**LOGWIDTH - 1 : 2**LOGWIDTH - MANTWIDTH - 2 ]), .S(dOm_pre), .Cout() );
  assign dOm = ( diOim[ 2**LOGWIDTH - MANTWIDTH - 3 ] ) ? ( dOm_pre ) :
                                                          ( diOim[ 2**LOGWIDTH - 1 : 2**LOGWIDTH - MANTWIDTH - 2 ]     ) ;
               
  // Exponent calculation
  logic [ EXPWIDTH : 0 ] dOe_pre, dOe_pre1, dOe_pre2;
  //assign dOe_pre = { 1'b0, diOie } - { diOee[EXPWIDTH -1], diOee } + dOm[ MANTWIDTH + 1]; //Changed to custom logic 
  sum_prefix #($clog2(EXPWIDTH+1)) outSP( .Cin(1'b1), .A({ 1'b0, diOie }), .B( ~{ diOee[EXPWIDTH -1], diOee }), .S(dOe_pre1), .Cout() );
  inc_prefix #($clog2(EXPWIDTH+1)) outIP( .A(dOe_pre1), .S(dOe_pre2), .Cout() );
  assign dOe_pre = ( dOm[ MANTWIDTH + 1] ) ? ( dOe_pre2 ) : ( dOe_pre1 );
  
  
  
  // Exception checking
  logic  cInf;  
  assign cInf    = ( dOe_pre[ EXPWIDTH : EXPWIDTH -1 ] == 2'b10 ) || ( &dOe_pre[EXPWIDTH -1 : 0] );
  assign coZero   = ( dOe_pre[ EXPWIDTH : EXPWIDTH -1 ] == 2'b11 ) || (                   ~|diOim );
  
  // Output exponent
  assign doOe = ( cInf  ) ? (         {EXPWIDTH{1'b1}} ) : // Infinity
                ( coZero ) ? (         {EXPWIDTH{1'b0}} ) : // Zero
                            ( dOe_pre[EXPWIDTH -1 : 0] ) ;
  
  // Output mantissa
  assign doOm = ( cInf || coZero ) ? (        {MANTWIDTH{1'b0}} ) : // Infinity or Zero
                                    ( dOm[ MANTWIDTH - 1 : 0 ] ) ;
    
endmodule 