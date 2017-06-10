// synopsys translate_off
`timescale 1 ps / 1 ps
// synopsys translate_on
module RAM_L1 #(
  parameter ROLE //  0 for Instruction memory/L1i cache, 1 for data memory/ L1d cache
)(
	aclr,
	address,
	addressstall_a,
	clken,
	clock,
	data,
	rden,
	wren,
	q
);

	input	  aclr;
	input	[7:0]  address;
	input	  addressstall_a;
	input	  clken;
	input	  clock;
	input	[31:0]  data;
	input	  rden;
	input	  wren;
	output	[31:0]  q;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_off
`endif
	tri0	  aclr;
	tri0	  addressstall_a;
	tri1	  clken;
	tri1	  clock;
	tri1	  rden;
`ifndef ALTERA_RESERVED_QIS
// synopsys translate_on
`endif

	wire [31:0] sub_wire0;
	wire [31:0] q = sub_wire0[31:0];

	altsyncram	altsyncram_component (
				.aclr0          (           aclr ),
				.address_a      (        address ),
				.addressstall_a ( addressstall_a ),
				.clock0         (          clock ),
				.clocken0       (          clken ),
				.data_a         (           data ),
				.rden_a         (           rden ),
				.wren_a         (           wren ),
				.q_a            (      sub_wire0 ),
				.aclr1          (           1'b0 ),
				.address_b      (           1'b1 ),
				.addressstall_b (           1'b0 ),
				.byteena_a      (           1'b1 ),
				.byteena_b      (           1'b1 ),
				.clock1         (           1'b1 ),
				.clocken1       (           1'b1 ),
				.clocken2       (           1'b1 ),
				.clocken3       (           1'b1 ),
				.data_b         (           1'b1 ),
				.eccstatus      (                ),
				.q_b            (                ),
				.rden_b         (           1'b1 ),
				.wren_b         (           1'b0 )
  );
	defparam
		altsyncram_component.clock_enable_input_a = "NORMAL",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.init_file = ( ROLE == 0 ) ? "../../Source/MIPS/L1i.mif" :  "../../Source/MIPS/L1d.mif",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 256,
		altsyncram_component.operation_mode = "SINGLE_PORT",
		altsyncram_component.outdata_aclr_a = "CLEAR0",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = 8,
		altsyncram_component.width_a = 32,
		altsyncram_component.width_byteena_a = 1;


endmodule