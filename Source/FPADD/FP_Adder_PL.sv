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
module FPAdder_Pipelined #( // 32 bit IEEE754 floating point adder LITTLE-ENDIAN/BIG-ENDIAN - to check initial schemes
  parameter LOGWIDTH = 5, EXPWIDTH = 8, MANTWIDTH = 23 // 32-bit IEEE754, 64-bit IEEE754 is #(6, 11, 52)
  )(
  input  logic                    clk,
  input  logic                    ci_rst,
                                  
  input  logic [2**LOGWIDTH-1:0]  diA, diB,
                                  
  input  logic                    ciADD_n,
  input  logic                    ciStallA,
                                  
  output logic [2**LOGWIDTH-1:0]  doY,
  output logic                    coNAN,
  output logic                    coZero
);
 
  // checking for parameters legality
  generate
    if ( 2**LOGWIDTH != MANTWIDTH + EXPWIDTH +1 ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      FPAdder__Error_in_module__Wrong_parameters non_existing_module();
    end
  endgenerate

  // signals in the top module
  logic                       dAs_A, dBs_A, dAs_B, dBs_B; // signs of input signals 
  logic [              1 :0 ] cAtype_A, cBtype_A, cAtype_B, cBtype_B, cAtype_C, cBtype_C; // 00 = normal, 01 = NaN, 10 = inf, 11 = -inf
  logic [ EXPWIDTH     -1:0 ] dAe, dBe; // Exponents of input signals
  logic [ MANTWIDTH      :0 ] dAm, dBm; // Mantissas of input signals
  logic [ 2**LOGWIDTH  -1:0 ] dAmo_A, dBmo_A, dAmo_B, dBmo_B;
  logic [ EXPWIDTH     -1:0 ] dOie_A, dOie_B, dOie_C;
  logic [ EXPWIDTH     -1:0 ] dOee_B, dOee_C;
  logic                       dOs_B, dOs_C; // output sign
  logic [ 2**LOGWIDTH  -1:0 ] dOim_B, dOim_C;
  logic [ EXPWIDTH     -1:0 ] dOe_C; // output exponent
  logic [ MANTWIDTH    -1:0 ] dOm_C;
  
  // ++++++++++++++++++++++++ Stage A ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  FPA_Input #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_In  (  diA,  diB, ciADD_n, dAs_A,  dBs_A,  dAe,    dBe,   dAm, dBm );
  FPA_Exp   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_Exp (  dAe,  dBe, dAm,     dBm,    dOie_A, dAmo_A, dBmo_A );
  
    // input type decode ( add/sub is already in dBs )
  assign cAtype_A = ( ~& dAe                  ) ? ( 2'b00 ) :
                  (  | dAm[ MANTWIDTH-1:0 ] ) ? ( 2'b01 ) : ( { 1'b1, dAs_A } );

  assign cBtype_A = ( ~& dBe                  ) ? ( 2'b00 ) :
                  (  | dBm[ MANTWIDTH-1:0 ] ) ? ( 2'b01 ) : ( { 1'b1, dBs_A } );     
                  
  
  PipelineReg #(
    .WIDTH ( 1 + 1 + 2**LOGWIDTH + 2**LOGWIDTH + MANTWIDTH + 2 + 2  )
  )  PR1  (
    .clk   ( clk        ),
    .rst   ( ci_rst     ),
    .clr   ( 1'b0       ),
    .EN    ( !ciStallA  ),

    .dIn   ( { dAs_A, dBs_A, dAmo_A, dBmo_A, dOie_A, cAtype_A, cBtype_A } ),
    .dOut  ( { dAs_B, dBs_B, dAmo_B, dBmo_B, dOie_B, cAtype_B, cBtype_B } )
  );
  
  // ++++++++++++++++++++++++ Stage B ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  
  FPA_Add   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_Add ( dAmo_B, dBmo_B, dAs_B, dBs_B, dOs_B, dOim_B, dOee_B );
    
  PipelineReg #(
    .WIDTH ( 1 + 2**LOGWIDTH + MANTWIDTH + MANTWIDTH + 2 + 2 )
  )  PR2  (
    .clk   ( clk    ),
    .rst   ( ci_rst ),
    .clr   ( 1'b0   ),
    .EN    ( 1'b1   ),

    .dIn   ( { dOs_B, dOim_B, dOee_B, dOie_B, cAtype_B, cBtype_B } ),
    .dOut  ( { dOs_C, dOim_C, dOee_C, dOie_C, cAtype_C, cBtype_C } )
  );
  
  // ++++++++++++++++++++++++ Stage C ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic cZero;
  FPA_Out   #( LOGWIDTH, EXPWIDTH, MANTWIDTH )  fpa_sub_Out ( dOie_C, dOee_C, dOim_C, dOe_C, dOm_C, cZero  );
      
  // Output assignments
  logic [2**LOGWIDTH-1:0] dYnorm, dYnan, dYpinf, dYninf;
  assign dYnorm = {                       dOs_C, dOe_C, dOm_C } ;
  assign dYnan  = {                         2**LOGWIDTH{1'b1} } ;
  assign dYpinf = { 1'b0, {EXPWIDTH{1'b1}}, {MANTWIDTH{1'b0}} } ;
  assign dYninf = { 1'b1, {EXPWIDTH{1'b1}}, {MANTWIDTH{1'b0}} } ;

  always_comb casex ( { cAtype_C, cBtype_C } )
    4'b0000 : { doY, coNAN, coZero } = { dYnorm, 1'b0, cZero };
    4'b0010 : { doY, coNAN, coZero } = { dYpinf, 1'b0, 1'b0  };
    4'b1000 : { doY, coNAN, coZero } = { dYpinf, 1'b0, 1'b0  };
    4'b1010 : { doY, coNAN, coZero } = { dYpinf, 1'b0, 1'b0  };
    4'b0011 : { doY, coNAN, coZero } = { dYninf, 1'b0, 1'b0  };
    4'b1100 : { doY, coNAN, coZero } = { dYninf, 1'b0, 1'b0  };
    4'b1111 : { doY, coNAN, coZero } = { dYninf, 1'b0, 1'b0  };
    default : { doY, coNAN, coZero } = { dYnan , 1'b1, 1'b0  };
  endcase
                                                        
endmodule
      