; Graphics that go in after Castlevania loads a stage's.
;
; Castlevania's loader ($FD23) copies a list of blocks with the screen off,
; then turns it back on with $C102. The hack takes over that last step: it
; copies in Samus's tile pairs that live over the status bar's font, and
; blanks the status bar in both name tables (Metroid's HUD is sprites).
; The Game Over screen writes text with the font, so it gets the font back.

STATUS_DOT = $20A1          ; row 5, column 1: the pixel sprite 0 hits
TILE_BLANK = $FF            ; background tiles in the font area (see below)
TILE_DOT = $FE
FONT_ADDR = $1D00
FONT_SIZE = $0300
CvFont = $BD00              ; a copy of Castlevania's font (bank 3 $BC08), see main.asm

; X = HACK_CHR, jumped to from the loader's end. The loader turned the NMI
; off ($C132); $C102 turns it back on, so it comes last: Castlevania's game
; runs in the NMI, and an NMI in the middle of these writes would turn the
; screen on and move the PPU's address under them.
ChrLoaded:
        ; FarCall puts back the bank it found: make that bank 6, which the
        ; loader would have mapped. On the stack: the return into HackEntry,
        ; the return into FarCall, then that bank.
        tsx
        lda #6
        sta $0105,x
        jsr @load
        jmp $C102
@load:
        lda #$FF                ; the HUD's digit tiles: redraw them
        sta HudShown
        sta HudShown+1
        sta HudShown+2
        lda GameMode            ; the intro, play and the demo
        cmp #2
        beq @samus
        cmp #4
        bcc @noSamus
        cmp #6
        bcc PutSamusChr
@noSamus:
        lda HackState           ; the font is Castlevania's
        and #~HS_FONT
        sta HackState
        rts
@samus:
        jmp PutSamusChr

; After a continue: the Game Over screen put the font back (RestoreFont),
; and a continue doesn't load the stage's graphics again. While the stage
; loads (mode 5, part 1), Castlevania's game turns the screen off for the
; rest of the frame, so Samus's tiles go back in then.
RestoreSamusChr:
        lda HackState
        and #HS_FONT
        bne @rts
        lda GameMode
        cmp #5
        bne @rts
        lda GameModeAux
        cmp #1
        bne @rts
        lda $FF                 ; increment by 1
        and #~$04
        sta $2000
        jmp PutSamusChr
@rts:
        rts

; Samus's tile pairs over the font, the dot sprite 0 hits, and the status
; bar blank. The screen must be off.
PutSamusChr:
        lda #>FontChrAddr
        ldx #<FontChrAddr
        jsr PpuAddr
        lda #<FontChr
        sta Ptr
        lda #>FontChr
        sta Ptr+1
        ldx #>FontChrSize + 1
        ldy #0
@copy:
        cpx #1
        bne @byte
        cpy #<FontChrSize
        beq @copied
@byte:
        lda (Ptr),y
        sta $2007
        iny
        bne @copy
        inc Ptr+1
        dex
        bne @copy
@copied:
        ; $1FE0: the dot (one pixel of colour 3, top left) and a blank tile
        lda #>$1FE0
        ldx #<$1FE0
        jsr PpuAddr
        ldx #0
@dot:
        lda DotTiles,x
        sta $2007
        inx
        cpx #32
        bne @dot
        lda HackState
        ora #HS_FONT
        sta HackState
        ; the status bar, rows 0-5 of both name tables
        lda #$20
        jsr BlankStatus
        lda #$24
        jsr BlankStatus
@rts:
        rts

DotTiles:
        .db $80,0,0,0,0,0,0,0, $80,0,0,0,0,0,0,0
        .dsb 16, 0

; A = name table high byte
BlankStatus:
        ldx #0
        jsr PpuAddr
        ldx #6 * 32
        lda #TILE_BLANK
@loop:
        sta $2007
        dex
        bne @loop
        rts

; PPU address A:X
PpuAddr:
        bit $2002
        sta $2006
        stx $2006
        rts

; The Game Over screen: put the font back while the screen is off.
RestoreFont:
        lda HackState
        and #HS_FONT
        beq @rts
        lda GameMode
        cmp #$0D
        bne @rts
        lda $1F                 ; the screen is off while this counts down
        cmp #2
        bcc @rts
        lda HackState
        and #~HS_FONT
        sta HackState
        lda #>FONT_ADDR
        ldx #<FONT_ADDR
        jsr PpuAddr
        lda #<CvFont
        sta Ptr
        lda #>CvFont
        sta Ptr+1
        ldx #>FONT_SIZE
        ldy #0
@copy:
        lda (Ptr),y
        sta $2007
        iny
        bne @copy
        inc Ptr+1
        dex
        bne @copy
@rts:
        rts
