`timescale 1ns/1ps // unit/precision
module sum_prefix(	input	logic [15:-1] A, B,
					output	logic [15:0 ] S,
					output	logic Cout );
	genvar i;
	logic [15:-1] P, G, Sxor;
	logic [7:0] PL1, PL2, PL3, PL4;
	logic [7:0] GL1, GL2, GL3, GL4;
	assign P = A|B;
	assign G = A&B;
	assign Sxor = A^B;
	// Prefix tree
	Prefix_L1 L1( P, G, PL1, GL1 );
	Prefix_L2 L2( P, G, PL1, GL1, PL2, GL2 );
	Prefix_L3 L3( P, G, PL1, GL1, PL2, GL2, PL3, GL3);
	Prefix_L4 L4( P, G, PL1, GL1, PL2, GL2, PL3, GL3, PL4, GL4);
	// Output logic
	assign S	= { GL4, GL3[3:0], GL2[1:0], GL1[0], G[-1] } ^ Sxor[15:0];
	PGL mCout( P[15], PL4[7], G[15], GL4[7], ,Cout );
endmodule 

module Prefix_L1(	input	logic	[15:-1] P, G,
					output	logic	[7:0] PL1, GL1);
	genvar i;
	generate 
		for( i = 0; i < 8; i = i + 1 ) begin: forloop1
			PGL m1( P[ 2*i ], P[ 2*i - 1 ], G[ 2*i ], G[ 2*i - 1 ], PL1[i], GL1[i]);
		end
	endgenerate
endmodule

module Prefix_L2(	input	logic	[15:-1] P, G,
					input	logic		[7:0] PL1, GL1,
					output	logic	[7:0] PL2, GL2);
	genvar i;
	generate 
		for( i = 0; i < 4; i = i + 1 ) begin: forloop2
			PGL m21( PL1[ 2*i + 1 ], PL1[2*i], GL1[2*i+1],	GL1[2*i],PL2[2*i+1],GL2[2*i+1]);
			PGL m22( P[   4*i + 1 ], PL1[2*i], G[  4*i+1],	GL1[2*i],PL2[2*i  ],GL2[2*i  ]);
		end
	endgenerate	
endmodule

module Prefix_L3(	input logic		[15:-1] P, G,
					input logic		[7:0] PL1, GL1,
					input logic		[7:0] PL2, GL2,
					output logic	[7:0] PL3, GL3);
	genvar i;
	generate 
		for(i=0;i<2;i=i+1) begin: forloop3
			PGL m31(PL2[4*i+3], PL2[4*i+1], GL2[4*i+3], GL2[4*i+1],PL3[4*i+3],GL3[4*i+3]);
			PGL m32(PL2[4*i+2], PL2[4*i+1], GL2[4*i+2], GL2[4*i+1],PL3[4*i+2],GL3[4*i+2]);
			PGL m33(PL1[4*i+2], PL2[4*i+1], GL1[4*i+2], GL2[4*i+1],PL3[4*i+1],GL3[4*i+1]);
			PGL m34(  P[8*i+3], PL2[4*i+1],   G[8*i+3], GL2[4*i+1],PL3[4*i  ],GL3[4*i  ]);
		end
	endgenerate	
endmodule

module Prefix_L4(	input logic		[15:-1] P, G,
					input logic		[7:0] PL1, GL1,
					input logic		[7:0] PL2, GL2,
					input logic		[7:0] PL3, GL3,
					output logic	[7:0] PL4, GL4);
	 genvar i;
	generate 
		for(i=0;i<4;i=i+1) begin: forloop41
			PGL m41(PL3[i+4], PL3[3], GL3[i+4], GL3[3],PL4[i+4],GL4[i+4]);
		end
		for(i=0;i<2;i=i+1) begin: forloop42
			PGL m42(PL2[i+4], PL3[3], GL2[i+4], GL3[3],PL4[i+2],GL4[i+2]);
		end
	endgenerate
	PGL m43(PL1[4], PL3[3], GL1[4], GL3[3],PL4[1],GL4[1]);
	PGL m44(  P[7], PL3[3],   G[7], GL3[3],PL4[0],GL4[0]);
endmodule

module PGL(	input logic P1,P2,G1,G2,
			output logic Pout, Gout	);
	assign Pout = P1 & P2;
	assign Gout = (P1 & G2) | G1;
endmodule
			


module Testbench2
#(parameter input_width = 16)
();
logic clk, reset;
logic [input_width-1:0] a,b;
logic [input_width-1:0] y, yexpected;
logic overflow, ofexpected;
logic [31:0] vectornum, errors;
logic [input_width*3:0] testvectors[10000:0]; //[input_width*3-1:0] testvectors[10000:0]; 
// instantiate under test
sum_prefix dut({a,1'b0} ,{b,1'b0},y,overflow);
// generate clock
always
	begin
		clk=1; #5; clk=0; #5;
	end
// at start, load vectors and pulse reset
initial
	begin
		$readmemh("../../Excercises/test2.tv",testvectors);
		vectornum = 0; errors = 0;
		reset = 1; #27; reset=0;
	end	
// apply test vectors on rising edge of clk
always@(posedge clk)
	begin
		#1; {a[input_width-1:0],b[input_width-1:0],yexpected[input_width-1:0],ofexpected}=testvectors[vectornum];
	end
// check at falling edge of clk
always@(negedge clk)
	if(~reset) begin // skip during reset
		if(yexpected != y) begin
			$display("Error: inputs = %d,%d",a,b);
			$display(" outputs = %d (%d expected)",y,yexpected);
			errors += 1;
		end
		if(ofexpected != overflow) begin
			$display("Error: inputs = %d,%d",a,b);
			$display(" outputs_overflow = %d (%d expected)",overflow,ofexpected);
			errors += 1;
		end
		vectornum += 1;
		if(testvectors[vectornum][0] === 1'bx) begin
			$display("%d tests complete with %d errors", vectornum, errors);
			$finish;
		end
	end
endmodule
