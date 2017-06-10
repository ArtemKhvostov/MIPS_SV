// Incrementor based on prefix adder
// TODO: optimise (-1:-1) and (oth:-1) PGL blocks
`timescale 1ns/1ps // unit/precision
module inc_prefix #(
  parameter LOGWIDTH = 5 // 32-bit
  )(
  input   logic [2**LOGWIDTH - 1:0] A,
  
  output  logic [2**LOGWIDTH - 1:0] S,
  output  logic                     Cout 
);

  genvar i;

  logic [2**LOGWIDTH - 1:0] P, G, Sxor;
  logic [2**LOGWIDTH - 1:0] Pout, Gout;
  logic                     Padd, Gadd;

  assign { Padd, P } = {                   A, 1'b1 };
  assign { Gadd, G } = { {2**LOGWIDTH{1'b0}}, 1'b1 };
    
  // Prefix tree
  Prefix_tree_inc #LOGWIDTH PT( P, G, Pout, Gout );
  
  // Output logic
  assign S = Gout ^ A;
  PGL_inc mCout( Padd, Pout[2**LOGWIDTH - 1], Gadd, Gout[2**LOGWIDTH - 1], ,Cout ); 
  
endmodule 

module Prefix_tree_inc #(
  parameter SIZE = 1
  )(
  input  logic [2**SIZE - 1:0] P, G,
  output logic [2**SIZE - 1:0] Pout, Gout
);
  genvar i;

  generate
    if( SIZE == 1 ) begin
      PGL_inc PGLBlock0( P[1], P[0], G[1], G[0], Pout[1], Gout[1] );
      assign  Pout[0] = P[0];
      assign  Gout[0] = G[0];
    end
    else  begin
      logic [2**( SIZE - 1 ) - 1:0] Pint, Gint;
      Prefix_tree_inc #( SIZE - 1 ) PT1( P[2**SIZE - 1:2**(SIZE-1)], G[2**SIZE - 1 : 2**( SIZE - 1 )], Pint,                        Gint );
      Prefix_tree_inc #( SIZE - 1 ) PT2( P[2**( SIZE - 1 ) - 1:0],   G[2**( SIZE - 1 ) - 1:0],         Pout[2**( SIZE - 1 ) - 1:0], Gout[2**( SIZE - 1 ) - 1:0] );
      for( i = 0; i < 2**( SIZE - 1 ); i = i + 1 )  begin: PGLGenerate
        PGL_inc PGLBlock( Pint[i], Pout[2**( SIZE - 1 ) - 1], Gint[i], Gout[2**( SIZE - 1 ) - 1 ], Pout[2**( SIZE - 1 ) + i ], Gout[2**( SIZE - 1 ) + i] );
      end
    end
  endgenerate

endmodule

module PGL_inc( 
  input  logic P1,P2,G1,G2,
  output logic Pout, Gout 
  );
  
  assign Pout = P1 & P2;
  assign Gout = P1 & G2;
  
endmodule
