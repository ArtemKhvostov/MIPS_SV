// Табл. 5.1 Операции АЛУ
// F2:0 Function
// 000  A AND B
// 001  A OR B
// 010  A + B
// 011  not used
// 100  A AND B¯
// 101  A OR B¯
// 110  A – B
// 111  SLT
/////////////////////////////////////////////////////
module ALU #(  //5.9, 5.10 and 5.11 
  parameter LOGWIDTH = 5 //32-bit
  )( 
  input   logic [2**LOGWIDTH-1:0] A, B,
  input   logic [2:0]             F,
  output  logic [2**LOGWIDTH-1:0] Y,
  output  logic                   Cout, Oflow, Zero 
);

  logic [2**LOGWIDTH-1:0] Binv, BB, S, OR, AND;

  assign  Binv = ~( B );
  assign  BB   = F[2] ? Binv : B;
  sum_prefix  #(
    .LOGWIDTH ( LOGWIDTH  )
  )SP(
    .Cin      ( F[2]      ), 
    .A        ( A         ), 
    .B        ( BB        ),
    .S        ( S         ),
    .Cout     ( Cout      )
  );
  //RCAdder #LOGWIDTH RCA( A, B, F[2], S, Cout);
  assign  OR  = A | BB;
  assign  AND = A & BB;
  
  localparam Width_reduced = 2**LOGWIDTH - 1;
  assign  Y = ( F[1] ) ? 
                          ( F[0] ) ? { { Width_reduced{ 1'h0 } }, S[ 2**LOGWIDTH - 1 ] } :
                                     ( S  ) :
                          ( F[0] ) ? ( OR ) : 
                                     ( AND );
                                     
  assign  Oflow = ( F[1:0] == 2'b10 ) ? ( ~( A[ Width_reduced ] ) & ~( BB[ Width_reduced ] ) &    S[ Width_reduced ] |
                                             A[ Width_reduced ]   &    BB[ Width_reduced ]   & ~( S[ Width_reduced ] ) ) :
                                        ( 1'b0 );
  assign  Zero = ~( |Y );

endmodule 