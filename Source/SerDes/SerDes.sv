`timescale 1ns/1ps // unit/precision

module  DeSerializer#(
  parameter LOGWIDTH = 5
  )( 
  input   logic                     Clk,
  input   logic                     Srst,
  input   logic                     Init,
  
  input   logic                     In,
  output  logic   [2**LOGWIDTH-1:0] Out,
  
  output  logic                     Ready 
);
      
  logic   [LOGWIDTH - 1    :0] Ind;
  //logic                           Init_hold;
  //logic   [2**LOGWIDTH - 1 :0] Buf;
  
  //assign Out   = Buf[0];
    
  always_ff@(posedge  Clk)  
    if( Srst )
    begin
      Ready <= 1;
      Ind   <= 0;
      Out   <= 0;
    end
    else
    begin
      if( Ready )
      begin
        if( Init )
        begin
          Out[2**LOGWIDTH - 1]   <= In;
          Ready                  <= 0;
          Ind                    <= 0;
        end
      end  
      else
      begin
        if( &Ind )  
        begin
          Ready <= 1;
        end
        else
        begin
          Out <= Out >> 1;
          Out[2**LOGWIDTH - 1]   <= In;
          Ind <= Ind + 1;
        end
      end
    end
endmodule

module  Serializer#(
  parameter LOGWIDTH = 5
  )( 
  input   logic                     Clk,
  input   logic                     Srst,
  input   logic                     Init,
  
  input   logic   [2**LOGWIDTH-1:0] In,
  output  logic                     Out,
  
  output  logic                     Ready 
);
      
  logic   [LOGWIDTH - 1    :0] Ind;
  //logic                           Init_hold;
  logic   [2**LOGWIDTH - 1 :0] Buf;
  
  assign Out   = Buf[0];
    
  always_ff@(negedge  Clk)  
    if( Srst )
    begin
      Ready <= 1;
      Ind   <= 0;
      Buf   <= 0;
    end
    else
    begin
      if( Ready )
      begin
        if( Init )
        begin
          Buf   <= In;
          Ready <= 0;
          Ind   <= 0;
        end
      end  
      else
      begin
        if( &Ind )  
          Ready <= 1;
        Buf <= Buf >> 1;
        Ind <= Ind + 1;
      end
    end
endmodule


module Testbench_SerDes#(
  parameter LOGWIDTH = 5
  )(
);
  
  logic clk, Srst;
  
  logic [2**LOGWIDTH - 1 :0] y_out, dut3_Out;
  logic                      a_out;
  
  logic [2**LOGWIDTH - 1 :0] dut2_In, DeS_expected;
  logic                      dut3_In, dut1_In, y, yexpected; 
  
  logic                      Init, dut1_Init, dut3_Init; //, dut3_Init_hold;
  
  logic                      Rd_DeS, Rd_Ser, Rd_dut3;
  
  logic [2**LOGWIDTH - 1 :0] testvectors[10000:0]; 
  logic [31:0]               vectornum, errors;
  logic [LOGWIDTH - 1    :0] bit_cnt, bit_cnt_DeS; 
  
  logic   trash;
  
  // instantiate under test
  DeSerializer  dut_DeS(  .Clk(clk), .Srst(Srst), .Init(dut1_Init),      .In(dut1_In), .Out(y_out),    .Ready(Rd_DeS)  );
  Serializer    dut_Ser(  .Clk(clk), .Srst(Srst), .Init(Init),      .In(dut2_In),       .Out(a_out),    .Ready(Rd_Ser)  );
  DeSerializer  dut_Comb( .Clk(clk), .Srst(Srst), .Init(dut3_Init), .In(dut3_In), .Out(dut3_Out), .Ready(Rd_dut3) );
  
  // generate clock
  always  begin
      clk=0; #5; clk=1; #5;
  end
  
  // at start, load vectors and pulse Srst
  initial
    begin
      $readmemh("../../Source/ALU/test_SerDes.tv",testvectors);
      vectornum = 0; errors = 0; bit_cnt = 0;
      Srst = 1; #27; Srst=0;
    end 
    
  // apply input values on rising edge of clk
  always@(posedge clk)
  begin
    DeS_expected = dut2_In;
    if(Init && !trash) begin
      #1; bit_cnt = 0;
      trash=1;
    end else begin
      #1; bit_cnt = bit_cnt+1;
      trash = 0;
    end
  end
  always@(negedge clk)
  begin
    dut1_Init = Init;
    bit_cnt_DeS = bit_cnt;
    #1;
    y      = testvectors[vectornum][bit_cnt];
    dut1_In = testvectors[vectornum][bit_cnt_DeS];
  end
  always@(posedge Init) begin //SET the vectors BEFORE Setting up Init!!!
      #1;
      dut2_In      = testvectors[vectornum];
  end
  
  // Initiation logic
  always begin
    Init = 0;
    #355;
    Init=1; #15;
  end
  
  // Pairing logic for dut3
  //always_ff @( posedge clk )
  //begin
  // dut3_Init      = ( dut3_Init_hold ) ? (1'b0 ) : ( !Rd_Ser );
	// dut3_Init_hold = dut3_Init || (!Rd_Ser);
  //end
  assign dut3_Init = !Rd_Ser;
  assign dut3_In  = a_out;
  
  
  // Checking logic ----------------
  
  //// DeSerialiser
  // check at falling edge of clk
  always@(negedge clk) 
  if( ~Srst && vectornum != 0 ) begin // skip during Srst and pre-first vector time
      if(Rd_DeS) begin
        //$display("vectornum = %d outputs = %h (%h expected)", vectornum, y_out, testvectors[vectornum]);
        if(y_out !== DeS_expected /* testvectors[vectornum]*/ ) begin
          $display("DeSerializer Error: vectornum = %d",vectornum);
          $display(" outputs = %h (%h expected)",y_out, DeS_expected ); //testvectors[vectornum]);
          errors += 1;
      end
    end
  end
  
  ////Serialiser
  // check at Rising edge of clk
  always@(posedge clk) 
  if( ~Srst && vectornum != 0 ) begin // skip during Srst and pre-first vector time 
    if(!Rd_Ser) begin
      if(a_out !== testvectors[vectornum][bit_cnt]) begin
        $display("Serializer Error: vectornum = %d",vectornum);
        $display(" outputs = %b (%b expected)",a_out,testvectors[vectornum][bit_cnt]);
        // $display("vectornum = %d outputs = %b (%b expected)", vectornum, a_out, testvectors[vectornum][bit_cnt]);
        errors += 1;
      end
    end
  end
  
  //// Combination
  // check at falling edge of clk
  always@(negedge clk) 
  if( ~Srst && vectornum != 0 ) begin // skip during Srst and pre-first vector time 
      if(Rd_dut3) begin
        $display("vectornum = %d outputs = %h (%h expected)", vectornum, dut3_Out, DeS_expected);
        // if(dut3_Out !== DeS_expected) begin 
          // $display("Combination Error: vectornum = %d",vectornum);
          // $display(" outputs = %h (%h expected)",dut3_Out, DeS_expected);
          // errors += 1;
      // end
    end
  end
  
  // Finalization logic ------------
  always@(posedge Init)
  if(~Srst) begin // skip during Srst
      vectornum += 1;
      if(testvectors[vectornum][0] === 1'bx) begin
        $display("%d tests complete with %d errors", vectornum, errors);
        $finish;
      end
  end
endmodule