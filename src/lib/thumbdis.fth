: left-parse-string  ( adr len delim -- tail$ head$ )
   split-string  dup if  1 /string  then  2swap
;
: 2nip  ( n1 n2 n3 n4 -- n3 n4 )  2swap 2drop  ;

0 value op             \ Current thumb instruction
0 value op2            \ Second half of current thumb instruction
0 value dis-pc         \ Address of next instruction
0 value arm-pc         \ PC value for address calculations
defer thumb-op@        \ How to access the instruction stream
' w@ to thumb-op@

: thumb-l@  ( adr -- l )  dup thumb-op@  swap wa1+ thumb-op@  wljoin  ;

\ Fetch next instruction and advance PC
: 4.x  ( w -- )  push-hex <# u# u# u# u# u#> pop-base  type space  ;
: @op  ( -- )  dis-pc thumb-op@ to op   dis-pc wa1+ to dis-pc  dis-pc wa1+ to arm-pc  ;
: @op2 ( -- )  dis-pc thumb-op@ to op2  dis-pc wa1+ to dis-pc  ;
: .instruction   ( -- )  @op  op  4.x  ;
: .instruction2  ( -- )  @op2 op2 4.x  ;

: select-substring  ( adr len index -- $ )
   >r                         ( adr len )
   bl left-parse-string       ( rem$ head$ )
   r> 0  ?do                  ( rem$ head$ )
      2drop                   ( rem$ )
      bl left-parse-string    ( rem$ head$ )
   loop                       ( rem$ head$ )
   2swap 2drop                ( $ )
;

: to-op  ( namelen -- )
   \ Advance to argument field
   d# 8 over - 0 max  spaces  ( )
;

\ Given a string containing instruction names separated
\ by spaces, display the one selected by "index"
: .opx  ( adr len index -- )
   select-substring  tuck type  ( name-len )
   to-op
;
: .op  ( adr len index -- )  5 spaces .opx  ;

