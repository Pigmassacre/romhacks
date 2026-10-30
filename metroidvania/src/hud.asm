; Metroid's HUD (DisplayHUD): "EN..", the energy, and the missile count with
; the missile beside it, at Metroid's places on the screen. Above them, in
; the same columns, what Castlevania's status bar told: the time, under
; Metroid's own label for its escape timer ("TIME", which Metroid shows in
; the missile row), and while the screen is locked for a boss, its health,
; beside the tank Metroid marks energy with:
;
;                  tank 6  4
;           TI ME  3    0  0
;           E  N   ..   9  9
;           missile 0   0  5
;
; Castlevania's sprites are 8x16, so each digit column is two sprites, each
; holding two rows: boss over time, energy over missiles. TI and ME share
; their sprites with E and N. That puts the HUD's rows 8 pixels apart instead
; of 10, but keeps it to 8 sprites on a line at most (a line can't show
; more). The labels and the missile are fixed tiles. The six digit tiles are
; redrawn in the pattern table when a number changes, through Castlevania's
; update buffer, one a frame.
;
; Missiles are Castlevania's hearts.

HUD_Y = $21 - 8             ; Metroid's energy row is at $21; 8 higher, the HUD is
                            ; over the status bar, above the split (see Bank6_Split)
HUD_PAL = $02               ; see SetHudColours
GLYPH_BLANK = $0B           ; in GlyphTable, after the digits and ".."
GLYPH_TANK = $0C

; The HUD's sprites, 7-16. Castlevania's sprite allocator leaves sprites
; 0-16 alone; of those, it draws the moving platforms (stages 4, 5 and 10),
; Dracula's head and the gate's walk-in in 1-6 itself (and 7-8 too, with
; three more such objects about, then the HUD comes first), and its status
; bar's subweapon box and icon in 7-16: the box only when a stage or a floor
; loads ($A17D, its y kept off the screen, see main.asm), the icon not at
; all (main.asm). Loading also clears 5-16 ($CB81).
HUD_OAM = $021C
HUD_SPRITES = 10

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
        ldx #5                  ; a digit column not drawn since the stage's
@new:                           ; graphics loaded: no HUD until it is
        lda HudShown,x
        cmp #$FF
        beq @hide
        dex
        bpl @new
        lda HUD_OAM             ; loading a stage or a floor clears or covers
        cmp #HUD_Y - 8          ; them: put them back whenever they are gone
        bne @oam
        lda HUD_OAM + (HUD_SPRITES - 1) * 4
        cmp #HUD_Y - 16
        beq @digitsMaybe
@oam:
        ldx #HUD_SPRITES * 4 - 1
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
        ldx #5
@col:
        lda HudNew,x
        cmp HudShown,x
        beq @same
        jmp HudColumn
@same:
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
@mod6:
        cmp #6
        bcc @refresh
        sbc #6
        bcs @mod6
@refresh:
        tax
        lda HudNew,x
        jmp HudColumn
@rts:
        rts

; HudNew: the six digit columns, each two glyphs: top in the high nibble,
; bottom in the low one (0-9 digits, $A ".." , $B blank, $C the tank). First
; ".." and energy over missiles, then the boss over the time.
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
        sta HudNew+2
        sty HudNew+1
        txa
        ora #$A0                ; ".." over the hundreds
        sta HudNew
        lda HealthHi
        and #$0F
        asl
        asl
        asl
        asl
        ora HudNew+1
        sta HudNew+1
        lda HealthLo
        and #$F0
        ora HudNew+2
        sta HudNew+2
        ; the time, which is in BCD: $43 hundreds, $42 tens and ones
        lda TimeHi
        and #$0F
        sta HudNew+3
        lda TimeLo
        lsr
        lsr
        lsr
        lsr
        sta HudNew+4
        lda TimeLo
        and #$0F
        sta HudNew+5
        ; the boss, while the screen is locked for it
        lda BossLock
        bne @boss
        lda #GLYPH_BLANK << 4
        tax
        tay
        bne @top
@boss:
        lda BossHP
        ldx #0
@bossTens:
        cmp #10
        bcc @bossOnes
        sbc #10
        inx
        bne @bossTens
@bossOnes:
        asl
        asl
        asl
        asl
        tay                     ; ones
        txa
        asl
        asl
        asl
        asl
        tax                     ; tens
        lda #GLYPH_TANK << 4
@top:
        ora HudNew+3
        sta HudNew+3
        txa
        ora HudNew+4
        sta HudNew+4
        tya
        ora HudNew+5
        sta HudNew+5
        rts

; X = column 0-5, A = what it shows: queue its 32 bytes.
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
        lda HudTileHi,x
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
        ldx #(HUD_SPRITES - 1) * 4
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
        .db <(HudTile7 * 16), <(HudTile8 * 16), <(HudTile9 * 16)
HudTileHi:
        .db >(HudTile4 * 16), >(HudTile5 * 16), >(HudTile6 * 16)
        .db >(HudTile7 * 16), >(HudTile8 * 16), >(HudTile9 * 16)

HudOam:
        .db HUD_Y - 8, HudTile0, HUD_PAL, $18         ; TI over E
        .db HUD_Y - 8, HudTile1, HUD_PAL, $20         ; ME over N
        .db HUD_Y, HudTile4, HUD_PAL, $28             ; ..  / hundreds
        .db HUD_Y, HudTile5, HUD_PAL, $30             ; tens
        .db HUD_Y, HudTile6, HUD_PAL, $38             ; ones
        .db HUD_Y + 8, HudTile2, $00, $18             ; the missile, in Samus's colours
        .db HUD_Y + 8, HudTile3, $00, $20
        .db HUD_Y - 16, HudTile7, HUD_PAL, $28        ; the boss / the time
        .db HUD_Y - 16, HudTile8, HUD_PAL, $30
        .db HUD_Y - 16, HudTile9, HUD_PAL, $38
