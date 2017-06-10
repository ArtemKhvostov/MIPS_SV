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

module CPU ( 
  input   logic         clk, ci_rst,
  output  logic [31:0]  writedata, adr,
  output  logic         memwrite
);
      
  logic [31:0] readdata;
  logic        cInstInp; // for debug purposes
  assign       cInstInp = 1'b0;
  assign       readdata = 32'b0;
  // instantiate processor and memories
  MIPS MIPS(
    .clk        (clk), 
    .ci_rst     (ci_rst), 
    
    .ciInstInp  (cInstInp), 
    
    .readdata   (readdata), 
    
    .adr        (adr),
    .writedata  (writedata),
    
    .memwrite   (memwrite)
  );
//  Mem_Cache #2  mem (clk, memwrite, adr, writedata, readdata);

endmodule

module MIPS
(
  input logic          clk, ci_rst,
  
  input logic          ciInstInp,
  
  input logic   [31:0] readdata, 
  
  output  logic [31:0] adr,
  output  logic [31:0] writedata, 
  
  output  logic        memwrite
  
);    
  // control constants 
  integer  i;
  localparam REG_SIZE_LOG = 5;//let REG_SIZE_LOG = 5; // SystemVerilog-2012, not supported in quartus; can use localparam instead
  
  // Data buses between blocks
  logic [31:0]  dPCBranch, dResult;   
  
  // control signals
  logic [5:0] cOpcode, cFunct;
  logic       cMemtoReg, cMemWrite, cBranch, cJump;
  logic       cALUSrc, cRegDst, cRegWrite;
  logic [2:0] cALUControl;
  logic       cALUZero, cPCSrc;
  
  // for test purposes, simple meaningless I/O
  assign  adr       = dPCBranch;
  assign  writedata = dResult;
  assign  memwrite  = cMemWrite;
    
  // Instruction memory
  logic [31:0]  dPC, dInstr, dInstr_cache;  // Program Counter и Instr для Instruction Memory
  
  Mem_Cache #0  MemInst (clk,1'b0,dPC,32'b0,dInstr_cache); // модуль выдает данные на чтение сразу же, не зависимо от clk
  
  assign  dInstr  = ( ciInstInp ) ? readdata  : dInstr_cache; // for test purposes, simple meaningless I/O; if ciInstInp then read instruction from higher-level module
  
  // Control logic
  assign    cOpcode = dInstr[ 31: 26];
  assign    cFunct  = dInstr[  5:  0];
  MIPS_cu   CU(
    .diOpcode     (cOpcode), 
    .diFunct      (cFunct),
    .doMemtoReg   (cMemtoReg), 
    .doMemWrite   (cMemWrite), 
    .doBranch     (cBranch),
    .doALUSrc     (cALUSrc), 
    .doRegDst     (cRegDst), 
    .doRegWrite   (cRegWrite), 
    .doJump       (cJump),
    .doALUControl (cALUControl)
  );
  assign    cPCSrc    = cBranch & cALUZero;
  
  // PC register logic
  logic [31:0]  dPCset, dPCPlus4, dPCJump;
  
  assign  dPCPlus4    = dPC + 4'h4;
  assign  dPCset      = ( cJump ) ? ( dPCJump ) : 
                                    ( cPCSrc  ) ? ( dPCBranch ) : ( dPCPlus4 );
  
  always_ff@( posedge clk or posedge ci_rst) 
  begin
    dPC <= ( ci_rst ) ? ( 0 ) : ( dPCset );
  end
  
  // Register File
  logic [31:0]  dRF_RD1, dRF_RD2, dWriteData;
  logic [4 :0]  dWriteReg, dRF_A1, dRF_A2;
  logic [31:0]  dREGFILE[ 2**REG_SIZE_LOG - 1 :0];
  
  assign  dWriteData  = dRF_RD2;
  assign  dRF_A1      = dInstr[25:21];
  assign  dRF_A2      = dInstr[20:16];
  assign  dWriteReg   = cRegDst ? dInstr[15:11] : dInstr[20:16];  
  assign  dRF_RD1     = dREGFILE[dRF_A1];
  assign  dRF_RD2     = dREGFILE[dRF_A2];
  
  always_ff@( posedge clk or posedge ci_rst ) 
    if( ci_rst )
      for( i = 0; i < 2**REG_SIZE_LOG; i = i + 1 )
          dREGFILE[i] <= 0;
    else
      if (cRegWrite) dREGFILE[dWriteReg] <= dResult;
    
  
  // Immediate, Jump and Branch logic
  logic [31:0]  dSrcA, dSrcB;
  logic [31:0]  dSignImm;
  
  assign  dSrcA   = dRF_RD1;
  assign  dSrcB   = cALUSrc ? dSignImm : dRF_RD2;
  
  assign  dSignImm  = { {16{dInstr[15]}}, dInstr[15:0]}; //sign extend
  assign  dPCBranch = dPCPlus4 + {dSignImm[29:0],2'b00};
  assign  dPCJump   = { dPCPlus4[31:28], dInstr[25:0], 2'b00 };
  
  // ALU
  logic [31:0]  dALUResult;
  
  ALU   ALU ( .A(dSrcA), .B(dSrcB),.F(cALUControl),.Y(dALUResult), .Cout(), .Oflow(), .Zero(cALUZero) );
  
  // Data memory
  logic [31:0]  dReadData;
  
  Mem_Cache   #1  MemDat  ( .clk(clk), .we(cMemWrite), .a(dALUResult), .wd(dWriteData), .rd(dReadData));
  
  assign  dResult = cMemtoReg ? dReadData : dALUResult;
  
  
endmodule

module MIPS_cu  (
  input logic [5:0] diOpcode, diFunct,
  output  logic doMemtoReg, doMemWrite, doBranch,
  output  logic doALUSrc, doRegDst, doRegWrite, doJump,
  output  logic [2:0] doALUControl
);

  logic [1:0] dALUOp; // from main decoder to ALU decoder
  
  // Main decoder
  logic [8:0] dDecOut;
  assign  { doRegWrite, doRegDst, doALUSrc, doBranch, doMemWrite, doMemtoReg, dALUOp, doJump} = dDecOut;
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
    8'b00xxxxxx: doALUControl  = 3'b010; //  add
    8'b01xxxxxx: doALUControl  = 3'b110; //  sub
    8'b10100000: doALUControl  = 3'b010; //  add
    8'b10100010: doALUControl  = 3'b110; //  sub
    8'b10100100: doALUControl  = 3'b000; //  AND
    8'b10100101: doALUControl  = 3'b001; //  OR
    8'b10101010: doALUControl  = 3'b111; //  SLT
    default:     doALUControl  = 3'bxxx; //  error case
  endcase 
  
endmodule