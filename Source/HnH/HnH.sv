`timescale 1ns/1ps // unit/precision
/////////////// First easy exercises //////////////////
module exercise1 (
  input   logic a, b, c,
  output  logic y, z
);

  assign y = a & b & c | a & b & ~c | a & ~b & c;
  assign z = a & b | ~a & ~b;

endmodule

module exercise2 (
  input logic [3:0] a,
  output  logic y
);

  assign y = ( a[ 3 ] ^ a[ 2 ] ) ^ ( a[ 1 ] ^ a[ 0 ] );

  endmodule

module exercise3 (
  input   logic s, r,
  output  logic Q, nQ
);

  logic state;            

  always_latch
    state=(s|r) ? s&~r:state;
  
  assign Q=state;
  assign nQ=~state&~s;

  endmodule

/////////////////////////////////////////////////////
module priority_coder #( // priority coder, ex 5.7
  parameter output_width = 4
  )( 
  input   logic [ 2**output_width-1 : 0 ] di_a,
  output  logic [ output_width-1    : 0 ] do_y, 
  output  logic                           co_err
);

  genvar ind_bit, cOrInd;

  generate
    for( ind_bit = 0; ind_bit < output_width; ind_bit = ind_bit + 1) begin: OutBitLoop
      //logic [ 2**(output_width-1)-1 : 0 ] or_in;
      localparam integer c_logMUXwidth = output_width - 1 - ind_bit;
      localparam integer cMUXwidth     = 2**( c_logMUXwidth );
      localparam integer cOrStep       = 2**( ind_bit + 1 );
      localparam integer cOrWidth      = 2**ind_bit;
      
      logic [cMUXwidth-1:0] mux_in;
      
      for( cOrInd = 0; cOrInd < cMUXwidth; cOrInd = cOrInd + 1 ) begin: OrLoop
        localparam integer cOrLastBitInd  = ( cOrInd + 1 ) * cOrStep - 1;
        assign  mux_in[cOrInd] = |( di_a[ cOrLastBitInd : cOrLastBitInd - cOrWidth + 1 ]);
      end
      
      if(ind_bit != output_width - 1 ) 
        N_MUX #c_logMUXwidth NM( mux_in, do_y[ output_width-1 : ind_bit + 1], do_y[ ind_bit ] );
      else 
        assign do_y[ output_width - 1 ] = mux_in[0];
    end
  endgenerate

  assign  co_err = ~|di_a;

  endmodule
  
/////////////////////////////////////////////////////
module N_MUX #(
  parameter Num=1
  )( 
  input  logic [ 2**Num - 1 : 0 ] In,
  input  logic [ Num - 1    : 0 ] Sel,
  output logic                   Out
);

  genvar i,j;
  logic [ 2**Num - 1 : 0 ]  Sum;
  
  generate
    if(Num == 0) assign Sum = In;
    else begin
      for(i = 0; i < 2**Num; i = i + 1 ) begin: forloop
        logic [Num-1:0] mod, smod;
        
        assign mod = i;
        
        for(j = 0; j < Num; j = j + 1 ) begin: forloop1
          assign  smod[j] = ( mod[j] ) ? ( Sel[j] ) :
                                         ( ~Sel[j] );
        end
        
        assign  Sum[i] = &{ smod, In[i] };
      end
    end
  endgenerate
  
  assign  Out = | Sum;
  
endmodule

/////////////////////////////////////////////////////
module comparators #( // ex 5.8
  parameter LOGWIDTH = 5
  )(
  input   logic [2**LOGWIDTH-1:0] A, B,
  output  logic                   ne, le, mo 
);

  logic [2**LOGWIDTH-1:0] C;
  logic [LOGWIDTH-1:0]    d;
  
  assign  C = A ^ B;
  
  logic  m, e, nm_a;
  
  priority_coder  #LOGWIDTH PC(C,d,e);
  
  assign  ne = ~e;
  
  N_MUX #LOGWIDTH NMA(A,d,nm_a);
  
  assign mo = ( e ) ? ( 0 ) : ( nm_a );
  assign le = ~( mo );
  
endmodule 

      