\ Return the instruction bit at the indicated position
: op-bit  ( bit# -- mask )  op swap rshift 1 and  ;
: op2-bit  ( bit# -- mask )  op2 swap rshift 1 and  ;

\ Return the instruction bit field at the indicated position
: op-bits  ( bit# #bits -- n )
   op rot rshift  ( #bits op )
   1 rot lshift 1-         ( op mask )
   and
;
: op2-bits  ( bit# #bits -- n )
   op2 rot rshift  ( #bits op )
   1 rot lshift 1-         ( op mask )
   and
;

\ The op1 field often selects instructions within a format group
: op1 ( -- bits )  #11 2 op-bits  ;

\ Bit 11 often chooses one of two instructions within a format group
: bit11  ( -- n )  #11 op-bit  ;

: .#  ." #"  ;
: .#n  .# (.) type  ;
\ Display the indicated bit field as an unsigned offset 
: offset8  0 8 op-bits  ;
: .offset  ( bit# #bits -- )  op-bits .#n  ;
: .offset5  6 5 .offset  ;
: .offset8  0 8 .offset  ;

\ Display the lower 8 bits as a signed offset
: .soffset  ( #bits -- )  0 swap op-bits  .# s.  ;

: .taddr  ( #bits -- )
   0 swap op-bits  .# dup s.
   ." ( " arm-pc + dup 1 invert and .x
   1 and  if ." T " then  ." )"  \ T for thumb mode
;

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
: .r3   3 .r#   ;
: .r3,  3 .r#,  ;
: .r6   6 .r#   ;
: .r8,  8 .r#,  ;

\ Display a register number including the high registers
: .rh    ( reg# -- )
   case
      d# 15 of  ." PC"  endof
      d# 14 of  ." LR"  endof
      d# 13 of  ." SP"  endof
      dup .reg
   endcase
;

\ Display high register from the field at bit# 0
\ Its high bit is in bit 7
: .rh0   ( bit# -- )  0 3 op-bits  7 op-bit  if 8 or  then  .rh  ;

\ Display high register from the field at bit# 3
\ Its high bit is adjacent to its low bits (in bit 6)
: .rh3   ( -- )  3 4 op-bits  .rh  ;

\ Display a list of registers
: .{rlist
   ." {"  offset8                  ( rembits )
   8 0  do                         ( rembits )
      dup 1 and  if                ( rembits )
         i .reg                    ( rembits )
         dup 2/  if  .,  then      ( rembits )
      then                         ( rembits )
      2/                           ( rembits' )
   loop                            ( rembits )
   drop
;

\ Display instructions from various format groups
: fmt1   \ e.g. LSL  R1,R2,#24
   " LSL LSR ASR" op1 .op
   .r0, .r3, push-decimal .offset5 pop-base
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
   .r8, .[ .pc, offset8 /l* dup .#n .]
   ."  ( " arm-pc 3 invert and + dup .x ." : " thumb-l@ .x ." ) "
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
: .bop  ( bit# -- )
   " BEQ BNE BCS BCC BMI BPL BVS BVC BHI BLS BGE BLT BGT BLE"
   rot 4 op-bits .op
;
: fmt16  \ e.g. BEQ #1234
   8 .bop
   .offset8
;
: fmt17  \ e.g. SWI #24
   " SWI" 0 .op
   .offset8
;
: fmt18  \ e.g. B #1234
   " B" 0 .op
   0 #11 .taddr
;
: fmt19  \ Complicated by THUMB-2
   .instruction 
;

: xtnd
   " SXTH SXTB UXTH UXTB" #10 2 op-bits .op
   .r0, .r3
;
: cps  \ 1011 0110 011 Im 0 0 I F
   \ XXX should check that  5 3 op-bits  3 =
   " CPSID CPSIE" 4 op-bit .op
   1 op-bit if ." I" then
   0 op-bit if ." F" then
;
: cbxz
   " CBZ CBNZ" bit11 .op
   .r0, 0 5 op-bits
   9 op-bit  if  h# ffff.ffe0 or  then  ." #" dup s.
   ." ( " arm-pc + .x ." )"      ( )
;
: brev
   " REV REV16 ??? REVSH" 6 2 op-bits .op
   .r0, .r3
;
: bkpt
   " BKPT" 0 .op
   8 .soffset
;
: .shift  ( count type -- )
   case
      0 of  ." LSL "  endof
      1 of  ." LSR "  ?dup 0=  if  #32  then  endof
      2 of  ." ASR "  ?dup 0=  if  #32  then  endof
      3 of  dup  if  ." ROR"  else  ." RRX "  1+  then  endof
   endcase
   .d
;
: .xshift
   6 2 op2-bits  #12 3 op2-bits  2 lshift or
   4 2 op2-bits  .shift
;
: .ops  ( adr len -- )
   tuck type  ( len )
   4 op-bit  if  ." S" 1+  then
   to-op
;
: .dprs
   .ops
   8 4 op2-bits .rh .,
   0 4 op-bits .rh .,
   0 4 op2-bits .rh .,
   .xshift
;
: .andr " AND" .dprs  ; \ 0  TST if Rd is PC
: .bicr " BIC" .dprs  ; \ 1
: .orrr " ORR" .dprs  ; \ 2  MOV if Rn is PC
: .ornr " ORN" .dprs  ; \ 3  MVN if Rn is PC
: .eorr " EOR" .dprs  ; \ 4  TEQ if Rd is PC
: .addr " ADD" .dprs  ; \ 8  CMN if Rd is PC
: .adcr " ADC" .dprs  ; \ a
: .sbcr " SBC" .dprs  ; \ b

0 [if]
: .addbi  " ADD"  .dpbi  ; \ 0  ADR if Rn is PC
: .movbi  " MOV"  .dpbi  ; \ 4
: .subbi  " SUB"  .dprs  ; \ a  ADR if Rn is PC
: .movtbi " MOVT" .dpbi  ; \ c

: .ssatbi " SSAT" .dpbi  ; \ 10 and 12
: .sbfxbi " SBFX" .dpbi  ; \ 14
: .bfibi  " BRI"  .dpbi  ; \ 16
: .usatbi " USAT" .dpbi  ; \ 18 and 1a
: .ubfxbi " UBFX" .dpbi  ; \ 1c
[then]


: ifthn
   0 4 op-bits  if
      " IT" 0 .op
      0 4 op-bits .x ., 4 4 op-bits .x
   else
      " NOP YIELD WFE WFI SEV" 4 4 op-bits .op
   then
;
: .???  ." ???"  ;
: ldst
   .instruction2
   6 op-bit  if
      " LDSTdual_excl_table_branch" 0 .opx  .???
   else
      " STM LDM" 4 op-bit .opx
      .rh0  ., .???
   then
;
: dps
   .instruction2
   " Shifted_register" 0 .opx  .???
;
: copr
   .instruction2
   " Coprocessor" 0 .opx  .???   
;
: si1i2imm12  ( -- 3hibits imm12 )
   #10 op-bit              dup  #31 lshift      ( s 1hibits )
   over  #13 op2-bit xor 1 xor  #30 lshift or   ( s 2hibits )
   swap  #11 op2-bit xor 1 xor  #29 lshift or   (   3hibits )

   0 #11 op2-bits 2*                            ( 3hibits imm12 )
;
: .relpc  ( simm -- )
   .PC  dup dup 0<  if           ( simm simm )
      ." -" negate               ( simm -imm )
   else                          ( simm imm )
      ." +"                      ( simm +imm )
   then                          ( simm uimm )
   .x                            ( imm )
   ." ( " arm-pc + .x ." )"      ( )
;
: .xbranch
   " B BL" #14 op2-bit .opx
   si1i2imm12                    ( 3hibits imm12 )
   0 #10 op-bits #12 lshift or   ( 3hibits imm22 )
   swap 7 >>a  or                ( simm )
   .relpc
;
: .specreg  ( -- )
   offset8 20 >  if
      ." RSVD"
   else
      \ 0    1     2     3    45    6    7     8   90123456       7       8           9         0
      " APSR IAPSR EAPSR XPSR  IPSR EPSR IEPSR MSD        PRIMASK BASEPRI BASEPRI_MAX FAULTMASK CONTROL"
      offset8 select-substring type
   then
;
: .msr
   " MSR" 0 .opx
   .specreg ., 0 4 op-bits .rh
;
: .mrs
   " MRS" 0 .opx
   0 4 op-bits .rh ., .specreg
;
: .undef  " ???" 0 .opx  ;
: .hint
   8 3 op2-bits 0<>  if  " CPS" 0 .opx  .???  exit  then
   4 4 op2-bits $f =  if  " DBG" 0 .opx  0 4 op2-bits .#n  exit  then
   3 5 op2-bits 0<>  if  .undef  exit  then
   " NOP YIELD WFE WFI SEV ? ? ?" 0 4 op2-bits .opx
;
: .msc
   4 4 op2-bits  dup 6 <  if
      \ 012     34   5   6
      "   CLREX  DSB DMB ISB" rot .opx
   else
      drop  .undef
   then
;   
: .xcondbranch
   6 .bop   
   si1i2imm12                    ( 3hibits imm12 )
   0 6 op-bits #12 lshift or     ( 3hibits imm18 )
   swap #11 >>a  or              ( simm )
   .relpc

;
: .xmisc  ( -- )  \ op2 bits 12 and 14 are both 0
   7 3 op-bits 7 =  if
      5 2 op-bits  case
	 0 of  .msr  endof
	 1 of  4 op-bit  if  .msc  else  .hint  then  endof
	 2 of  .undef  endof
	 3 of  .mrs    endof
      endcase
   else
      .xcondbranch
   then
;

: xrd  ( -- n )  8 4 op2-bits  ;
: xrn  ( -- n )  0 4 op-bits  ;
: .xdp
   9 op-bit  if
      " XDPBinaryImmediate"
   else
      xrd $f =  if
         " " 2drop
      else
      then

      " XDPModifiedImmediate"
   then
   0 .opx  .???
;
: opf0
   .instruction2
   #15 op2-bit  if
      #12 op2-bit  if  .xbranch  else  .xmisc  then
   else
      .xdp
   then
;

: xldst
   .instruction2
   " XLDST" 0 .opx  .???
;
: xmul
   .instruction2
   " XMUL" 0 .opx  .???
;
: xdpr
   .instruction2
   " XDPR" 0 .opx  .???
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
ff c, b6 c, ' cps   token,
ff c, b2 c, ' xtnd  token,
f5 c, b1 c, ' cbxz  token,
f6 c, b4 c, ' fmt14 token,
ff c, ba c, ' brev  token,
ff c, be c, ' bkpt  token,
ff c, bf c, ' ifthn  token,
f0 c, c0 c, ' fmt15 token,
ff c, df c, ' fmt17 token,
f0 c, d0 c, ' fmt16 token,
f8 c, e0 c, ' fmt18 token,
fe c, e8 c, ' ldst  token,  \ Load Store
fe c, ea c, ' dps   token,  \ Data Processing Shifted
ec c, ec c, ' copr  token,  \ Coprocessor
f8 c, f0 c, ' opf0  token,  \ Additional 32-bit instructions
fe c, f8 c, ' xldst token,  \ Data Processing Register
ff c, fa c, ' xdpr  token,  \ Data Processing Register
ff c, fb c, ' xmul  token,  \ Multiply


here op-table - constant /op-table
base !

: dis1  ( -- )
   push-hex  dis-pc 8 u.r 2 spaces  pop-base
   .instruction
   op-table  /op-table  bounds  do
      op 8 rshift                    ( opcode-bits )
      i c@ and   i ca1+ c@  =  if    ( )
         i 2 ca+ token@ execute  cr  ( )
	 unloop exit                 ( -- )
      then                           ( )
   /token 2 ca+ +loop                ( )
   true abort" Op decode error!"
;

: end-dis?  ( -- flag )  key?  dup  if  key drop  then  ;
: +dis  ( -- )
   begin  end-dis? 0=  while  dis1  repeat	 
;

: dis  ( adr -- )   to dis-pc  +dis  ;
