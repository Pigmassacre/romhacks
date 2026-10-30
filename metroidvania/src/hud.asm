; Metroid's HUD (DisplayHUD): "EN..", the energy, and the missile count with
; the missile beside it, at Metroid's places on the screen.
;
; Castlevania's sprites are 8x16, so each HUD column is one sprite: Metroid's
; energy row on top, its missile row below. That puts the missile row 8
; pixels under the energy row instead of 10, but keeps the HUD to 7 sprites
; on its lines (Metroid's 10 sprites, 8x16, would be more than a line can
; show). E, N and the missile are fixed tiles. The three digit columns are
; redrawn in the pattern table when a number changes, through Castlevania's
; update buffer, one column a frame.
;
; Missiles are Castlevania's hearts.

HUD_Y = $21 - 8             ; Metroid's energy row is at $21; 8 higher, the HUD is
                            ; over the status bar, above the split (see Bank6_Split)
HUD_PAL = $02               ; see SetHudColours

; The HUD's sprites, 9-15. Castlevania's sprite allocator leaves sprites
; 0-16 alone; of those, it draws the moving platforms (stages 4, 5 and 10),
; Dracula's head and the gate's walk-in in 1-8 itself, and its status bar's
; subweapon box and icon in 7-16: the box only when a stage or a floor
; loads ($A17D, its y kept off the screen, see main.asm), the icon not at
; all (main.asm). Loading also clears 5-16 ($CB81).
HUD_OAM = $0224

; Sprite 0, which Castlevania sets again each frame: the dot over the status
; bar's dot pixel, in black (palette 3).
Sprite0:
        lda #(STATUS_DOT & $3E0) / 4 - 1
        sta $0200
        lda #$FF
        sta $0201
        lda #$03
        sta $0202
        lda #(STATUS_DOT & $1F) * 8
        sta $0203
        rts

DrawHud:
        ldx #2                  ; a digit column not drawn since the stage's
@new:                           ; graphics loaded: no HUD until it is
        lda HudShown,x
        cmp #$FF
        beq @hide
        dex
        bpl @new
        lda HUD_OAM             ; loading a stage or a floor clears or covers
        cmp #HUD_Y              ; them: put them back whenever they are gone
        bne @oam
        lda HUD_OAM + 6 * 4
        cmp #HUD_Y + 8
        beq @digitsMaybe
@oam:
        ldx #7 * 4 - 1
@spr:
        lda HudOam,x
        sta HUD_OAM,x
        dex
        bpl @spr
@digitsMaybe:
        ; the digits: worked out every 4th frame
        lda FrameCounter
        and #$03
        beq @digits
        rts
@hide:
        jsr HideHud
@digits:
        ; the digit columns
        jsr HudDigits
        ldx #2
@col:
        lda Temp0,x
        cmp HudShown,x
        bne HudColumn
        dex
        bpl @col
        ; nothing changed: every 8 frames, send one column again anyway, in
        ; case Castlevania dropped the buffer (it does while a stage starts)
        lda FrameCounter
        and #$07
        bne @rts
        lda FrameCounter
        lsr
        lsr
        lsr
@mod3:
        cmp #3
        bcc @refresh
        sbc #3
        bcs @mod3
@refresh:
        tax
        lda Temp0,x
        jmp HudColumn
@rts:
        rts

; Temp0-Temp2: the three digit columns, each two glyphs: top in the high
; nibble, bottom in the low one (0-9 digits, $A ".." , $B blank).
HudDigits:
        lda Hearts
        ldx #0
@hundreds:
        cmp #100
        bcc @tens0
        sbc #100
        inx
        bne @hundreds
@tens0:
        ldy #0
@tens:
        cmp #10
        bcc @ones
        sbc #10
        iny
        bne @tens
@ones:
        sta Temp2
        stx Temp0
        sty Temp1
        lda Temp0
        ora #$A0                ; ".." over the hundreds
        sta Temp0
        lda HealthHi
        and #$0F
        asl
        asl
        asl
        asl
        ora Temp1
        sta Temp1
        lda HealthLo
        and #$F0
        ora Temp2
        sta Temp2
        rts

; X = column 0-2, A = what it shows: queue its 32 bytes.
HudColumn:
        ldy $20                 ; the update buffer's end
        pha
        tya
        clc
        adc #36
        bcs @full
        cmp #$C0
        bcs @full               ; no room this frame: next frame
        pla
        sta HudShown,x
        lda #1
        sta $0700,y
        lda #0
        sta $0701,y
        lda HudTileLo,x
        sta $0702,y
        lda HudShown,x
        lsr
        lsr
        lsr
        lsr
        jsr @glyph
        lda HudShown,x
        and #$0F
        jsr @glyph
        lda #$FF
        sta $0703,y
        lda #0
        sta $0704,y             ; end of the buffer
        iny
        iny
        iny
        iny
        sty $20
        rts
@full:
        pla
        rts
; A = glyph: its 16 bytes at $0703,y on
@glyph:
        stx Temp3
        asl
        asl
        asl
        asl
        tax
        lda #16
        sta DrawCount
@byte:
        lda GlyphTable,x
        sta $0703,y
        inx
        iny
        dec DrawCount
        bne @byte
        ldx Temp3
        rts

; The HUD's sprites off the screen.
HideHud:
        lda #$F8
        ldx #6 * 4
@hide:
        sta HUD_OAM,x
        dex
        dex
        dex
        dex
        bpl @hide
        rts

; The digit columns' tile addresses (pattern table 0)
HudTileLo:
        .db <(HudTile4 * 16), <(HudTile5 * 16), <(HudTile6 * 16)

HudOam:
        .db HUD_Y, HudTile0, HUD_PAL, $18             ; E
        .db HUD_Y, HudTile1, HUD_PAL, $20             ; N
        .db HUD_Y, HudTile4, HUD_PAL, $28             ; ..  / hundreds
        .db HUD_Y, HudTile5, HUD_PAL, $30             ; tens
        .db HUD_Y, HudTile6, HUD_PAL, $38             ; ones
        .db HUD_Y + 8, HudTile2, $00, $18             ; the missile, in Samus's colours
        .db HUD_Y + 8, HudTile3, $00, $20
