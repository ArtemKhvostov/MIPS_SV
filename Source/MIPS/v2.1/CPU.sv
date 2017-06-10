////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Memory and caches module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module Mem_Cache #(
  parameter  ROLE //  0 for Instruction memory/L1i cache, 1 for data memory/ L1d cache, 2 for unified memory/ L2 cache
  )(
  input logic          clk,
  input logic          we,

  input logic   [31:0] a, wd,
  output  logic [31:0] rd
);

  logic [31:0] RAM[63:0]; // [31:0] RAM[63:0] originally; 64 is whole size, not log

  initial begin
    if ( ROLE == 0) $readmemb("../../Source/MIPS/memfileL1i.dat", RAM);
    if ( ROLE == 1) $readmemh("../../Source/MIPS/memfileL1d.dat", RAM);
    if ( ROLE == 2) $readmemh("../../Source/MIPS/memfileL2.dat",  RAM);
  end

  assign rd = RAM[a[31:2]]; // word aligned

  always @(posedge clk) if (we) RAM[a[31:2]] <= wd;

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// CPU top module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module CPU (
  input   logic         clk, ci_rst,
  input   logic         ciInstInp,
  input   logic [31:0]  diInstToMem,
  input   logic [ 7:0]  diInstAddr,
  
  output  logic [31:0]  writedataM, adrM,
  output  logic         memwriteM,
  
  output  logic [31:0]  writedataR, adrR,
  output  logic         memwriteR
);

  logic [31:0]  readdata;
  assign        readdata    = 32'b0;
  // instantiate processor and memories
  MIPS MIPS(
    .clk            ( clk         ),
    .ci_rst         ( ci_rst      ),
                      
    .ciInstInp      ( ciInstInp   ),
    .diInstToMem    ( diInstToMem ),
    .diInstAddr     ( diInstAddr  ),
                      
    .readdata       ( readdata    ),
                      
    .doadrM         ( adrM        ),
    .dowritedataM   ( writedataM  ),
    .domemwriteM    ( memwriteM   ),
                      
    .doadrR         ( adrR        ),
    .dowritedataR   ( writedataR  ),
    .domemwriteR    ( memwriteR   )
  );
