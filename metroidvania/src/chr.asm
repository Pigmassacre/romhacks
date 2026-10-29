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

; X = HACK_CHR, jumped to from the loader's end.
ChrLoaded:
        ; FarCall puts back the bank it found: make that bank 6, which the
        ; loader would have mapped. On the stack: the return into HackEntry,
        ; the return into FarCall, then that bank.
        tsx
        lda #6
        sta $0105,x
        jsr $C102
        lda #$FF                ; the HUD's digit tiles: redraw them
        sta HudShown
        sta HudShown+1
        sta HudShown+2
        lda GameMode
        cmp #4
        bcc @rts
        cmp #6
        bcs @rts
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
