`timescale 1ns/1ps // unit/precision
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Cache top module
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// TODO: Add full memory write-back command for validating of upper-level memory instance
module  Cache#(
  parameter LOGWIDTH    = 5, // Port width
  parameter LOG_NWAYS   = 1, // N-Way set associativity, for now restricted to 2-Way only!
  parameter LOG_NSETS   = 2, // Number of sets
  parameter LOG_NWORDS  = 2, // Number of words in set
  parameter MEM_LATENCY = 2,  // M10K latency in cycles
  parameter BYTEOFFSET  = 2,
  parameter TAGSIZE     = 2**LOGWIDTH - LOG_NSETS - LOG_NWORDS - BYTEOFFSET
  )( 
  // Global control
  input  logic                                 clk,
  input  logic                                 rst,
  
  // Downlink memory interface
  input  logic  [ 2**LOGWIDTH-1 : 0 ]       diAddr,
  input  logic  [ 2**LOGWIDTH-1 : 0 ]  diWriteData,
  
  input  logic                                ciWE,
  input  logic                               ciENA, // Enable signal for not-invoking meaningless cache misses
  input  logic                            ciCANCEL, // Cancel miss operation and return to state S0 ( not cancel initiated UpMem operation )
  
  output logic  [ 2**LOGWIDTH-1 : 0 ]   doReadData,
  
  output logic                             coStall,
  
  // Uplink memory interface
  output logic  [         TAGSIZE + LOG_NSETS  -1:0 ]  doUpMem_address,
  output logic                                         coUpMem_clock,
  output logic  [ 2**LOGWIDTH * 2**LOG_NWORDS  -1:0 ]  doUpMem_data,
  output logic                                         coUpMem_wren,
  input  logic  [ 2**LOGWIDTH * 2**LOG_NWORDS  -1:0 ]  diUpMem_q              
  );  
  integer i;
  genvar  gi;
  localparam NBLOCKS    = 2**LOG_NSETS * 2**LOG_NWAYS; 
    
  // checking for parameters legality
  generate
    if ( LOG_NWAYS != 1 ) begin
      //$error("Error in module FPAdder: wrong parameters!"); // Quartus doesn't support this (SystemVerilog IEEE1800-2009)
      Cache__Error_in_module__Not_upported_organisation non_existing_module();
    end
  endgenerate

  // ++++++++++++++++++ Cache memory block +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Block address in cache memory = ( 2**LOG_NSETS * Set + Way )
  // Least Recent Used
  logic [ LOG_NWAYS                    -1:0 ] cLRU_m   [ 2**LOG_NSETS  -1:0 ];

  // Cache memory blocks: Data and control fields
  logic [ 1                            -1:0 ] cDirty_m [ NBLOCKS       -1:0 ];
  logic [ 1                            -1:0 ] cValid_m [ NBLOCKS       -1:0 ];
  logic [ TAGSIZE                      -1:0 ] dTag_m   [ NBLOCKS       -1:0 ];
  logic [ 2**LOG_NWORDS * 2**LOGWIDTH  -1:0 ] dBlock_m [ NBLOCKS       -1:0 ]; // TODO: maybe specify structure for LRU, Tag and Block
  
  // Write enable for cache
  logic                     cCacheWE;

  // Address to write to cache
  logic [ LOG_NSETS  -1:0 ] dCache_WSet;
  logic [ LOG_NWAYS  -1:0 ] dCache_WWay;
  
  // Data to write to cache
  logic                                       cCache_WDirty;
  //logic                                       cCache_WbyWord;   // Write-By-Word mode; disabled at least for now
  //logic [ LOG_NWAYS                    -1:0 ] dCache_WWordAddr; // Word address in block
  logic [ TAGSIZE                      -1:0 ] dCache_WTag;
  //logic [ 2**LOGWIDTH                  -1:0 ] dCache_Wword;
  logic [ 2**LOG_NWORDS * 2**LOGWIDTH  -1:0 ] dCache_WBlock;
  
  // Cache Flip-flops
  always_ff@( posedge clk or posedge rst )
  begin
    if( rst ) begin //Reset logic
      for ( int i=0; i< NBLOCKS; i=i+1 ) begin 
        dBlock_m [i] <= 0;
        dTag_m   [i] <= 0;
        cValid_m [i] <= 0;
        cDirty_m [i] <= 0;      
      end
    end else begin // Cache writing logic
      if ( cCacheWE ) begin
        cDirty_m [ 2**LOG_NWAYS * dCache_WSet + dCache_WWay ] <= cCache_WDirty;
        cValid_m [ 2**LOG_NWAYS * dCache_WSet + dCache_WWay ] <= 1'b1;
        dTag_m   [ 2**LOG_NWAYS * dCache_WSet + dCache_WWay ] <= dCache_WTag;
        dBlock_m [ 2**LOG_NWAYS * dCache_WSet + dCache_WWay ] <= dCache_WBlock;
      end
    end
  end
  
  // LRU Flip-flop
  logic [ LOG_NSETS  -1:0 ] cLRU_WSet;
  logic [ LOG_NWAYS  -1:0 ] cLRU_WData;
  logic                     cLRU_WE;
  
  always_ff@( posedge clk or posedge rst )
  begin
    if( rst ) for ( i=0; i< 2**LOG_NSETS; i=i+1 ) cLRU_m[i] <= 0;
    else  if( cLRU_WE ) cLRU_m[ cLRU_WSet ] <= cLRU_WData;
  end
  
  // Address hold buffer
  logic [ 2**LOGWIDTH  -1:0 ] dAddr_buf;  
  logic                       cInput_Store;
  
  always_ff@( posedge clk or posedge rst ) begin
    if( rst )               dAddr_buf <= 0;
    else if( cInput_Store ) dAddr_buf <= diAddr;
  end
  
  // Address hold buffer bypassing
  logic [ 2**LOGWIDTH  -1:0 ]  dAddr_cur;
  logic                        cInput_bypass;

  assign dAddr_cur = ( cInput_bypass ) ? ( diAddr ) : ( dAddr_buf );
  
  assign dCache_WTag = dAddr_cur[ 2**LOGWIDTH  -1 : 2**LOGWIDTH - TAGSIZE ];
  
  // Data hold buffer
  logic  [ 2**LOGWIDTH  -1:0 ] dData, dData_buf;
  always_ff@( posedge clk or posedge rst ) begin
    if( rst )               dData_buf <= 0;
    else if( cInput_Store ) dData_buf <= diWriteData;
  end
  
  assign dData    = ( cInput_bypass ) ? ( diWriteData ) : ( dData_buf );
  
  // Output block select logic
  logic [        LOG_NSETS + LOG_NWAYS  -1:0 ] cData_BlselR;
  logic [  2**LOG_NWORDS * 2**LOGWIDTH  -1:0 ] dCache_RdBlock;
  assign dCache_RdBlock = dBlock_m[cData_BlselR];
  
  // Write data block combination
  logic  [ 2**LOG_NWORDS * 2**LOGWIDTH  -1:0 ] dData_InPack;
  logic  [ 2**LOG_NWORDS * 2**LOGWIDTH  -1:0 ] dMemory_RD;
  logic  [                  LOG_NWORDS  -1:0 ] cData_WselW;
  logic                                        cData_Src;
  
  
  generate
    for( gi = 0; gi < 2**LOG_NWORDS; gi = gi + 1 ) begin: Input_block_combination
      assign dData_InPack[ 2**LOGWIDTH * (gi+1)  -1: 2**LOGWIDTH * gi ] = ( cData_WselW == gi ) ? dData : dCache_RdBlock[ 2**LOGWIDTH * (gi+1)  -1: 2**LOGWIDTH * gi ];
    end
  endgenerate
  
  assign  dCache_WBlock = ( cData_Src ) ? ( dMemory_RD ) : ( dData_InPack );
  
  // ++++++++++++++++++ M10K L2 memory instance ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic                                         cMemory_WE;
  
  //assign  doUpMem_address        =    ; // getting from CU
  assign  coUpMem_clock          =            clk;
  assign  doUpMem_data           = dCache_RdBlock;
  assign  coUpMem_wren           =     cMemory_WE;
  assign  dMemory_RD             =      diUpMem_q;
    
  // ++++++++++++++++++ Output word select +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic  [  LOG_NWORDS  -1:0 ] cData_WselR;
  logic  [ 2**LOGWIDTH  -1:0 ] dCache_RdWords [ 2**LOG_NWORDS  -1:0 ];
  generate
    for( gi = 0; gi < 2**LOG_NWORDS; gi = gi + 1 ) begin: Output_block_decomposition
      assign dCache_RdWords[ gi ] = dCache_RdBlock[ 2**LOGWIDTH * (gi+1)  -1: 2**LOGWIDTH * gi ];
    end
  endgenerate
  assign doReadData = dCache_RdWords[cData_WselR];
  
  // ++++++++++++++++++ Control unit +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Cache_CU#(
    .LOGWIDTH    (    LOGWIDTH ), // Port width
    .LOG_NWAYS   (   LOG_NWAYS ), // N-Way set associativity, for now restricted to 2-Way only!
    .LOG_NSETS   (   LOG_NSETS ), // Number of sets
    .LOG_NWORDS  (  LOG_NWORDS ), // Number of words in set
    .TAGSIZE     (     TAGSIZE ), // Tag size, == Width-log_Nsets-log_nwords-byte_offset
    .MEM_LATENCY ( MEM_LATENCY )  // M10K latency in cycles
  ) CCU ( 
    // Control signals
    .clk             (             clk ),
    .rst             (             rst ),
    .ciWE            (            ciWE ),
    .ciENA           (           ciENA ),
    .ciCANCEL        (        ciCANCEL ),
                           
    // Input data           
    .diAddr          (          diAddr ),
    .diAddr_cur      (       dAddr_cur ),
    .ciDirty_m       (        cDirty_m ),
    .ciValid_m       (        cValid_m ),
    .diTag_m         (          dTag_m ),
    .ciLRU_m         (          cLRU_m ),
    
    // Output controls
    .coLRU_WData     (      cLRU_WData ),
    .coLRU_WSet      (       cLRU_WSet ),     
    .coLRU_WE        (         cLRU_WE ),       
    .coCacheWE       (        cCacheWE ),      
    .doCache_WSet    (     dCache_WSet ),   
    .doCache_WWay    (     dCache_WWay ),   
    .coCache_WDirty  (   cCache_WDirty ), 
    .coInput_Store   (    cInput_Store ),   
    .coInput_bypass  (   cInput_bypass ),
    .coData_Src      (       cData_Src ),
    .coData_WselW    (     cData_WselW ),   
    .coData_BlselR   (    cData_BlselR ),    
    .coData_WselR    (     cData_WselR ),
    .coMemory_WE     (      cMemory_WE ),  
    .coStall         (         coStall ),
    .doUpMem_address ( doUpMem_address )
  );
  
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Control Unit for Cache
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
module Cache_CU#(
  parameter LOGWIDTH    = 5,  // Port width
  parameter LOG_NWAYS   = 1,  // N-Way set associativity, for now restricted to 2-Way only!
  parameter LOG_NSETS   = 2,  // Number of sets
  parameter LOG_NWORDS  = 2,  // Number of words in set
  parameter TAGSIZE     = 26, // Tag size, == Width-log_Nsets-log_nwords-byte_offset
  parameter MEM_LATENCY = 2   // M10K latency in cycles
  )( 
  // Control signals
  input  logic                                              clk,
  input  logic                                              rst,
  
  input  logic                                             ciWE,
  input  logic                                             ciENA, // Enable signal for not-invoking meaningless cache misses
  input  logic                                          ciCANCEL,
  
  // Input data
  input  logic  [           2**LOGWIDTH  -1:0 ]          diAddr, // TODO: use diAddr_cur only ( maybe slower somewhere but less interconnect usage )
  input  logic  [           2**LOGWIDTH  -1:0 ]      diAddr_cur,
  input  logic  [                     1  -1:0 ]       ciDirty_m   [ 2**LOG_NSETS * 2**LOG_NWAYS  -1:0 ],
  input  logic  [                     1  -1:0 ]       ciValid_m   [ 2**LOG_NSETS * 2**LOG_NWAYS  -1:0 ],
  input  logic  [               TAGSIZE  -1:0 ]         diTag_m   [ 2**LOG_NSETS * 2**LOG_NWAYS  -1:0 ],
  input  logic  [             LOG_NWAYS  -1:0 ]         ciLRU_m   [                2**LOG_NSETS  -1:0 ],
    // Output controls
  output logic  [             LOG_NWAYS  -1:0 ]     coLRU_WData,
  output logic  [             LOG_NSETS  -1:0 ]      coLRU_WSet,     
  output logic                                         coLRU_WE,       
  output logic                                        coCacheWE,      
  output logic  [             LOG_NSETS  -1:0 ]    doCache_WSet,   
  output logic  [             LOG_NWAYS  -1:0 ]    doCache_WWay,   
  output logic                                   coCache_WDirty, 
  output logic                                    coInput_Store,   
  output logic                                   coInput_bypass,   
  output logic                                       coData_Src,  
  output logic  [            LOG_NWORDS  -1:0 ]    coData_WselW,   
  output logic  [ LOG_NSETS + LOG_NWAYS  -1:0 ]   coData_BlselR,   
  output logic  [            LOG_NWORDS  -1:0 ]    coData_WselR,
  output logic                                      coMemory_WE,   
  output logic                                          coStall,
  output logic  [  TAGSIZE + LOG_NSETS  -1:0 ]  doUpMem_address
  );    
  
  integer i, ind;
  localparam BYTEOFFSET = 2;
  // Address recognition
  logic [      TAGSIZE  -1:0 ]   diTag, diTag_cur;
  logic [    LOG_NSETS  -1:0 ]   diSet, diSet_cur;
  logic [   LOG_NWORDS  -1:0 ]   diBlock, diBlock_cur;
  logic [   BYTEOFFSET  -1:0 ]   diBO, diBO_cur;  // meaningless trash for convenience
  
  assign { diTag,     diSet,     diBlock,     diBO     } = diAddr;
  assign { diTag_cur, diSet_cur, diBlock_cur, diBO_cur } = diAddr_cur;
  
  // ++++++++++++++++++ Hit and way logic ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  logic [ 2**LOG_NWAYS  -1:0 ]   cHits; // One hit bit per way
  logic                          cHit;  // Overall hit
  logic                          cWay, cWay_lock;  // Selected way; IMPLEMENTATION LIMIT: 1-bit width means 2-Way organisation at most
  
  always_comb begin
    for( i = 0; i < 2**LOG_NWAYS; i = i + 1 ) begin
      ind = 2**LOG_NWAYS * diSet + i;
      cHits[i] = ( ( diTag ) == ( diTag_m[ ind ] ) ) && ciValid_m[ ind ] ;
    end    
  end
  
  assign cHit = |(cHits);
    
  assign cWay = ( cHit ) ? ( cHits[1] ) : ( ciLRU_m[diSet] );
  
  logic                           cState_store;
  logic                           cWE_lock;
  always_ff@( posedge clk or posedge rst ) begin
    if(rst) begin
      cWay_lock <= 1'b0;
      cWE_lock  <= 1'b0;
    end
    else if(cState_store) begin
      cWay_lock <= cWay;
      cWE_lock  <= ciWE;
    end
  end
  
  // ++++++++++++++++++ Write-Back detect logic ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // Block address in cache memory = ( 2**LOG_NWAYS * Set + Way )
  logic                       cDoWB;
  assign cDoWB = ( (ciDirty_m[ 2**LOG_NWAYS * diSet + cWay ])  &&  (ciValid_m[ 2**LOG_NWAYS * diSet + cWay ]) );
  
  // ++++++++++++++++++ Write-Back/Read address select +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  // WARNING: Using diSet instead of diSet_cur is faster but works properly only if initialised on stage S0 !!!
  assign  doUpMem_address        =    ( coMemory_WE ) ? ( {  diTag_m[ 2**LOG_NWAYS * diSet + cWay] , diSet } ) : 
                                                        ( diAddr_cur[ 2**LOGWIDTH  -1 : 2**LOGWIDTH - TAGSIZE - LOG_NSETS ] );
                                      
  // ++++++++++++++++++ Control unit ( State machine ) +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    // State  Mean                Action                                      Next state
    // S0     Cache operation     Immediate response if hit, stall if miss    ( Hit ) ? S0 : ( !D || !V ) ? S2 : S1
    // S1     Memory write        Writing from cache to memory                ( Mem finish ) ? S2 : S1
    // S2     Memory read         Reading from memory to cache                ( Mem finish ) ? S3 : S2
    // S3     Cache operation     Final cache operation after cache miss      S0
    
  logic  cMemFinish, cMem_Init;
  logic  [ MEM_LATENCY  :1 ]  cnt;
  always_ff@(posedge clk or posedge rst) begin
    if(rst)
      cnt <= 0;
    else if( cMem_Init ) cnt <= { {MEM_LATENCY-1{1'b0}}, 1'b1 };
    else cnt <= cnt << 1;
  end
  assign  cMemFinish = cnt[MEM_LATENCY];
  
  enum int unsigned { S0 = 0, S1 = 1, S2 = 2, S3 = 4 } state, next_state;
  
  // TODO: recognition if cancelling is unnecessary ( currently loading data block is to be fetched in next operation )
  always_comb begin : next_state_logic
    case(state)
      S0: next_state =  (       ciCANCEL ) ?  ( S0 ) : 
                        ( !ciENA || cHit ) ?  ( S0 ) : // Cache hit;  In-cache operation
                        (          cDoWB ) ?  ( S1 ) : // Cache miss; Write back before fetch from upper - level memory
                                              ( S2 ) ; // Cache miss; Fetch from upper level memory without write-back operation
      S1: next_state =  (       ciCANCEL ) ?  ( S0 ) :
                                              ( S2 ) ; // Go to reading phase ( Immediately due to M10K pipelining );
      S2: next_state =  (       ciCANCEL ) ?  ( S0 ) :
                        (     cMemFinish ) ?  ( S3 ) : // Go to Cache phase;
                                              ( S2 ) ; // Waiting until operation is complete
      S3: next_state =                          S0   ; // Transition to normal operation
    endcase
  end
  
  always_ff@(posedge clk or posedge rst) begin
    if(rst)
      state <= S0;
    else
      state <= next_state;
  end
  
  always_comb begin
    case(state)
      S0: begin         // Input command parsing; immediate response if hit.
        coLRU_WData     =  !cWay;
        coLRU_WSet      =  diSet;
        coLRU_WE        =  ciENA && cHit;
        coCacheWE       =  ciENA && cHit  && ciWE;
        doCache_WSet    =  diSet;                     // TODO: seems to writeaddr == dAddr_cur
        doCache_WWay    =  cWay;
        coCache_WDirty  =  ciWE;                      // not important value
        coInput_Store   =  1'b1;                      // for less logic usage, for possibly less dynamic power use "!cHit"
        coInput_bypass  =  1'b1;
        coData_Src      =  1'b0;
        coData_WselW    =  diBlock;
        coData_BlselR   =  { diSet, cWay };
        coData_WselR    =  diBlock;
        coMemory_WE     =  ciENA && cDoWB && !cHit;
        cMem_Init       =  ciENA && !cHit;
        coStall         =  ciENA && !cHit;
        cState_store    =  1'b1;                      // for less logic usage, for possibly less dynamic power use "!cHit"
      end
      S1: begin         // Writing from cache to memory
        coLRU_WData     =  !cWay_lock;                // meaningless because of WE==0
        coLRU_WSet      =  diSet_cur;                 // meaningless because of WE==0
        coLRU_WE        =  1'b0;                
        coCacheWE       =  1'b0;                
        doCache_WSet    =  diSet_cur;                 // meaningless because of WE==0
        doCache_WWay    =  cWay_lock;                 // meaningless because of WE==0
        coCache_WDirty  =  1'b0;                      // meaningless because of WE==0
        coInput_Store   =  1'b0;                
        coInput_bypass  =  1'b0;   
        coData_Src      =  1'b1;                      // meaningless because of WE==0
        coData_WselW    =  diBlock_cur;               // meaningless because of WE==0
        coData_BlselR   =  { diSet_cur, cWay_lock };
        coData_WselR    =  diBlock_cur;               // meaningless but forces output currently re-writed data
        coMemory_WE     =  1'b0;
        cMem_Init       =  1'b1;
        coStall         =  1'b1;
        cState_store    =  1'b0;
      end
      S2: begin         // Reading from memory to cache
        coLRU_WData     =  !cWay_lock;                // meaningless because of WE==0
        coLRU_WSet      =  diSet_cur;                 // meaningless because of WE==0
        coLRU_WE        =  1'b0; 
        coCacheWE       =   cnt[MEM_LATENCY];         // for easier simulation and less dyanmic power; can use 1'b1; for less logic usage
        doCache_WSet    =  diSet_cur;
        doCache_WWay    =  cWay_lock;
        coCache_WDirty  =  1'b0;
        coInput_Store   =  1'b0;
        coInput_bypass  =  1'b0;
        coData_Src      =  1'b1;
        coData_WselW    =  diBlock_cur;               // meaningless because of cData_Src = 1
        coData_BlselR   =  { diSet_cur, cWay_lock };  // meaningless because nothing to read
        coData_WselR    =  diBlock_cur;               // meaningless because nothing to read
        coMemory_WE     =  1'b0;
        cMem_Init       =  1'b0;
        coStall         =  1'b1;
        cState_store    =  1'b0;
      end
      S3: begin         // Final cache operation after cache miss 
        coLRU_WData     =  !cWay_lock;
        coLRU_WSet      =  diSet_cur;
        coLRU_WE        =  1'b1;
        coCacheWE       =  cWE_lock;
        doCache_WSet    =  diSet_cur;
        doCache_WWay    =  cWay_lock;
        coCache_WDirty  =  cWE_lock;
        coInput_Store   =  1'b0;
        coInput_bypass  =  1'b0;
        coData_Src      =  1'b0;
        coData_WselW    =  diBlock_cur;
        coData_BlselR   =  { diSet_cur, cWay_lock };
        coMemory_WE     =  1'b0;
        cMem_Init       =  1'b0;
        coData_WselR    =  diBlock_cur;
        coStall         =  1'b0;    // possibly 1'b1
        cState_store    =  1'b0;
      end
    endcase
  end
endmodule

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Testbench for cache
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Checked data evolution 
// Signal\Stage        S0                        S1           S2         S3
// doReadData     | hit    -> Requested data  |            |          | New data
//                | miss   -> Old data        -> --//--    -> --//--  |
//                |           to be replaced  |            |          |
//  coStall       | Hit    -> 0               |            |          | 0
//                | miss   -> 1               | 1          | 1        |
//  doUpMem_addr  | w/o WB -> diAddr[31:3]    -> Addr_buf  -> --//--  -> --//-- 
//                | WB     -> WBAddr          |            |          |
//  doUpMem_data  | hit    -> Requested       |            |          | New data block
//                |           data's block    |            |          |
//                | miss   -> Old block       -> --//--    -> --//--  |
//                |           to be replaced  |            |          |
//  doUpMem_WE    | hit    -> 0               |            | 0        | 0
//                | miss   -> ( Write-Back )  | 1          |          |
//                                            |            |          |
module Testbench_Cache#(
  parameter LOGWIDTH = 5
  )(
);
  // basic control  
  logic clk, Srst;
  
  // Test input signals to DUT
  logic [ 2**LOGWIDTH - 1:0]           dut_Addr, dut_WriteData;
  logic                                dut_WE, dut_ENA;
  
  // DUT output signals and their checking expecteds
  logic [ 2**LOGWIDTH - 1:0]           RD, RD_EX;
  logic                                Stall, Stall_EX;
  
  // DUT <-> M10K interface         
  logic  [           28  - 1: 0 ]      mem_address, mem_address_EX;    // WARNING: MAGIC VALUE (26) = TAGSIZE
  logic                                mem_clock;         
  logic  [ 4 * 2**LOGWIDTH - 1:0]      mem_data,    mem_data_EX;       // WARNING: MAGIC VALUE (4) = NWORDS
  logic                                mem_wren,    mem_wren_EX;           
  logic  [ 4 * 2**LOGWIDTH - 1:0]      mem_q;                          // WARNING: MAGIC VALUE (4) = NWORDS

  // Testbench related
  logic [ 8*( 2**LOGWIDTH ) + 4*4 - 1 :0] testvectors[10000:0]; // ADDR_WDATA_WE_ENA_RDATA_STALL_(M10K-ADDR)_(M10K-WDATA)_(M10K-WE)
  logic [ 31:0]        vectornum, errors;
  logic [ LOGWIDTH - 1    :0] bit_cnt; 
  
  logic  [17:0] tr;
  
  // instantiate under test
  Cache#(
    .LOGWIDTH    ( 5 ), // Port width
    .LOG_NWAYS   ( 1 ), // N-Way set associativity, for now restricted to 2-Way only!
    .LOG_NSETS   ( 2 ), // Number of sets
    .LOG_NWORDS  ( 2 ), // Number of words in set
    .MEM_LATENCY ( 2 )  // M10K latency in cycles
  ) dut ( 
    // Global control
    .clk                    (                clk ),
    .rst                    (               Srst ),
      
    // Downlink memory interface  
    .diAddr                 (           dut_Addr ),
    .diWriteData            (      dut_WriteData ),
                                        
    .ciWE                   (             dut_WE ),
    .ciENA                  (            dut_ENA ), // Read-enable for not-invoking meaningless operations
                                        
    .doReadData             (                 RD ),
                                        
    .coStall                (              Stall ),
    
    // Uplink memory interface
    .doUpMem_address         (        mem_address ),
    .coUpMem_clock           (          mem_clock ),
    .doUpMem_data            (           mem_data ),
    .coUpMem_wren            (           mem_wren ),
    .diUpMem_q               (              mem_q )
  );  
  
  // L2 M10K module
  
  RAM_L2 #0  Memory (
    .address_a  ( mem_address[8:0] ),             // WARNING: MAGIC VALUE (7) = mem_address width +1
    .address_b  (          {9'h00} ),
    .clock      (        mem_clock ),
    .data_a     (         mem_data ),
    .data_b     (        { 128'h0} ),             // WARNING: MAGIC VALUE (128)
    .wren_a     (         mem_wren ),
    .wren_b     (             1'b0 ),
    .q_a        (            mem_q ),
    .q_b        (                  )
  );
  
  
  // generate clock
  always  begin
      clk=0; #5; clk=1; #5;
  end
  
  // at start, load vectors and pulse Srst
  initial
    begin
      $readmemh("../../Source/Cache/test.tv",testvectors);
      vectornum = 0; errors = 0; bit_cnt = 0;
      Srst = 1; #27; Srst=0;
    end 
      
  // apply test vectors on rising edge of clk
  always@(posedge clk)
    begin
      // format hhhhhhhh_hhhhhhhh_b_b_hhhhhhhh_b_hhhhhhhh_hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh_b
      #1; { dut_Addr, dut_WriteData,  tr[17:15],
            dut_WE,   tr[14:12],      dut_ENA, 
            RD_EX,    tr[11:9],       Stall_EX, 
            mem_address_EX,           tr[8:5], 
            mem_data_EX,              tr[2:0],  mem_wren_EX} = testvectors[ vectornum ];
    end
  
  // check at falling edge of clk
  always @( negedge clk )
    if( ~Srst ) begin // skip during reset
      if( ( RD != RD_EX ) || ( Stall != Stall_EX ) ) begin
       $display( "Error: step %d", vectornum );
       $display( " legend:  RD          Stall");
       $display( " outputs  = %h, %b", RD, Stall    );
       $display( " expected = %h, %b", RD_EX, Stall_EX );
       errors += 1;
      end
      if( ( mem_address != mem_address_EX ) || ( mem_data != mem_data_EX ) || ( mem_wren != mem_wren_EX ) ) begin
       $display( "Error: step %d", vectornum );
       $display( " legend:  mem_address          mem_data           mem_wren");
       $display( " outputs  = %h, %h, %b", mem_address, mem_data,  mem_wren   );
       $display( " expected = %h, %h, %b", mem_address_EX, mem_data_EX,mem_wren_EX  );
       errors += 1;
      end
      
      vectornum += 1;
      if( testvectors[ vectornum ][ 0 ] === 1'bx ) begin
      $display( "%d tests complete with %d errors", vectornum, errors );
      $finish;
      end
    end
    
endmodule