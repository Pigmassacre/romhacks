; Gimmick! 1.5
;
; tools/build.py assembles this file with asm6. Each `;@ seg <bank> <start> <end>`
; line starts a segment: the code after it is assembled at <start> and written
; into that 8 KB bank of the expanded ROM. It must end before <end>.
;
; Bank $3F is the fixed bank at $E000 (the original bank $1F, moved).
; Bank $20 is new and holds most of the hack. It is mapped at $A000 by FarCall
; for as long as a hack routine runs.

.include "defs.asm"

; =============================================================================
;@ seg $3F $E271 $E2D5 fixed: far calls
; =============================================================================
; The original game skips this block with `lda #0 / beq` at $E26D: it is the
; developers' cheats (Select refills health, controller 2 A+B adds a life),
; disabled for release. Nothing else jumps into it.
;
; Each entry point loads Y with a routine number and falls into FarCall.
; $2C is BIT abs, which swallows the next two-byte `ldy`.

Far_StarButton:
        ldy #0
        .db $2C
Far_Jump:
        ldy #2
        .db $2C
Far_FxDraw:
        ldy #4
        .db $2C
Far_Water:
        ldy #6
        .db $2C
Far_BHeld:
        ldy #8
        .db $2C
Far_TitleNotice:
        ldy #10

; Map the hack bank at $A000, call routine Y, and put back what was there.
; X is kept. The routine's carry is returned; A and Y are not.
FarCall:
        lda BankA000
        pha
        txa
        pha
        lda #$0A
        sta MapperCmd           ; NMI and IRQ restore the command from here
        sta $8000
        lda #HACK_BANK
        sta BankA000            ; NMI restores the bank from here
        sta $A000
        jsr HackEntry
        pla
        tax
        pla
        tay
        lda #$0A
        sta MapperCmd
        sta $8000
        sty BankA000
        sty $A000
        rts

; =============================================================================
;@ seg $1E $8199 $81A0 player: jump test
; =============================================================================
; Was: lda $F5 / and $036E / beq $81AB  (jump if A is new and he is on the floor)

        jsr Far_Jump
        bcc $81AB
        nop
        nop

; =============================================================================
;@ seg $1E $81C3 $81D1 player: star button
; =============================================================================
; Was: skip the charge code while the star is thrown (1), in a tube (2) or
; vanishing ($D0+).

        jsr Far_StarButton
        bcc $81D1               ; go on to the charge code
        jmp $81F8               ; skip it

; =============================================================================
;@ seg $1E $81DA $81E0 player: is B held?
; =============================================================================
; Was: lda $F7 / and #$40 / beq $81FB (let go of the star when B is up).
; BHeld answers for tap mode too.

        jsr Far_BHeld
        bcc $81FB
        nop

; =============================================================================
;@ seg $1D $8469 $846E star: draw
; =============================================================================
; Was: lda $9B / sta $0424 (start of the star's draw routine). FxDraw draws
; the effects and then does those two instructions.

        jsr Far_FxDraw
        nop
        nop

; =============================================================================
;@ seg $1D $8151 $8156 star: before its physics
; =============================================================================
; Was: lda $C3 / sta $0397 (save vy before moving). WaterSkip bounces the star
; off water and then does those two instructions.

        jsr Far_Water
        nop
        nop

; =============================================================================
;@ seg $1B $8082 $8086 title: after its nametables
; =============================================================================
; Was: lda #3 / sta $4A. TitleNotice draws the notice above the panel and then
; does those two instructions.

        jsr Far_TitleNotice
        nop

; =============================================================================
;@ seg $20 $A000 $BF00 hack bank
; =============================================================================

HackEntry:
        lda HackTable+1,y
        pha
        lda HackTable,y
        pha
        rts

HackTable:
        .dw StarButton-1
        .dw JumpCheck-1
        .dw FxDraw-1
        .dw WaterSkip-1
        .dw BHeld-1
        .dw TitleNotice-1

; The rendering is off here, as for the copies this follows. Writing with Y
; going up from 0 draws two whole rows; tools/title.py fills in NoticeRows.
TitleNotice:
        bit $2002
        lda #>NOTICE_PPU
        sta $2006
        lda #<NOTICE_PPU
        sta $2006
        ldy #0
@row:
        lda NoticeRows,y
        sta $2007
        iny
        cpy #64
        bne @row
        lda #3
        sta $4A
        rts

.include "recall.asm"
.include "fx.asm"
.include "water.asm"
.include "jump.asm"
.include "tap.asm"