//  Mem_Cache #2  mem (clk, memwrite, adr, writedata, readdata);
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Main processor module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS
(
  input  logic         clk, ci_rst,

  input  logic         ciInstInp,
  input  logic  [31:0] diInstToMem,
  input  logic  [ 7:0] diInstAddr, 
  
  input  logic  [31:0] readdata,

  output logic  [31:0] doadrM,
  output logic  [31:0] dowritedataM,
  output logic         domemwriteM,

  output logic  [31:0] doadrR,
  output logic  [31:0] dowritedataR,
  output logic         domemwriteR
);
  // ++++++++++++++++++++++++ Control logic ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [5:0] cOpcode, cFunct;
  logic       cMemtoRegD, cMemWriteD, cJumpD;
  logic       cALUSrcD, cRegDstD, cRegWriteD;
  logic [2:0] cALUControlD;
  logic [31:0] dInstrD;
  logic       cBranchD, cPCSrcD, cEqualD;

  assign    cOpcode = dInstrD[ 31: 26];
  assign    cFunct  = dInstrD[  5:  0];
  MIPS_CU   CU(
    .diOpcode     ( cOpcode       ),
    .diFunct      ( cFunct        ),
    .ciEqualD     ( cEqualD       ),
    .coMemtoReg   ( cMemtoRegD    ),
    .coMemWrite   ( cMemWriteD    ),
    .coPCSrcD     ( cPCSrcD       ),
    .coALUSrc     ( cALUSrcD      ),
    .coRegDst     ( cRegDstD      ),
    .coRegWrite   ( cRegWriteD    ),
    .coJump       ( cJumpD        ),
    .coBranchD    ( cBranchD      ),
    .coALUControl ( cALUControlD  )
  );

  // ++++++++++++++++++++++++ Hazard unit ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic           cStallF,    cStallD;
  logic           cForwardAD, cForwardBD;
  logic  [ 1:0]   cForwardAE, cForwardBE;
  logic  [ 4:0]   dRsD,       dRtD;
  logic  [ 4:0]   dRsE,       dRtE;
  logic           cFlushE;
  logic  [ 4:0]   dWriteRegE, dWriteRegM, dWriteRegW;
  logic           cMemtoRegE, cMemtoRegM;
  logic           cRegWriteE, cRegWriteM, cRegWriteW;

  MIPS_HU  HU(
    .ciBranchD    ( cBranchD      ),

    .ciMemtoRegE  ( cMemtoRegE    ),
    .ciMemtoRegM  ( cMemtoRegM    ),
    .ciRegWriteE  ( cRegWriteE    ),
    .ciRegWriteM  ( cRegWriteM    ),
    .ciRegWriteW  ( cRegWriteW    ),

    .diRsD        ( dRsD          ),
    .diRtD        ( dRtD          ),
    .diRsE        ( dRsE          ),
    .diRtE        ( dRtE          ),

    .diWriteRegE  ( dWriteRegE    ),
    .diWriteRegM  ( dWriteRegM    ),
    .diWriteRegW  ( dWriteRegW    ),

    .coStallF     ( cStallF       ),
    .coStallD     ( cStallD       ),

    .coForwardAD  ( cForwardAD    ),
    .coForwardBD  ( cForwardBD    ),
    .coForwardAE  ( cForwardAE    ),
    .coForwardBE  ( cForwardBE    ),

    .coFlushE     ( cFlushE       )
  );

  // ++++++++++++++++++++++++ Pipeline stage    1: Fetch +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dPCBranchD;
  logic [31:0] dPCPlus4F;
  logic [31:0] dInstrF;
  logic [25:0] dJumpDst;

  MIPS_IF  IF(
    .clk          ( clk           ),
    .ci_rst       ( ci_rst        ),
    .ciInstInp    ( ciInstInp     ),
    .diInstToMem  ( diInstToMem   ),
    .diInstAddr   ( diInstAddr    ),
    .diJumpDst    ( dJumpDst      ),
    .diPCBranchD  ( dPCBranchD    ),
    .ciJump       ( cJumpD        ),
    .ciPCSrcD     ( cPCSrcD       ),
    .ciStallF     ( cStallF       ),
    .doInstr      ( dInstrF       ),
    .doPCPlus4F   ( dPCPlus4F     )
  );

  // ++++++++++++++++++++++++ Pipeline register 1 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dPCPlus4D;

  MIPS_PR #(
    .WIDTH (  32 + 32  )
  )  PR1   (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cPCSrcD || cJumpD || ciInstInp ),
    .EN    ( !cStallD  ),

    .dIn   ( { dInstrF, dPCPlus4F } ),
    .dOut  ( { dInstrD, dPCPlus4D } )
  );

  // ++++++++++++++++++++++++ Pipeline stage    2: Decode ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dResultM, dResultW, dALUOutM, dSignImmD, dRF_RD1_D, dRF_RD2_D;
  logic [ 4:0] dRdD, dRdE;

  MIPS_ID  ID(
    .clk          ( clk           ),
    .ci_rst       ( ci_rst        ),
    .diInstrD     ( dInstrD       ),
    .diPCPlus4D   ( dPCPlus4D     ),
    
    //.diWriteRegW  ( dWriteRegW    ),
    .diWriteRegW  ( dWriteRegM    ),
    
    //.diResultW    ( dResultW      ),
    .diResultW    ( dResultM      ),
    
    .diALUOutM    ( dALUOutM      ),
    .ciForwardAD  ( cForwardAD    ),
    .ciForwardBD  ( cForwardBD    ),
    
    //.ciRegWriteW  ( cRegWriteW    ),
    .ciRegWriteW  ( cRegWriteM    ),
    
    .doJumpDst    ( dJumpDst      ),
    .doRsD        ( dRsD          ),
    .doRtD        ( dRtD          ),
    .doRdD        ( dRdD          ),
    .doPCBranchD  ( dPCBranchD    ),
    .doSignImmD   ( dSignImmD     ),
    .doRF_RD1     ( dRF_RD1_D     ),
    .doRF_RD2     ( dRF_RD2_D     ),
    .coEqualD     ( cEqualD       )
  );
  
  // debug outputs
  assign doadrR       = { 27'h0, dWriteRegW };
  assign dowritedataR = dResultW;
  assign domemwriteR  = cRegWriteW;
  
  // ++++++++++++++++++++++++ Pipeline register 2 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Datapath part
  logic [31:0] dRF_RD1_E, dRF_RD2_E, dSignImmE;

  MIPS_PR #(
    .WIDTH (  32 + 32 + 5 + 5 + 5 + 32 )
  )  PR2D  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushE   ),
    .EN    ( 1'b1      ),

    .dIn   ( { dRF_RD1_D, dRF_RD2_D, dRsD, dRtD, dRdD, dSignImmD } ),
    .dOut  ( { dRF_RD1_E, dRF_RD2_E, dRsE, dRtE, dRdE, dSignImmE } )
  );

  // Control part
  logic       cMemWriteE, cALUSrcE, cRegDstE;
  logic [2:0] cALUControlE;

  MIPS_PR #(
    .WIDTH (   1 + 1 + 1 + 3 + 1 + 1 )
  )  PR2C  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushE   ),
    .EN    ( 1'b1      ),

    .dIn   ( { cRegWriteD, cMemtoRegD, cMemWriteD, cALUControlD, cALUSrcD, cRegDstD } ),
    .dOut  ( { cRegWriteE, cMemtoRegE, cMemWriteE, cALUControlE, cALUSrcE, cRegDstE } )
  );

  // ++++++++++++++++++++++++ Pipeline stage    3: Execute +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dALUOutE, dWriteDataE;

   MIPS_EX  EX(
    .diRF_RD1      ( dRF_RD1_E     ),
    .diRF_RD2      ( dRF_RD2_E     ),

    .diRtE         ( dRtE          ),
    .diRdE         ( dRdE          ),

    .diSignImmE    ( dSignImmE     ),

    .diALUOutM     ( dALUOutM      ),
    .diResultW     ( dResultW      ),

    .ciForwardAE   ( cForwardAE    ),
    .ciForwardBE   ( cForwardBE    ),

    .ciRegDstE     ( cRegDstE      ),
    .ciALUSrcE     ( cALUSrcE      ),
    .ciALUControlE ( cALUControlE  ),

    .doALUOutE     ( dALUOutE      ),
    .doWriteDataE  ( dWriteDataE   ),
    .doWriteRegE   ( dWriteRegE    )
  );

  // ++++++++++++++++++++++++ Pipeline register 3 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Datapath part
  logic [31:0] dWriteDataM;

  MIPS_PR #(
    .WIDTH (  32 + 32 + 5 )
  )  PR3D  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( 1'b0      ),
    .EN    ( 1'b1      ),

    .dIn   ( { dALUOutE, dWriteDataE, dWriteRegE } ),
    .dOut  ( { dALUOutM, dWriteDataM, dWriteRegM } )
  );

  // Control part
  logic cMemWriteM;

  MIPS_PR #(
    .WIDTH (  1 + 1 + 1 )
  )  PR3C  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( 1'b0      ),
    .EN    ( 1'b1      ),

    .dIn   ( { cRegWriteE, cMemtoRegE, cMemWriteE } ),
    .dOut  ( { cRegWriteM, cMemtoRegM, cMemWriteM } )
  );

  // ++++++++++++++++++++++++ Pipeline stage    4: Memory ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dReadDataM;

  //MIPS_MEM  MEM(
  //  .clk          ( clk ),
  //  .ci_rst       ( ci_rst ),
  //
  //  .diALUOutM    ( dALUOutM ),
  //  .diWriteDataM ( dWriteDataM ),
  //
  //  .ciMemWriteM  ( cMemWriteM ),
  //
  //  .doReadDataM  ( dReadDataM )
  //);

  RAM_L1 #1 MemDat  (
    .aclr           (           ci_rst ),
    .address        (    dALUOutE[9:2] ), // TODO: Out-of range exception
    .addressstall_a (             1'b0 ),
    .clken          (             1'b1 ),
    .clock          (              clk ),
    .data           (      dWriteDataE ),
    .rden           (             1'b1 ),
    .wren           (       cMemWriteE ),
    .q              (       dReadDataM )
  );
  
  
  assign  dResultM = ( cMemtoRegM ) ? ( dReadDataM ) : ( dALUOutM );
  
  // debug outputs
  assign doadrM       = dALUOutM;
  assign dowritedataM = dWriteDataM;
  assign domemwriteM  = cMemWriteM;
  // ++++++++++++++++++++++++ Pipeline register 4 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Datapath part
  logic [31:0] dReadDataW, dALUOutW;
  
  MIPS_PR #( 
    .WIDTH (  32 + 5 ) 
  )  PR4D  (  
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( 1'b0      ),
    .EN    ( 1'b1      ),
    
    .dIn   ( { dResultM, dWriteRegM } ),
    .dOut  ( { dResultW, dWriteRegW } ) 
  );     
         
  // Control part
  logic      cMemtoRegW;

  MIPS_PR #( 
    .WIDTH (  1 + 1 ) 
  )  PR4C  (  
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( 1'b0      ),
    .EN    ( 1'b1      ),
     
    .dIn   ( { cRegWriteM, cMemtoRegM } ),
    .dOut  ( { cRegWriteW, cMemtoRegW } ) 
  );     
  
  // ++++++++++++++++++++++++ Pipeline stage    5: Writeback +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // NULL

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline registers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module  MIPS_PR #(
  parameter WIDTH = 1
  )(
  input  logic                clk,
  input  logic                rst,
  input  logic                clr,
  input  logic                EN,
  input  logic [ WIDTH-1 :0 ] dIn,
  output logic [ WIDTH-1 :0 ] dOut
);
  always_ff@( posedge clk or posedge rst )
  begin
    if( rst )
    begin
      dOut  <= 0;
    end else
    if( EN ) begin
      dOut  <= ( clr ) ? ( 0 ) : ( dIn );
    end
  end
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Control unit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_CU  (
  input  logic [ 5:0] diOpcode, diFunct,
  input  logic        ciEqualD,
  output logic        coMemtoReg,
  output logic        coMemWrite,
  output logic        coPCSrcD,
  output logic        coALUSrc,
  output logic        coRegDst,
  output logic        coRegWrite,
  output logic        coJump,
  output logic        coBranchD,
  output logic [2:0] coALUControl
);

  logic [1:0] dALUOp; // from main decoder to ALU decoder

  // Main decoder
  logic [8:0] dDecOut;
  assign  { coRegWrite, coRegDst, coALUSrc, coBranchD, coMemWrite, coMemtoReg, dALUOp, coJump} = ( |{ diOpcode, diFunct } ) ? dDecOut : 0; // NOP detection
  always_comb case (diOpcode)
    6'b000000:  dDecOut = 9'b110000100; // R-type
    6'b100011:  dDecOut = 9'b101001000; // lw
    6'b101011:  dDecOut = 9'b001010000; // sw
    6'b000100:  dDecOut = 9'b000100010; // beq
    6'b001000:  dDecOut = 9'b101000000; // addi
    6'b000010:  dDecOut = 9'b000000001; // Jump
    default:    dDecOut = 9'bxxxxxxxxx; // error case
  endcase

  // ALU Decoder
  always_comb casex ( { dALUOp, diFunct } )
    8'b00xxxxxx: coALUControl  = 3'b010; //  add
    8'b01xxxxxx: coALUControl  = 3'b110; //  sub
    8'b10100000: coALUControl  = 3'b010; //  add
    8'b10100010: coALUControl  = 3'b110; //  sub
    8'b10100100: coALUControl  = 3'b000; //  AND
    8'b10100101: coALUControl  = 3'b001; //  OR
    8'b10101010: coALUControl  = 3'b111; //  SLT
    default:     coALUControl  = 3'bxxx; //  error case
  endcase

  assign    coPCSrcD = coBranchD & ciEqualD;

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Hazard unit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_HU  (
  input  logic        ciBranchD,

  input  logic        ciMemtoRegE,
  input  logic        ciMemtoRegM,
  input  logic        ciRegWriteE,
  input  logic        ciRegWriteM,
  input  logic        ciRegWriteW,

  input  logic [ 4:0] diRsD,
  input  logic [ 4:0] diRtD,
  input  logic [ 4:0] diRsE,
  input  logic [ 4:0] diRtE,

  input  logic [ 4:0] diWriteRegE,
  input  logic [ 4:0] diWriteRegM,
  input  logic [ 4:0] diWriteRegW,

  output logic        coStallF,
  output logic        coStallD,

  output logic        coForwardAD,
  output logic        coForwardBD,
  output logic [ 1:0] coForwardAE,
  output logic [ 1:0] coForwardBE,

  output logic        coFlushE
);
  // Bypass from Memory and Writeback to Execute
  always_comb begin
    if ( ( diRsE != 0 ) && ( diRsE == diWriteRegM ) && ( ciRegWriteM ) ) begin 
      coForwardAE = 2'b10;
    end else 
    if ( ( diRsE != 0 ) && ( diRsE == diWriteRegW ) && ( ciRegWriteW ) ) begin
      coForwardAE = 2'b01;
    end else begin
      coForwardAE = 2'b00;
    end
  end
  
  always_comb begin
    if ( ( diRtE != 0 ) && ( diRtE == diWriteRegM ) && ( ciRegWriteM ) ) begin 
      coForwardBE = 2'b10;
    end else 
    if ( ( diRtE != 0 ) && ( diRtE == diWriteRegW ) && ( ciRegWriteW ) ) begin
      coForwardBE = 2'b01;
    end else begin
      coForwardBE = 2'b00;
    end
  end
  
  // Bypass and stall for branch
  logic  cBranchStall;
  assign coForwardAD  = ( diRsD != 0 ) && ( diRsD == diWriteRegM ) && ( ciRegWriteM );
  assign coForwardBD  = ( diRtD != 0 ) && ( diRtD == diWriteRegM ) && ( ciRegWriteM );
  assign cBranchStall = ( ciBranchD && ciRegWriteE && ( ( diWriteRegE == diRsD ) || ( diWriteRegE == diRtD ) ) ) ||
                        ( ciBranchD && ciMemtoRegM && ( ( diWriteRegM == diRsD ) || ( diWriteRegM == diRtD ) ) );
  
  // Stall
  logic  clwstall;
  assign clwstall = ( ( ( diRsD == diRtE) || ( diRtD == diRtE) ) && ( ciMemtoRegE ) );
  assign coFlushE = ( clwstall || cBranchStall );
  assign coStallD = coFlushE;
  assign coStallF = coStallD;
  
  
  
  
endmodule


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 1: Fetch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_IF  (
  input  logic        clk,
  input  logic        ci_rst,
  
  input  logic        ciInstInp,    // for debug purposes
  input  logic [31:0] diInstToMem,  // for debug purposes
  input  logic [ 7:0] diInstAddr,   // for debug purposes
  
  input  logic [25:0] diJumpDst,
  input  logic [31:0] diPCBranchD,
  input  logic        ciJump,
  input  logic        ciPCSrcD,
  input  logic        ciStallF,
  
  output logic [31:0] doInstr,
  output logic [31:0] doPCPlus4F
);
  // Instruction memory
  logic [31:0]  dPCF, dPCF2;  // Program Counter и Instr для Instruction Memory; Duplicating for placing Instr cache to M10K
  logic [ 7:0]  dIMAddr;
  
  
   // PC register and Jump logic
  logic [31:0]  dPCset, dPCJump;

  assign  dPCJump     = { doPCPlus4F[31:28], diJumpDst, 2'b00 };
  assign  doPCPlus4F  = dPCF2 + 4'h4;
  assign  dPCset      = ( ciJump ) ? ( dPCJump   ) :
                                     ( ciPCSrcD  ) ? ( diPCBranchD ) : ( doPCPlus4F );
  
  // Instruction memory and program counter register  
  assign dIMAddr = ( ci_rst ) ?    8'h00 :
                             ( ciInstInp ) ? ( diInstAddr ) : ( /*dPCF[9:2]*/dPCset[9:2] );  // TODO: make exception when adderss > 32'h000000FF
  // assign dIMAddr = ( ciInstInp ) ? ( diInstAddr ) : ( dPCF );
  // Mem_Cache #0  MemInst ( .clk( clk ), .we( ciInstInp ), .a( dIMAddr ), .wd( diInstToMem ), .rd( doInstr ) ); // модуль выдает данные на чтение сразу же, не зависимо от clk
  RAM_L1 #0	MemInst   (
	 .aclr           (               1'b0 ),
	 .address        (            dIMAddr ),
	 .addressstall_a (           ciStallF ),
	 .clken          (               1'b1 ),
	 .clock          (                clk ),
	 .data           (        diInstToMem ),
	 .rden           (               1'b1 ),
	 .wren           (          ciInstInp ),
	 .q              (            doInstr )
	);
  
  always_ff@( posedge clk or posedge ci_rst)
  begin
    if(ci_rst) begin
      dPCF   <= 0;
		  dPCF2  <= 0;
    end
    else begin 
	   if( !ciStallF ) begin
        dPCF   <= dPCset;
        dPCF2  <= dPCset;
      end
      else begin
        dPCF   <= dPCF; 
        dPCF2  <= dPCF2;
      end
    end
  end

  
  
  
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 2: Decode
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_ID  (
  input  logic        clk,
  input  logic        ci_rst,
  input  logic [31:0] diInstrD,
  input  logic [31:0] diPCPlus4D,
  input  logic [ 4:0] diWriteRegW,
  input  logic [31:0] diResultW,
  input  logic [31:0] diALUOutM,
  input  logic        ciForwardAD,
  input  logic        ciForwardBD,
  input  logic        ciRegWriteW,
  output logic [25:0] doJumpDst,
  output logic [ 4:0] doRsD,
  output logic [ 4:0] doRtD,
  output logic [ 4:0] doRdD,
  output logic [31:0] doPCBranchD,
  output logic [31:0] doSignImmD,
  output logic [31:0] doRF_RD1,
  output logic [31:0] doRF_RD2,
  output logic        coEqualD
);
  // control constants
  integer  i;
  localparam REG_SIZE_LOG = 5;//let REG_SIZE_LOG = 5; // SystemVerilog-2012, not supported in quartus; can use localparam instead

  // Register File
  logic [31:0]  dREGFILE[ 2**REG_SIZE_LOG - 1 :0];

  assign  doRsD      = diInstrD[25:21];
  assign  doRtD      = diInstrD[20:16];
  assign  doRdD      = diInstrD[15:11];

  assign  doRF_RD1   = dREGFILE[doRsD];
  assign  doRF_RD2   = dREGFILE[doRtD];

  always_ff@( posedge clk or posedge ci_rst )
  begin
    if( ci_rst )
      for( i = 0; i < 2**REG_SIZE_LOG; i = i + 1 )
          dREGFILE[i] <= 0;
    else
      if ( ciRegWriteW && diWriteRegW !=0 ) dREGFILE[diWriteRegW] <= diResultW;
   end

   // EqualD logic
   logic [31:0]  dEq_RD1, dEq_RD2;

   assign  dEq_RD1  = ( ciForwardAD ) ? diALUOutM : doRF_RD1;
   assign  dEq_RD2  = ( ciForwardBD ) ? diALUOutM : doRF_RD2;
   assign  coEqualD = ( dEq_RD1 == dEq_RD2 );

  // Immediate, Jump and Branch logic
  assign  doSignImmD  = { {16{diInstrD[15]}}, diInstrD[15:0]}; //sign extend
  assign  doPCBranchD = diPCPlus4D + {doSignImmD[29:0],2'b00}; // TODO: replace with custom logic
  assign  doJumpDst   = diInstrD[25:0];

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 3: Execute
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_EX  (
  input  logic  [31:0]  diRF_RD1,
  input  logic  [31:0]  diRF_RD2,

  input  logic  [ 4:0]  diRtE,
  input  logic  [ 4:0]  diRdE,

  input  logic  [31:0]  diSignImmE,

  input  logic  [31:0]  diALUOutM,
  input  logic  [31:0]  diResultW,

  input  logic  [ 1:0]  ciForwardAE,
  input  logic  [ 1:0]  ciForwardBE,

  input  logic          ciRegDstE,
  input  logic          ciALUSrcE,
  input  logic  [ 2:0]  ciALUControlE,

  output logic  [31:0]  doALUOutE,
  output logic  [31:0]  doWriteDataE,
  output logic  [ 4:0]  doWriteRegE
);

  assign doWriteRegE  = ( ciRegDstE ) ? ( diRdE ) : ( diRtE );

  // ALU source logic
  logic [31:0]  dSrcAE, dSrcBE;

  always_comb case (ciForwardAE)
    2'b00:   dSrcAE       = diRF_RD1;
    2'b01:   dSrcAE       = diResultW;
    2'b10:   dSrcAE       = diALUOutM;
    default: dSrcAE       = 31'hxxxxxxxx;
  endcase

  always_comb case (ciForwardBE)
    2'b00:   doWriteDataE = diRF_RD2;
    2'b01:   doWriteDataE = diResultW;
    2'b10:   doWriteDataE = diALUOutM;
    default: doWriteDataE = 31'hxxxxxxxx;
  endcase

  assign dSrcBE   = ( ciALUSrcE ) ? ( diSignImmE ) : ( doWriteDataE );

  // ALU
  ALU   ALU ( .A(dSrcAE), .B(dSrcBE),.F(ciALUControlE),.Y(doALUOutE), .Cout(), .Oflow(), .Zero() );

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 4: Memory
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// In main module

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 5: Write back
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// In main module
