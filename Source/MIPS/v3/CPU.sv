////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// CPU top module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module CPU (
  input   logic         clk, ci_rst,
  input   logic         ciInstInp,
  input   logic [31:0]  diInstToMem,
  input   logic [31:0]  diInstAddr,
  
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
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Main processor module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS
(
  input  logic         clk, ci_rst,

  input  logic         ciInstInp,
  input  logic  [31:0] diInstToMem,
  input  logic  [31:0] diInstAddr, 
  
  input  logic  [31:0] readdata,

  output logic  [31:0] doadrM,
  output logic  [31:0] dowritedataM,
  output logic         domemwriteM,

  output logic  [31:0] doadrR,
  output logic  [31:0] dowritedataR,
  output logic         domemwriteR
);
  // ++++++++++++++++++++++++ Control logic ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [ 5:0]  cOpcode,    cFunct;
  logic         cMemtoRegD, cMemWriteD, cJumpD;
  logic         cALUSrcD,   cRegWriteD;
  logic         cXsSrc,     cXsFP,      cXtFP;
  logic [ 1:0]  cRegDstD,   cCMPmaskD;
  logic [ 2:0]  cALUControlD;
  logic [31:0]  dInstrD;
  logic         cBranchD,     cPCSrcD,        cEqualD;
  logic         cMemEnableD,  cFPBranchD,     cFPALU_Valid_M;
  logic         cFP_ALUen_D,  cFP_ALUen_E,    cFP_CVTen_D;
  logic         cFP_ALUCtrlD, cRegWrite_MovD, cCMPresult;

  assign    cOpcode = dInstrD[ 31: 26];
  assign    cFunct  = dInstrD[  5:  0];
  MIPS_CU   CU(
    .clk              ( clk             ),
    .rst              ( ci_rst          ),
    .diOpcode         ( cOpcode         ),
    .diFunct          ( cFunct          ),
    .ciRS             ( dInstrD[25:21]  ),
    .ciFPBranchCond   ( dInstrD[16]     ),
    .ciEqualD         ( cEqualD         ),
    .ciCMPresult      ( cCMPresult      ),
    .ciFPALU_Valid_M  ( cFPALU_Valid_M  ),
    .coMemtoReg       ( cMemtoRegD      ),
    .coMemWrite       ( cMemWriteD      ),
    .coMemEnableD     ( cMemEnableD     ),
    .coPCSrcD         ( cPCSrcD         ),
    .coALUSrc         ( cALUSrcD        ),
    .coRegDst         ( cRegDstD        ),
    .coXsSrc          ( cXsSrc          ),
    .coXsFP           ( cXsFP           ),
    .coXtFP           ( cXtFP           ),
    .coRegWrite       ( cRegWriteD      ),
    .coJump           ( cJumpD          ),
    .coBranchD        ( cBranchD        ),
    .coALUControl     ( cALUControlD    ),
    .coFP_ALUen       ( cFP_ALUen_D     ),
    .coFP_CVTen       ( cFP_CVTen_D     ),
    .coFP_ALUCtrl     ( cFP_ALUCtrlD    ),
    .coFPBranchD      ( cFPBranchD      ),
    .coRegWrite_Mov   ( cRegWrite_MovD  ),
    .coCMPmask        ( cCMPmaskD       )
  );

  // ++++++++++++++++++++++++ L2 memory ( M10K based dual port ) +++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [ 31:0] dMemL2_addr_i, dMemL2_addr_d;
  logic [127:0] dMemL2_D_i   , dMemL2_D_d;
  logic [127:0] dMemL2_Q_i   , dMemL2_Q_d;
  logic         cMemL2_WE_i  , cMemL2_WE_d;
  RAM_L2 #1  Memory (
    .address_a  ( dMemL2_addr_i[8:0] ),             // TODO: address overflow error detection
    .address_b  ( dMemL2_addr_d[8:0] ),
    .clock      (                clk ),
    .data_a     (         dMemL2_D_i ),
    .data_b     (         dMemL2_D_d ),
    .wren_a     (        cMemL2_WE_i ),
    .wren_b     (        cMemL2_WE_d ),
    .q_a        (         dMemL2_Q_i ),
    .q_b        (         dMemL2_Q_d )
  ); 
  
  // ++++++++++++++++++++++++ Hazard unit ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic           cStallF,    cStallD,    cStallE,    cStallM;
  logic           cStall_CacheM, cFPALU_Stall_M, cFP_ALUen_M;
  logic           cForwardAD, cForwardBD;
  logic  [ 1:0]   cForwardAE, cForwardBE;
  logic  [ 5:0]   dXsD,       dXtD;
  logic  [ 5:0]   dXsE,       dXtE;
  logic           cFlushE,    cFlushW;
  logic  [ 5:0]   dWriteRegE, dWriteRegM, dWriteRegW;
  logic           cRegWriteE, cRegWriteM, cRegWriteW;
  logic           cMemtoRegE, cMemtoRegM, cMemEnableM;

  MIPS_HU  HU(
    .ciBranchD       ( cBranchD       ),
    .ciFPBranchD     ( cFPBranchD     ),
                                      
    .ciMemtoRegE     ( cMemtoRegE     ),
    .ciMemtoRegM     ( cMemtoRegM     ),
    .ciFP_ALUen_E    ( cFP_ALUen_E    ),
    .ciFP_ALUen_M    ( cFP_ALUen_M    ),
    .ciRegWriteE     ( cRegWriteE     ),
    .ciRegWriteM     ( cRegWriteM     ),
    .ciRegWriteW     ( cRegWriteW     ),
    .ciStall_CacheM  ( cStall_CacheM  ),
    .ciFPALU_Stall_M ( cFPALU_Stall_M ),
    .ciMemEnableM    ( cMemEnableM    ),
                                      
    .diXsD           ( dXsD           ),
    .diXtD           ( dXtD           ),
    .diXsE           ( dXsE           ),
    .diXtE           ( dXtE           ),
                                      
    .diWriteRegE     ( dWriteRegE     ),
    .diWriteRegM     ( dWriteRegM     ),
    .diWriteRegW     ( dWriteRegW     ),
                                      
    .coStallF        ( cStallF        ),
    .coStallD        ( cStallD        ),
    .coStallE        ( cStallE        ),
    .coStallM        ( cStallM        ),
                                      
    .coForwardAD     ( cForwardAD     ),
    .coForwardBD     ( cForwardBD     ),
    .coForwardAE     ( cForwardAE     ),
    .coForwardBE     ( cForwardBE     ),
                                      
    .coFlushE        ( cFlushE        ),
    .coFlushW        ( cFlushW        )
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
    .ciFLUSH      ( cPCSrcD || cJumpD || ciInstInp ),
    .doInstr      ( dInstrF       ),
    .doPCPlus4F   ( dPCPlus4F     ),
    // Uplink memory interface
    .doUpMem_address         ( dMemL2_addr_i ),
    .coUpMem_clock           (),
    .doUpMem_data            (    dMemL2_D_i ),
    .coUpMem_wren            (   cMemL2_WE_i ),
    .diUpMem_q               (    dMemL2_Q_i ) 
  );

  // ++++++++++++++++++++++++ Pipeline register 1 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dPCPlus4D;

  PipelineReg #(
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
  logic [ 5:0] dRdD, dRdE, dFdD, dFdE;
  logic [ 1:0] dFP_CMP_M;

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
    .ciRegWriteW  ( cRegWriteM && !cStall_CacheM ),
    .ciRegWrite_MovD ( cRegWrite_MovD ),
    
    .ciXsSrc      ( cXsSrc        ), 
    .ciXsFP       ( cXsFP         ),  
    .ciXtFP       ( cXtFP         ),  
    
    .doJumpDst    ( dJumpDst      ),
    .doXsD        ( dXsD          ),
    .doXtD        ( dXtD          ),
    .doRdD        ( dRdD          ),
    .doFdD        ( dFdD          ),
    .doPCBranchD  ( dPCBranchD    ),
    .doSignImmD   ( dSignImmD     ),
    .doRF_RD1     ( dRF_RD1_D     ),
    .doRF_RD2     ( dRF_RD2_D     ),
    .coEqualD     ( cEqualD       )
  );
  
  // debug outputs
  assign doadrR       = { 26'h0, dWriteRegW };
  assign dowritedataR = dResultW;
  assign domemwriteR  = cRegWriteW;
  
  // ++++++++++++++++++++++++ Pipeline register 2 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Datapath part
  logic [31:0] dRF_RD1_E, dRF_RD2_E, dSignImmE;

  PipelineReg #(
    .WIDTH (  32 + 32 + 6 + 6 + 6 + 6 + 32 )
  )  PR2D  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushE   ),
    .EN    ( !cStallE  ),

    .dIn   ( { dRF_RD1_D, dRF_RD2_D, dXsD, dXtD, dRdD, dFdD, dSignImmD } ),
    .dOut  ( { dRF_RD1_E, dRF_RD2_E, dXsE, dXtE, dRdE, dFdE, dSignImmE } )
  );

  // Control part
  logic       cMemWriteE, cALUSrcE, cMemEnableE;
  logic [1:0] cRegDstE, cCMPmaskE;
  logic       cFP_ALUCtrlE, cFP_CVTen_E;
  logic [2:0] cALUControlE;

  PipelineReg #(
    .WIDTH (   1 + 1 + 1 + 3 + 1 + 2 + 1 )
  )  PR2C  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushE   ),
    .EN    ( !cStallE  ),

    .dIn   ( { cRegWriteD, cMemtoRegD, cMemWriteD, cALUControlD, cALUSrcD, cRegDstD, cMemEnableD } ),
    .dOut  ( { cRegWriteE, cMemtoRegE, cMemWriteE, cALUControlE, cALUSrcE, cRegDstE, cMemEnableE } )
  );
  
  PipelineReg #(
    .WIDTH ( 1 + 1 + 1 + 2 )
  )  PR2CFP(
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushE   ),
    .EN    ( !cStallE  ),

    .dIn   ( { cFP_ALUen_D, cFP_CVTen_D, cFP_ALUCtrlD, cCMPmaskD } ),
    .dOut  ( { cFP_ALUen_E, cFP_CVTen_E, cFP_ALUCtrlE, cCMPmaskE } )
  );
  
  // ++++++++++++++++++++++++ Pipeline stage    3: Execute +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dALUOutE, dWriteDataE;
  logic [31:0] dSrc_FP_AE, dSrc_FP_BE;

  // Integer EX stage
  MIPS_EX  EX(
    .clk           ( clk            ),
    .rst           ( ci_rst         ),
    .diRF_RD1      ( dRF_RD1_E      ),
    .diRF_RD2      ( dRF_RD2_E      ),
                                                                        
    .diSignImmE    ( dSignImmE      ),
                                    
    .diALUOutM     ( dALUOutM       ),
    .diResultW     ( dResultW       ),
                                    
    .ciForwardAE   ( cForwardAE     ),
    .ciForwardBE   ( cForwardBE     ),
                                    
    .ciALUSrcE     ( cALUSrcE       ),
    .ciALUControlE ( cALUControlE   ),
    
    .ciStallE       ( cStallE       ),
                                    
    .doALUOutE     ( dALUOutE       ),
    .doWriteDataE  ( dWriteDataE    ),
    .doSrc_FP_AE   ( dSrc_FP_AE     ),
    .doSrc_FP_BE   ( dSrc_FP_BE     )
  );

  // FP converter
  logic [31:0] dFP_CVT_Out_E;
  MIPS_EX_FP_CONV FP_CVT( 
    .diSrc_FP_AE    ( dSrc_FP_AE      ),
    .ciFP_CVTway_E  ( cFP_ALUCtrlE    ),
                    
    .doFP_CVT_Out_E ( dFP_CVT_Out_E   ),
    .doNAN          (  ),
    .doINF          (  )
  );

  // FP ALU
  logic [31:0]  dFP_ALU_Out_M;
  MIPS_EX_FP_ALU FPALU(
    .clk            ( clk             ),
    .rst            ( ci_rst          ),  
                                      
    .diSrc_FP_AE    ( dSrc_FP_AE      ),
    .diSrc_FP_BE    ( dSrc_FP_BE      ), 
                    
    .ciFP_ALUen_E   ( cFP_ALUen_E     ), 
    .ciFP_ADD_n_E   ( cFP_ALUCtrlE    ),
    .ciStallM       ( 1'b0/*cStallM*/         ),
                    
    .doFP_ALU_Out_M ( dFP_ALU_Out_M   ), 
    .doFP_CMP_M     ( dFP_CMP_M       ),     // 0=eq, 1=gt, 10=eq, 11=lt
                                         
    .coFPALU_Stall  ( cFPALU_Stall_M  ), 
    .coFPALU_Valid  ( cFPALU_Valid_M  ), 
    .coNAN          (  )
  );
  // mask 11 = lt, 10 = le, 00 = eq
  logic [1:0] cCMPmaskM;
  always_comb casex( { cCMPmaskM, dFP_CMP_M } )
    4'bx0x0:  cCMPresult = 1'b1;// equal
    4'b1x11:  cCMPresult = 1'b1;// lt
    default:  cCMPresult = 1'b0;
  endcase
  
  logic [31:0] dALUOutE_post;
  assign dALUOutE_post = ( cFP_CVTen_E ) ? ( dFP_CVT_Out_E ) : ( dALUOutE ); 
  
  always_comb case(cRegDstE)
    2'b10: dWriteRegE = dXsE;
    2'b00: dWriteRegE = dXtE;
    2'b01: dWriteRegE = dRdE;
    2'b11: dWriteRegE = dFdE;
    default: dWriteRegE = 6'hxx;
  endcase
  
  // ++++++++++++++++++++++++ Pipeline register 3 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Datapath part
  logic [31:0] dWriteDataM;

  PipelineReg #(
    .WIDTH (  32 + 32 + 6 )
  )  PR3D  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( 1'b0      ),
    .EN    ( !cStallM  ),

    .dIn   ( { dALUOutE_post, dWriteDataE, dWriteRegE } ),
    .dOut  ( { dALUOutM,      dWriteDataM, dWriteRegM } )
  );

  // Control part
  logic cMemWriteM;

  PipelineReg #(
    .WIDTH ( 1 + 1 + 1 + 1 + 1 + 2 )
  )  PR3C  (
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( 1'b0      ),
    .EN    ( !cStallM  ),

    .dIn   ( { cRegWriteE, cMemtoRegE, cMemWriteE, cMemEnableE, cFP_ALUen_E, cCMPmaskE } ),
    .dOut  ( { cRegWriteM, cMemtoRegM, cMemWriteM, cMemEnableM, cFP_ALUen_M, cCMPmaskM } )
  );

  // ++++++++++++++++++++++++ Pipeline stage    4: Memory ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [31:0] dReadDataM;

  MIPS_MEM  MEM(
   .clk             (           clk ),
   .ci_rst          (        ci_rst ),
                          
   .diALUOutM       (      dALUOutM ),
   .diWriteDataM    (   dWriteDataM ),
                       
   .ciMemWriteM     (    cMemWriteM ),
   .ciMemEnableM    (   cMemEnableM ),
                        
   .doReadDataM     (    dReadDataM ),
   .coStall_CacheM  ( cStall_CacheM ),
   
   // Uplink memory interface
   .doUpMem_address ( dMemL2_addr_d ),
   .coUpMem_clock   (),
   .doUpMem_data    (    dMemL2_D_d ),
   .coUpMem_wren    (   cMemL2_WE_d ),
   .diUpMem_q       (    dMemL2_Q_d ) 
  );
  
  assign  dResultM =  ( cFPALU_Valid_M  ) ? ( dFP_ALU_Out_M ) :
                      ( cMemtoRegM      ) ? ( dReadDataM    ) : ( dALUOutM );
  
  // debug outputs
  assign doadrM       = dALUOutM;
  assign dowritedataM = dWriteDataM;
  assign domemwriteM  = cMemWriteM;
  // ++++++++++++++++++++++++ Pipeline register 4 ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Datapath part
  //logic [31:0] dReadDataW, dALUOutW;
  
  PipelineReg #( 
    .WIDTH (  32 + 6 ) 
  )  PR4D  (  
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushW   ),
    .EN    ( 1'b1      ),
    
    .dIn   ( { dResultM, dWriteRegM } ),
    .dOut  ( { dResultW, dWriteRegW } ) 
  );     
         
  // Control part
  logic      cMemtoRegW;

  PipelineReg #( 
    .WIDTH ( 1 + 1 ) 
  )  PR4C  (  
    .clk   ( clk       ),
    .rst   ( ci_rst    ),
    .clr   ( cFlushW   ),
    .EN    ( 1'b1      ),
     
    .dIn   ( { cRegWriteM, cMemtoRegM } ),
    .dOut  ( { cRegWriteW, cMemtoRegW } ) 
  );     
  
  // ++++++++++++++++++++++++ Pipeline stage    5: Writeback +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // NULL

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Control unit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_CU  (
  input  logic        clk,              //
  input  logic        rst,              //
  input  logic [ 5:0] diOpcode,
  input  logic [ 5:0] diFunct,
  input  logic [ 4:0] ciRS,
  input  logic        ciFPBranchCond,
  input  logic        ciEqualD,           
  input  logic        ciCMPresult,
  input  logic        ciFPALU_Valid_M, //
  output logic        coMemtoReg,         
  output logic        coMemWrite,         
  output logic        coMemEnableD,       
  output logic        coPCSrcD,           // 1 for branch
  output logic        coALUSrc,           
  output logic [1:0]  coRegDst,           
  output logic        coXsSrc,
  output logic        coXsFP, 
  output logic        coXtFP, 
  output logic        coRegWrite,         
  output logic        coJump,             
  output logic        coBranchD,          
  output logic [2:0]  coALUControl,       
  output logic        coFP_ALUen,   
  output logic        coFP_CVTen,   
  output logic        coFP_ALUCtrl, 
  output logic        coFPBranchD,
  output logic        coRegWrite_Mov,
  output logic [1:0]  coCMPmask           // 11 = lt, 10 = le, 00 = eq
);
 logic [1:0] dALUOp; // from main decoder to ALU decoder
  logic       cFlPt;  // Floating point operation (except memory load/store)

  // Main decoder
  logic [10:0] dDecOut;
  logic        cRegWrite;
  logic        cIntRegDst;
  assign  { cRegWrite, cIntRegDst, coALUSrc, coBranchD, coMemWrite, coMemEnableD, coMemtoReg, dALUOp, coJump, cFlPt } = ( |{ diOpcode, diFunct } ) ? dDecOut : 0; // NOP detection
  always_comb case (diOpcode)
    6'b000000:  dDecOut = 11'b11000001000; // R-type
    6'b100011:  dDecOut = 11'b10100110000; // lw
    6'b101011:  dDecOut = 11'b00101100000; // sw
    6'b000100:  dDecOut = 11'b00010000100; // beq
    6'b001000:  dDecOut = 11'b10100000000; // addi
    6'b000010:  dDecOut = 11'b00000000010; // Jump
    6'b010001:  dDecOut = 11'b00100001101; // FlPt // Override regwrite for some commands
    6'b110001:  dDecOut = 11'b10100110000; // lwc1
    6'b111001:  dDecOut = 11'b00101100000; // swc1
    default:    dDecOut = 11'bxxxxxxxxxxx; // error case
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
    default:     coALUControl  = cFlPt ? 3'b010 : 3'bxxx; // need for mtc1/mfc1
  endcase


  // FP decoder
  logic cFP_Regwrite;
  logic cXsFP, cXtFP;
  logic [1:0]  cFP_RegDst;
  
  logic [12:0] cFP_Config;
  
  assign {  cFP_Regwrite, cFP_RegDst, coXsSrc, cXsFP, cXtFP,  coFP_ALUen, 
            coFP_CVTen, coFP_ALUCtrl, coRegWrite_Mov, coCMPmask, coFPBranchD } = cFP_Config;
  
  // TODO: coXsSrc == coXsFP == cFlPt; 
  // TODO: compare controls
  always_comb casex ( { cFlPt, ciRS, diFunct } )
    12'b1100xx000000: cFP_Config  = 13'b1111111000000; //add.s
    12'b1100xx000001: cFP_Config  = 13'b1111111010000; //sub.s
    12'b1001xx000000: cFP_Config  = 13'b1011100001000; //mtc1
    12'b1000xx000000: cFP_Config  = 13'b1001100001000; //mfc1   
    12'b1100xx100000: cFP_Config  = 13'b1111100100000; //cvt.s.w       
    12'b1100xx100100: cFP_Config  = 13'b1111100110000; //cvt.w.s
    12'b1100xx111100: cFP_Config  = 13'b0001111010110; //c.lt.s 
    12'b1100xx111110: cFP_Config  = 13'b0001111010100; //c.le.s
    12'b1100xx110010: cFP_Config  = 13'b0001111010000; //c.eq.s
    12'b1010xxxxxxxx: cFP_Config  = 13'b0001110000001; //bc1*
    default:          cFP_Config  = 13'b0000000000000; //  error case or not FlPt
  endcase
  
  assign coXsFP     = cXsFP;
  assign coXtFP     = ( cFlPt ) ? ( cXtFP        ) : ( diOpcode == 6'b110001 || diOpcode == 6'b111001  ); // lwc1/swc1
  assign coRegDst   = ( cFlPt ) ? ( cFP_RegDst   ) : ( { 1'b0, cIntRegDst } );
  assign coRegWrite = ( cFlPt ) ? ( cFP_Regwrite ) : cRegWrite;
  
  // compare result keeper
  logic cCMP_keep;
  always_ff@(posedge clk or posedge rst) begin
    if(rst)                  cCMP_keep <= 1'b0;
    else if(ciFPALU_Valid_M) cCMP_keep <= ciCMPresult;
  end
  
  assign coPCSrcD = ( coBranchD && ciEqualD ) || ( coFPBranchD && !( ciFPBranchCond ^ cCMP_keep ) );
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Hazard unit
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TODO: override stall for instruction next to bubble after stall if possible
// TODO: don't stall sequential FPALU instructions
module MIPS_HU  (
  input  logic        ciBranchD,
  input  logic        ciFPBranchD,

  input  logic        ciMemtoRegE,
  input  logic        ciMemtoRegM,
  
  input  logic        ciFP_ALUen_E,
  input  logic        ciFP_ALUen_M,
  
  input  logic        ciRegWriteE,
  input  logic        ciRegWriteM,
  input  logic        ciRegWriteW,
  input  logic        ciStall_CacheM,
  input  logic        ciFPALU_Stall_M,
  input  logic        ciMemEnableM,

  input  logic [ 5:0] diXsD,
  input  logic [ 5:0] diXtD,
  input  logic [ 5:0] diXsE,
  input  logic [ 5:0] diXtE,

  input  logic [ 5:0] diWriteRegE,
  input  logic [ 5:0] diWriteRegM,
  input  logic [ 5:0] diWriteRegW,

  output logic        coStallF,
  output logic        coStallD,
  output logic        coStallE,
  output logic        coStallM,

  output logic        coForwardAD,
  output logic        coForwardBD,
  output logic [ 1:0] coForwardAE,
  output logic [ 1:0] coForwardBE,

  output logic        coFlushE,
  output logic        coFlushW
);
  //logic not used now
  logic cNULL0, cNULL1, cNULL2, cNULL3;
  
  // Bypass from Memory and Writeback to Execute
  always_comb begin
    if ( ( diXsE != 0 ) && ( diXsE == diWriteRegM ) && ( ciRegWriteM ) ) begin 
      coForwardAE = 2'b10;
    end else 
    if ( ( diXsE != 0 ) && ( diXsE == diWriteRegW ) && ( ciRegWriteW ) ) begin
      coForwardAE = 2'b01;
    end else begin
      coForwardAE = 2'b00;
    end
  end
  
  always_comb begin
    if ( ( diXtE != 0 ) && ( diXtE == diWriteRegM ) && ( ciRegWriteM ) ) begin 
      coForwardBE = 2'b10;
    end else 
    if ( ( diXtE != 0 ) && ( diXtE == diWriteRegW ) && ( ciRegWriteW ) ) begin
      coForwardBE = 2'b01;
    end else begin
      coForwardBE = 2'b00;
    end
  end
  
  // Bypass and stall for branch
  logic  cBranchStall;
  assign coForwardAD  = ( diXsD != 0 ) && ( diXsD == diWriteRegM ) && ( ciRegWriteM );
  assign coForwardBD  = ( diXtD != 0 ) && ( diXtD == diWriteRegM ) && ( ciRegWriteM );
  assign cBranchStall = ( ciBranchD   && ciRegWriteE && ( ( diWriteRegE == diXsD ) || ( diWriteRegE == diXtD ) ) ) ||
                        ( ciBranchD   && ciMemtoRegM && ( ( diWriteRegM == diXsD ) || ( diWriteRegM == diXtD ) ) ) ||
                        ( ciFPBranchD &&                (   ciFP_ALUen_E           ||   ciFP_ALUen_M           ) );
  
  // LWStall
  logic  clwstall;
  assign clwstall = ( ( ( diXsD == diWriteRegE) || ( diXtD == diWriteRegE) ) && ( ciMemtoRegE || ciFP_ALUen_E ) );
  
  
  // Combine stalls
  logic [1:0] cStallCause;
  assign cStallCause[0] = ( clwstall || cBranchStall );
  assign cStallCause[1] = ciStall_CacheM || ciFPALU_Stall_M;
  
  // Pipeline registers management
  logic [ 4:0 ] cStalls, cFlushes;
  assign { coStallF, coStallD, coStallE, coStallM, cNULL0   } = cStalls;
  assign { cNULL1,   cNULL2,   coFlushE, cNULL3,   coFlushW } = cFlushes;
  always_comb case (cStallCause)
    2'b00:  begin // No stall
              cStalls  = 5'b00000;
              cFlushes = 5'b00000;
            end
    2'b01:  begin // Branch, or LW stall
              cStalls  = 5'b11000;
              cFlushes = 5'b00100;
            end
    2'b10,
    2'b11:  begin // Cache miss stall
              cStalls  = 5'b11110;
              cFlushes = 5'b00001;
            end
    default: begin // error
              cStalls  = 5'bxxxxx;
              cFlushes = 5'bxxxxx;
            end
  endcase
  
  
endmodule


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 1: Fetch
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_IF  (
  input  logic                clk,
  input  logic             ci_rst,
                         
  input  logic                   ciInstInp,    // for debug purposes
  input  logic [  31 : 0 ]     diInstToMem,  // for debug purposes
  input  logic [  31 : 0 ]      diInstAddr,   // for debug purposes
                         
  input  logic [  25 : 0 ]       diJumpDst,
  input  logic [  31 : 0 ]     diPCBranchD,
  input  logic                      ciJump,
  input  logic                    ciPCSrcD,
  input  logic                    ciStallF,
  input  logic                     ciFLUSH,  // Cancelling cache memory miss operation
                         
  output logic [  31 : 0 ]         doInstr,
  output logic [  31 : 0 ]      doPCPlus4F,
  
  // L2 memory interface
  input  logic [ 127 : 0 ]       diUpMem_q,
  output logic [  31 : 0 ] doUpMem_address,
  output logic               coUpMem_clock,  
  output logic [ 127 : 0 ]    doUpMem_data,   
  output logic                coUpMem_wren    
);
  // Instruction memory
  logic [31:0]  dPCF;  // Program Counter and Instr for Instruction Memory; 
  logic [31:0]  dIMAddr;
  
  // Cache logic
  logic [31:0]  dCache_RD;  
  logic         cStall_CacheF;
  
   // PC register and Jump logic
  logic [31:0]  dPCset, dPCJump, cPCP4F_pre;

  assign  dPCJump     = { doPCPlus4F[31:28], diJumpDst, 2'b00 };
  //assign  doPCPlus4F  = dPCF + 4'h4; // Replaced with custom Incrementor
  inc_prefix  #(5)  IP0( .A( { 2'b00, dPCF[31:2] } ), .S(cPCP4F_pre), .Cout() );
  assign  doPCPlus4F  = { cPCP4F_pre[29:0], dPCF[1:0] };
  assign  dPCset      = ( ciJump ) ? ( dPCJump   ) :
                                     ( ciPCSrcD  ) ? ( diPCBranchD ) : ( doPCPlus4F );
    
  always_ff@( posedge clk or posedge ci_rst)
  begin
    if(ci_rst) begin
      dPCF   <= 0;
    end
    else begin 
	   if( !( ciStallF || ( cStall_CacheF && !ciFLUSH ) ) ) begin
        dPCF   <= dPCset;
      end
      else begin
        dPCF   <= dPCF; 
      end
    end
  end

  // Instruction memory and program counter register  
     assign dIMAddr = ( ciInstInp ) ? ( diInstAddr ) : ( dPCF );
  
  Cache#(
  .LOGWIDTH    ( 5 ), // Port width
  .LOG_NWAYS   ( 1 ), // N-Way set associativity, for now restricted to 2-Way only!
  .LOG_NSETS   ( 2 ), // Number of sets
  .LOG_NWORDS  ( 2 ), // Number of words in set
  .MEM_LATENCY ( 2 )  // M10K latency in cycles
  ) CacheInst ( 
    .clk          (           clk ),
    .rst          (        ci_rst ),
                          
    .diAddr       (       dIMAddr ),
    .diWriteData  (         32'b0 ),
                          
    .ciWE         (          1'b0 ),
    .ciENA        (          1'b1 ),  
    .ciCANCEL     (       ciFLUSH ),
                          
    .doReadData   (     dCache_RD ),  
    .coStall      ( cStall_CacheF ),
    
    // Uplink memory interface
    .doUpMem_address         ( doUpMem_address[27:0] ),
    .coUpMem_clock           (   coUpMem_clock ),
    .doUpMem_data            (    doUpMem_data ),
    .coUpMem_wren            (    coUpMem_wren ),
    .diUpMem_q               (       diUpMem_q ) 
  );  
  assign doUpMem_address[31:28] = 4'b0000;

  // Output logic 
  assign doInstr = ( cStall_CacheF ) ? 32'b0 : dCache_RD;  // NOP for stall
  
  
  
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 2: Decode
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_ID  (
  input  logic        clk,
  input  logic        ci_rst,
  input  logic [31:0] diInstrD,
  input  logic [31:0] diPCPlus4D,
  input  logic [ 5:0] diWriteRegW,
  input  logic [31:0] diResultW,
  input  logic [31:0] diALUOutM,
  input  logic        ciForwardAD,
  input  logic        ciForwardBD,
  input  logic        ciRegWriteW,
  input  logic        ciRegWrite_MovD,
  input  logic        ciXsSrc,          
  input  logic        ciXsFP,           
  input  logic        ciXtFP,    
  output logic [25:0] doJumpDst,
  output logic [ 5:0] doXsD,            
  output logic [ 5:0] doXtD,            
  output logic [ 5:0] doRdD,            
  output logic [ 5:0] doFdD,            
  output logic [31:0] doPCBranchD,
  output logic [31:0] doSignImmD,
  output logic [31:0] doRF_RD1,
  output logic [31:0] doRF_RD2,
  output logic        coEqualD
);
  // control constants
  integer  i;
  localparam REG_SIZE_LOG = 6;//let REG_SIZE_LOG = 5; // SystemVerilog-2012, not supported in quartus; can use localparam instead

  // mtc1/mfc1 select logic 
  logic  cMovMode;
  assign cMovMode = diInstrD[23];
  
  // Register File
  logic [31:0]  dREGFILE[ 2**REG_SIZE_LOG - 1 :0];


  always_comb case( { ciXsSrc, ( ciRegWrite_MovD && cMovMode ) } ) 
    2'b00:  doXsD = { ciXsFP, diInstrD[25:21] };
    2'b10:  doXsD = { ciXsFP, diInstrD[15:11] };
    2'b01:  doXsD = {   1'b0, diInstrD[20:16] };
    2'b11:  doXsD = {   1'b0, diInstrD[20:16] };
  endcase
  
  assign  doXtD      = ( { ciXtFP, diInstrD[20:16] } );
  assign  doRdD      = ( { ( ciRegWrite_MovD && cMovMode ),   diInstrD[15:11] } );
  assign  doFdD      = ( { 1'b1,   diInstrD[10:6 ] } );

  assign  doRF_RD1   = dREGFILE[doXsD];
  assign  doRF_RD2   = dREGFILE[doXtD];
  
        
  always_ff@( posedge clk or posedge ci_rst )
  begin
    if( ci_rst )
      for( i = 0; i < 2**REG_SIZE_LOG; i = i + 1 )
          dREGFILE[i] <= 0;
    else begin
      if ( ciRegWriteW      && diWriteRegW  !=0 ) dREGFILE[diWriteRegW] <= diResultW;
    end  
   end

   // EqualD logic
   logic [31:0]  dEq_RD1, dEq_RD2;

   assign  dEq_RD1  = ( ciForwardAD ) ? diALUOutM : doRF_RD1;
   assign  dEq_RD2  = ( ciForwardBD ) ? diALUOutM : doRF_RD2;
   assign  coEqualD = ( dEq_RD1 == dEq_RD2 );

  // Immediate, Jump and Branch logic
  assign  doSignImmD  = ( ciRegWrite_MovD ) ? ( 32'h00000000 ) : ( { {16{diInstrD[15]}}, diInstrD[15:0]} ); //sign extend
  //assign  doPCBranchD = diPCPlus4D + {doSignImmD[29:0],2'b00}; // Replaced with custom logic
  sum_prefix  #(5)  SP0 ( .Cin(1'b0), .A(diPCPlus4D), .B({doSignImmD[29:0],2'b00}), .S(doPCBranchD), .Cout() );  
  assign  doJumpDst   = diInstrD[25:0];

endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 3: Execute
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_EX  (
  input  logic          clk,
  input  logic          rst,
  input  logic  [31:0]  diRF_RD1,
  input  logic  [31:0]  diRF_RD2,
  
  input  logic  [31:0]  diSignImmE,

  input  logic  [31:0]  diALUOutM,
  input  logic  [31:0]  diResultW,

  input  logic  [ 1:0]  ciForwardAE,
  input  logic  [ 1:0]  ciForwardBE,

  input  logic          ciALUSrcE,
  input  logic  [ 2:0]  ciALUControlE,
  
  input  logic          ciStallE,

  output logic  [31:0]  doALUOutE,
  output logic  [31:0]  doWriteDataE,
  // For FP 
  output logic  [31:0]  doSrc_FP_AE,
  output logic  [31:0]  doSrc_FP_BE
);
  // ALU source logic
  logic [31:0]  dSrcAE, dSrcBE, dSrcAE_imm, dWDE_imm;

  always_comb case (ciForwardAE)
    2'b00:   dSrcAE_imm       = diRF_RD1;
    2'b01:   dSrcAE_imm       = diResultW;
    2'b10:   dSrcAE_imm       = diALUOutM;
    default: dSrcAE_imm       = 31'hxxxxxxxx;
  endcase

  always_comb case (ciForwardBE)
    2'b00:   dWDE_imm = diRF_RD2;
    2'b01:   dWDE_imm = diResultW;
    2'b10:   dWDE_imm = diALUOutM;
    default: dWDE_imm = 31'hxxxxxxxx;
  endcase

  //assign dSrcAE = dSrcAE_imm;
  //assign doWriteDataE = dWDE_imm;
  SEL_GRD #32 grdEA ( .clk(clk), .rst(rst), .ciStall( ciStallE ), .ciBypass( |(ciForwardAE) ), .diInput( dSrcAE_imm ), .doOutput( dSrcAE       ) );
  SEL_GRD #32 grdEB ( .clk(clk), .rst(rst), .ciStall( ciStallE ), .ciBypass( |(ciForwardBE) ), .diInput( dWDE_imm   ), .doOutput( doWriteDataE ) );
  
  assign dSrcBE   = ( ciALUSrcE ) ? ( diSignImmE ) : ( doWriteDataE );

  // ALU
  ALU   ALU ( .A(dSrcAE), .B(dSrcBE),.F(ciALUControlE),.Y(doALUOutE), .Cout(), .Oflow(), .Zero() );
  
  // FP outputs
  assign doSrc_FP_AE = dSrcAE;
  assign doSrc_FP_BE = doWriteDataE;
  
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 3a: FP converter
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_EX_FP_CONV(
  input  logic  [31:0]  diSrc_FP_AE,
  input  logic          ciFP_CVTway_E,
  
  output logic  [31:0]  doFP_CVT_Out_E,
  output logic          doNAN,
  output logic          doINF
);
  CVT_FP #(5, 8, 23) FPCVT (
  .diA      (    diSrc_FP_AE ),

  .ciWay    (  ciFP_CVTway_E ), // 0 for word-to-float
  .ciENA    (           1'b1 ), // Not used now

  .doY      ( doFP_CVT_Out_E ),
  .doNAN    (          doNAN ),
  .doINF    (          doINF )
);
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 3b: FP ALU
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module MIPS_EX_FP_ALU(
  input  logic          clk,
  input  logic          rst,  

  input  logic  [31:0]  diSrc_FP_AE,
  input  logic  [31:0]  diSrc_FP_BE, 
  
  input  logic          ciFP_ALUen_E,
  input  logic          ciFP_ADD_n_E,
  input  logic          ciStallM,
  
  output logic  [31:0]  doFP_ALU_Out_M,
  output logic  [ 1:0]  doFP_CMP_M,     // 0=eq, 1=gt, 10=eq, 11=lt
  
  output logic          coFPALU_Stall,
  output logic          coFPALU_Valid,  
  output logic          coNAN
);
  logic cZero;
    
  FPAdder_Pipelined #(5, 8, 23) FPADD (
  .clk        ( clk             ),
  .ci_rst     ( rst             ), 
                    
  .diA        ( diSrc_FP_AE     ), 
  .diB        ( diSrc_FP_BE     ),
                  
  .ciADD_n    ( ciFP_ADD_n_E    ),
  .ciStallA   ( ciStallM        ),
  
  .doY        ( doFP_ALU_Out_M  ),
  .coNAN      ( coNAN           ),
  .coZero     ( cZero           )
  );
  // Compare
  assign doFP_CMP_M[0] = !cZero;
  assign doFP_CMP_M[1] = doFP_ALU_Out_M[31];
  
  // Enable propagation
  logic[1:0] cENA_Carry;
  
  always_ff@(posedge clk or posedge rst)
  begin
    if(rst) cENA_Carry <= 2'b00;
    else begin
      if ( !ciStallM) cENA_Carry[0] <= ( cENA_Carry[0] ) ? ( 1'b0 ) : ( ciFP_ALUen_E );
      cENA_Carry[1] <= cENA_Carry[0];
    end
  end
  
  assign coFPALU_Stall = cENA_Carry[0];
  assign coFPALU_Valid = cENA_Carry[1];

endmodule



////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 4: Memory
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TODO: Out-of-order operation when cache is busy ( on miss ). Do on stage 4 due to additional complexity
module MIPS_MEM (
  input  logic                         clk,
  input  logic                      ci_rst,
                            
  input  logic  [31:0]           diALUOutM,
  input  logic  [31:0]        diWriteDataM,
                            
  input  logic                 ciMemWriteM,
  input  logic                ciMemEnableM,
                            
  output logic  [31:0]         doReadDataM,
                            
  output logic              coStall_CacheM,
  
  // L2 memory interface
  input  logic [ 127 : 0 ]       diUpMem_q,
  output logic [  31 : 0 ] doUpMem_address,
  output logic               coUpMem_clock,  
  output logic [ 127 : 0 ]    doUpMem_data,   
  output logic                coUpMem_wren    
);
  // Data memory
  Cache#(
    .LOGWIDTH    ( 5 ), // Port width
    .LOG_NWAYS   ( 1 ), // N-Way set associativity, for now restricted to 2-Way only!
    .LOG_NSETS   ( 2 ), // Number of sets
    .LOG_NWORDS  ( 2 ), // Number of words in set
    .MEM_LATENCY ( 2 )  // M10K latency in cycles
  ) CacheDat ( 
    .clk          (            clk ),
    .rst          (         ci_rst ),
                           
    .diAddr       (      diALUOutM ),
    .diWriteData  (   diWriteDataM ),
                           
    .ciWE         (    ciMemWriteM ),
    .ciENA        (   ciMemEnableM ),  
    .ciCANCEL     (1'b0),
                           
    .doReadData   (    doReadDataM ),  
    .coStall      ( coStall_CacheM ),
    
    // Uplink memory interface
    .doUpMem_address         ( doUpMem_address[27:0] ),
    .coUpMem_clock           (   coUpMem_clock ),
    .doUpMem_data            (    doUpMem_data ),
    .coUpMem_wren            (    coUpMem_wren ),
    .diUpMem_q               (       diUpMem_q ) 
  );  
  assign doUpMem_address[31:28] = 4'b0000;


endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pipeline stage 5: Write back
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// In main module

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Selector guard
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module SEL_GRD #( parameter Width = 32 )
(
  input  logic                    clk,
  input  logic                    rst,
  input  logic                    ciStall,
  input  logic                    ciBypass,
  input  logic  [ Width  -1:0 ]   diInput,
  output logic  [ Width  -1:0 ]   doOutput
);

  logic cPrevStall;
  always_ff@( posedge clk or posedge rst ) begin
    if(rst) cPrevStall <= 1'b0;
    else    cPrevStall <= ciStall;
  end

  logic  cSwitch;
  assign cSwitch = cPrevStall && !ciBypass;
  
  logic [ Width  -1:0 ] dDataReg;
  always_ff@( posedge clk or posedge rst ) begin
    if(rst)                 dDataReg <= 1'b0;
    else if(!cSwitch)    dDataReg <= diInput;
  end
  
  assign  doOutput = ( cSwitch ) ? ( dDataReg ) : ( diInput );

endmodule