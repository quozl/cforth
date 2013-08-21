: left-parse-string  ( adr len delim -- tail$ head$ )
   split-string  dup if  1 /string  then  2swap
;
: 2nip  ( n1 n2 n3 n4 -- n3 n4 )  2swap 2drop  ;

0 value instruction    \ Current thumb instruction
0 value dis-pc         \ Address of next instruction
defer thumb-op@        \ How to access the instruction stream
' w@ to thumb-op@

\ Fetch next instruction and advance PC
: @op  ( -- )  dis-pc thumb-op@ to instruction  dis-pc wa1+ to dis-pc  ;
: .instruction  ( -- )  @op push-hex instruction 4 u.r space  pop-base  ;

\ Given a string containing instruction names separated
\ by spaces, display the one selected by "index"
: .op  ( adr len index -- )
   >r                         ( adr len )
   bl left-parse-string       ( rem$ head$ )
   r> 0  ?do                  ( rem$ head$ )
      2drop                   ( rem$ )
      bl left-parse-string    ( rem$ head$ )
   loop                       ( rem$ head$ )
   2swap 2drop                ( name$ )
   tuck type                  ( name-len )
   \ Advance to argument field
   d# 8 over - spaces         ( )
;
   
\ Return the instruction bit at the indicated position
: op-bit  ( bit# -- mask )  1 swap lshift instruction and  ;

\ Return the instruction bit field at the indicated position
: op-bits  ( bit# #bits -- n )
   instruction rot rshift  ( #bits op )
   1 rot lshift 1-         ( op mask )
   and
;

\ The op1 field often selects instructions within a format group
: op1 ( -- bits )  #11 2 op-bits  ;

\ Bit 11 often chooses one of two instructions within a format group
: bit11  ( -- n )  #11 op-bit  ;

\ Display the indicated bit field as an unsigned offset 
: .offset  ( bit# #bits -- )  op-bits ." #" (.) type  ;
: .offset5  6 5 .offset  ;
: .offset8  0 8 .offset  ;

\ Display the lower 8 bits as a signed offset
: .soffset  ( #bits -- )  0 swap op-bits  ." #" s.  ;

\ Display various components of an argument field
: .,  ." ,"  ;
: .]  ." ]"  ;
: .[  ." ["  ;
: .}  ." }"  ;
: .sp,  ." SP,"  ;
: .lr  ." LR"  ;
: .pc  ." PC"  ;
: .pc,  .pc .,  ;

\ Display a register number
: .reg   ( reg# -- )  ." R" push-decimal (.) type pop-base  ;

\ Display a register number followed by a comma
: .reg,  ( reg# -- )  .reg .,  ;

\ Display a register number given the lower bit#
: .r#    ( bit# -- )  3 op-bits .reg   ;

\ Display a register number given the lower bit#, followed by a comma
: .r#,   ( bit# -- )  3 op-bits .reg,  ;

\ Display common register fields
: .r0,  0 .r#,  ;
: .r3,  3 .r#,  ;
: .r6   6 .r#   ;
: .r8,  8 .r#,  ;

\ Display a register number including the high registers
: .rh    ( reg# -- )
   case
      d# 15 =  of  ." PC"  endof
      d# 14 =  of  ." LR"  endof
      d# 13 =  of  ." SP"  endof
      dup .reg
   endcase
;

\ Display high register from the field at bit# 0
\ Its high bit is in bit 7
: .rh0   ( bit# -- )  0 3 op-bits  7 op-bit  if 4 or  then  .rh  ;

\ Display high register from the field at bit# 3
\ Its high bit is adjacent to its low bits (in bit 6)
: .rh3   ( -- )  3 4 op-bits  .rh  ;

\ Display a list of registers
: .{rlist
   ." {"  0 8 op-bits              ( rembits )
   8 0  do                         ( rembits )
      dup 1 and  if  i .reg  then  ( rembits )
      2/  dup  if  .,  then        ( rembits' )
   loop                            ( rembits )
   drop
;

\ Display instructions from various format groups
: fmt1   \ e.g. LSL  R1,R2,#24
   " LSL LSR ASR" op1 .op
   .r0, .r3, .offset5
;
: fmt2   \ e.g. ADD  R1,R2,#24  or  ADD R1,R2,R3
  " ADD SUB" d# 9 op-bit .op
   .r0, .r3,  d# 10 op-bit  if  0 3 .offset  else  .r6  then
;
: fmt3   \ e.g. MOV R1,#1234
   " MOV CMP ADD SUB" op1 .op
   .r8,  .offset8
;
: fmt4   \ e.g. AND R1,R2
   " AND EOR LSL LSR ASR ADC SBC ROR TST NEG CMP CMN ORR MUL BIC MVN" d# 6 4 op-bits .op
   .r0, 3 .r#
;
: fmt5   \ e.g. ADD R13,R5
   " ADD CMP MOV BX" 8 2 op-bits .op
   8 2 op-bits 3 <>  if  .rh0 .,  then  .rh3
;
: fmt6   \ e.g. LDR  R1,[PC,#24]
   " LDR" 0 .op
   .r8, .[ .pc, .offset8 .]
;
: fmt7/8  \ e.g. STR R1,[R2,R3]
   " STR STRH STRB LDRSB LDR LDRH LDRB LDRSH" 9 3 op-bits .op
   .r0, .[ .r3, .r6 .]
;
: fmt9   \ e.g STR R1,[R2,#24]
   " STR LDR STRB LDRB" op1 .op
   .r0, .[ .r3, .offset5 .]
;
: fmt10  \ e.g. STRH R1,[R2,#24]
   " STRH LDRH" bit11 .op
   .r0, .[ .r3, .offset5 .]  
;
: fmt11  \ e.g. STR R1,[SP,#24]
   " STR LDR" bit11 .op
   .r0, .[ .sp, .offset8 .]
;
: fmt12  \ e.g. ADD R1,SP,#1234
   " ADD" 0 .op
   .r8,  bit11  if  .sp,  else  .pc,  then  .offset8
;
: fmt13  \ e.g. ADD SP,#1234
   " ADD" 0 .op
   .sp, 8 .soffset
;
: fmt14  \ e.g. PUSH {R1,R2,LR}
   " PUSH POP" bit11 .op
   .{rlist
   8 op-bit  if
      .,
      bit11  if  .pc  else  .lr  then
   then
   .}
;
: fmt15  \ e.g. STMIA R1!,{R1,R2}
   " STMIA LDMIA" bit11 .op
   8 .r# ." !," .{rlist .}
;
: fmt16  \ e.g. BEQ #1234
   " BEQ BNE BCS BCC BMI BPL BVS BVC BHI BLS BGE BLT BGT BLE" 8 4 op-bits .op
   .offset8
;
: fmt17  \ e.g. SWI #24
   " SWI" 0 .op
   .offset8
;
: fmt18  \ e.g. B #1234
   " B  BLX" bit11 .op
   0 #11 .soffset
;
: fmt19  \ Complicated by THUMB-2
   .instruction 
;

base @ hex
create op-table
e0 c, 00 c, ' fmt1 token,
f8 c, 18 c, ' fmt2 token,
e0 c, 20 c, ' fmt3 token,
fc c, 40 c, ' fmt4 token,
fc c, 44 c, ' fmt5 token,
f8 c, 48 c, ' fmt6 token,
f0 c, 50 c, ' fmt7/8 token,
e0 c, 60 c, ' fmt9 token,
f0 c, 80 c, ' fmt10 token,
f0 c, 90 c, ' fmt11 token,
f0 c, a0 c, ' fmt12 token,
ff c, b0 c, ' fmt13 token,
f6 c, b4 c, ' fmt14 token,
f0 c, c0 c, ' fmt15 token,
ff c, df c, ' fmt17 token,
f0 c, d0 c, ' fmt16 token,
f0 c, e0 c, ' fmt18 token,
f0 c, f0 c, ' fmt19 token,
here op-table - constant /op-table
base !

: dis1  ( -- )
   push-hex  dis-pc 8 u.r 2 spaces  pop-base
   .instruction
   op-table  /op-table  bounds  do
      instruction 8 rshift        ( opcode-bits )
      i c@ and   i 1+ c@  =  if   ( )
         i 2+ token@ execute      ( )
	 unloop exit              ( -- )
      then                        ( )
   /token 2+ +loop                ( )
   true abort" Op decode error!"
;

: end-dis?  ( -- flag )  key?  dup  if  key drop  then  ;
: +dis  ( -- )
   begin  end-dis? 0=  while  dis1  repeat	 
;

: dis  ( adr -- )   to dis-pc  +dis  ;
