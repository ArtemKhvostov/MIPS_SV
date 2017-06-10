/////////////////////////////////////////////////////
module RCAdder #(
  parameter LOGWIDTH = 5
  )(
  input   logic [ 2**LOGWIDTH - 1 : 0 ] A, B,
  input   logic                         Cin,
  output  logic [ 2**LOGWIDTH - 1 : 0 ] S,
  output  logic                         Cout 
);
  
  genvar  i;
  logic  [ 2**LOGWIDTH : 0 ] C;
  assign  C[ 0 ] = Cin;
  generate
    for( i = 0; i < 2**LOGWIDTH; i = i + 1 ) begin: fulladder
      Fulladder FA( A[ i ], B[ i ], C[ i ], S[ i ], C[ i + 1 ] );
    end
  endgenerate
  
  assign  Cout = C[ 2**LOGWIDTH ];
  
endmodule

//////////////////////////////////////////////////////
module Fulladder (
  input  logic A, B, Cin,  
  output logic S, Cout
);

  logic  cb;
  assign cb   = A  ^ B;
  assign S    = cb ^ Cin;
  assign Cout = ( cb & Cin ) | ( A & B );
  
endmodule     