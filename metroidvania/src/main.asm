; Metroidvania
;
; tools/build.py assembles this file with asm6. Each `;@ seg <bank> <start> <end>`
; line starts a segment: the code after it is assembled at <start> and written
; into that 16 KB bank of the expanded ROM. It must end before <end>.
;
; Bank $0F is the fixed bank at $C000 (the original bank 7, moved). Bank $08 is
; new and holds the hack; FarCall maps it at $8000 while a hack routine runs.

.include "defs.asm"

; =============================================================================
;@ seg $0F $FF2A $FF40 fixed: far call
; =============================================================================
; Padding before the vectors. X = routine number * 2 (see HackEntry).
; CurrentBank is set to $08 while the hack runs, so that an NMI that lands in
; it (its sound code switches banks) maps the hack back afterwards.

FarCall:
        lda CurrentBank
        pha
        lda #$08
        sta CurrentBank
        sta HackBankByte        ; holds $08, so there is no bus conflict
        jsr HackEntry
        pla
        tay
        jmp SwitchBankY         ; keeps A and the carry

;@ seg $0F $FFF0 $FFF9 fixed: bank byte, reset
HackBankByte:
        .db $08

; Castlevania's reset calls this instead of InitializeZeroPage.
ResetHook:
        jsr $C19B               ; InitializeZeroPage
        ldx #HACK_RESET
        jmp FarCall

;@ seg $0F $C020 $C023 reset: zero page
        jsr ResetHook

; =============================================================================
;@ seg $06 $9366 $9369 Simon's handler dispatch
; =============================================================================
        jmp Bank6_Simon

;@ seg $0F $C13B $C13F sprite 0: over the dot (see chr.asm), in black (palette 3)
; Bank6_Split and Castlevania's split both write this to sprite RAM. A late
; frame's NMI can land after this frame's sprites, so it is what the next
; frame's sprite 0 is.
        .db (STATUS_DOT & $3E0) / 4 - 1, $FF, $03, (STATUS_DOT & $1F) * 8

;@ seg $0F $C08A $C08D NMI: status bar split
        jsr Bank6_Split

;@ seg $06 $BA3C $C000 bank 6: hooks
; (from $BA3C: the $FF at $BA3B ends the title bat's path, $BA17)
; Castlevania's breakable blocks break when the whip hits them, at frame 9
; of Simon's attack (StrangeCode13, $A825). The whip reaches $18 ahead of
; Simon, so a shot is put there, Simon $18 behind it facing right, and the
; rest of that check ($A837) run for it. Blocks are solid, so only shots
; that just exploded on a wall are checked.
Bank6_ShotsBreakBlocks:
        ldx #2
@shot:
        lda BulDie,x
        cmp #SHOT_HIT_WALL
        bne @next
        lda #0
        sta BulDie,x
        txa
        pha
        lda SimonXLo
        pha
        lda SimonXHi
        pha
        lda SimonY
        pha
        lda ObjFacing
        pha
        lda WhipLevel
        pha
        lda #0
        sta WhipLevel
        sta ObjFacing
        tsx                     ; X: the shot, 6 bytes up the stack
        lda $0106,x
        tax
        lda BulXLo,x
        sec
        sbc #$18
        sta SimonXLo
        lda BulXHi,x
        sbc #0
        sta SimonXHi
        lda BulY,x
        sta SimonY
        jsr $A837
        pla
        sta WhipLevel
        pla
        sta ObjFacing
        pla
        sta SimonY
        pla
        sta SimonXHi
        pla
        sta SimonXLo
        pla
        tax
@next:
        dex
        bpl @shot
        rts

; The status bar split. Metroid's HUD needs its own colours: sprite palette 2
; holds them from the top of the screen (Bank0_BgGfx sets them in vblank),
; and gets Castlevania's back right after the split, on the status bar's
; last, blank lines. Changing the palette needs the screen off for a moment,
; and the PPU's address then has to be set back to where the picture is.
SPLIT_LINE = 45             ; the first line drawn again: the screen comes back on
                            ; at the end of line 44, in its horizontal blank, so the
                            ; PPU fetches line 45 whole (measured in Mesen)
SPLIT_WAIT2 = 10            ; (also measured)
SPLIT_WAIT = 21             ; to the end of line 43 (also measured)
Bank6_Split:
        bit HackState           ; HS_SPLIT: set in vblank, with the HUD's colours
        bvs @split
        jmp $F87D               ; Castlevania's split
@split:
        ; Castlevania's split for play (mode 5, part 6; $F8B6 on), but
        ; watching for sprite 0 more closely: its loop looks every 17 cycles,
        ; too loosely for the palette writes to stay in a horizontal blank.
        jsr $C13F               ; sprite 0
        jsr $F868               ; ResetScrolling
        lda $1B
        bne @noTimer
        jsr $A08A
@noTimer:
        ldx #0                  ; both waits give up, as Castlevania's do
@clear:
        inx
        beq @cleared
        bit $2002
        bvs @clear
@cleared:
        ldx #0
        ldy #3                  ; 768 tries of 11 cycles: past line 40, even from
                                ; the top of a vertical blank (after a black frame,
                                ; no hit is left to wait out)
@hit:
        bit $2002
        bvs @hitNow
        dex
        bne @hit
        dey
        bne @hit
@hitNow:
        ldy #$2C                ; Castlevania's 221 cycles
@delay:
        dey
        bne @delay
        lda $2002
        lda ScrollLo
        sta $2005
        lda #0
        sta $2005
        jsr $F909
        lda $FF
        and #$FE
        adc #0
        sta $FF
        sta $2000
        ; While the screen is off the PPU shows the colour its address points
        ; at, so the palette writes are quick, at the end of a line, with
        ; everything loaded first.
        ldy #SPLIT_WAIT         ; on to the end of line 43
@wait:
        dey
        bne @wait
        nop
        nop
        ldx #$11                ; Castlevania's palette 2: $37, $11, $0F
        ldy #$0F
        lda #0
        sta $2001               ; off
        lda #$3F
        sta $2006
        lda #$19
        sta $2006               ; from here on the PPU shows these colours...
        lda #$37
        sta $2007
        stx $2007
        sty $2007               ; ...until here ($3F1C is black): all in the
                                ; horizontal blank
        lda #0
        sta $2006
        sta $2006
        ; v = the picture at SPLIT_LINE, scrolled as Castlevania just set
        lda $FF
        and #$01
        asl
        asl
        ora #((SPLIT_LINE & 7) << 4) | (SPLIT_LINE >> 6)
        sta $2006
        lda #SPLIT_LINE
        sta $2005
        lda ScrollLo
        sta $2005
        lsr
        lsr
        lsr
        ora #<((SPLIT_LINE & $F8) << 2)
        sta $2006
        ldy #SPLIT_WAIT2        ; on to the end of line 44
@wait2:
        dey
        bne @wait2
        lda $FE
        sta $2001
        rts

; A late frame: the game hasn't finished the last one, so the update buffer
; isn't flushed, and with it the HUD's colours don't go in. The split put
; Castlevania's back last frame: without this, the HUD flashes in them
; whenever the game runs late.
Bank6_LateFrame:
        lda $FE                 ; as Castlevania's late frame ($C0C0)
        ldx $1F
        beq @mask
        lda #0
@mask:
        sta $2001
        bit HackState
        bvc @split
        lda $2002
        lda #$3F
        sta $2006
        lda #$19
        sta $2006
        lda #$12                ; Metroid's HUD colours (see HudColours, bank 0)
        sta $2007
        lda #$30
        sta $2007
        lda #$21
        sta $2007
@split:
        jsr Bank6_Split
        jsr $C11F               ; UpdateScreenScrolling
        ; Back to the bank it landed in. That's $27's, unless it landed in the
        ; sound effect routine ($C1A7), which maps bank 0 without noting it.
        lda $7F
        beq @noted
        ldy #0
        jmp $C1D8
@noted:
        jmp $C1CF               ; SwitchBank_Restore

; The rosary's flash writes a whole palette every other frame. With the
; screen scrolling, that backs up the update buffer (see Bank0_BgGfx): no flash
; this time if there is plenty to write already.
Bank6_Flash:
        lda $20
        cmp #BUFFER_BUSY
        bcs @rts
        jmp $FA8E
@rts:
        rts

; Simon's actions: 0 walk, 1 jump, 2 whip, 3 crouch, 4 stairs, 5 hurt,
; 6 to the stairs, 7 fall, 8 dead, 9 land. Stairs and dying stay
; Castlevania's, with Samus following Simon; the rest are Samus's.
Bank6_Simon:
        lda ObjAction
        cmp #4
        beq @cv
        cmp #6
        beq @cv
        cmp #8
        bne @samus
@cv:
        ldx #HACK_CV
        jsr FarCall
        bcc @cvMoves
        jmp $A1E5               ; KillSimon: hit on the stairs, out of energy
@cvMoves:
        lda ObjAction
        jsr $9369               ; Castlevania's dispatch
        ldx #HACK_STAIRCAM
        jmp FarCall
@samus:
        ; stairs: up or down pressed on the ground, where Simon could climb.
        ; Only a new press: Samus aims up with it held, and that shouldn't
        ; take her up every stair she walks past.
        lda HackState
        and #HS_GROUND
        beq @noStairs
        lda PadPressed
        and #BTN_UP | BTN_DOWN
        beq @noStairs
        lda PadHeld
        sta ObjBonus            ; Simon's handlers keep the buttons there
        ; Castlevania takes Simon to be at the middle of the screen ($80)
        ; unless MoveDir bit 2 says he moves on the screen; Samus's camera
        ; leaves her anywhere between $71 and $8F.
        lda ObjX
        cmp #$80
        beq @mid
        lda #$04
        sta MoveDir
@mid:
        lda #0
        jsr $9C10
        bcc @noStairs
        lda #$10
        sta ObjLastHit
        lda #0
        sta $054C
        rts
@noStairs:
        ldx #HACK_SAMUS
        jsr FarCall
        jsr Bank6_ShotsBreakBlocks
        lda HackState
        and #HS_KILL
        beq @alive
        jmp $A1E5               ; KillSimon
@alive:
        jsr $9A1D               ; out of time: KillSimon, as Simon's handlers check
        bcs @rts
        jsr Bank6_AtExit
        bcc @rts
        jmp $9397               ; as Simon's walking handler does
@rts:
        rts

; At a stage's exit? Castlevania's window ($9F7A) is 4 pixels back from the
; exit and 3 on, and where a wall is behind the exit (stages 7, 8 and 13) Samus
; stops at 4 on: jumping up to the door, she would land against the wall
; beside it, and stand there. So 2 pixels more, towards the wall.
;
; The window is on the screen, not in the level: Simon only gets that far over
; with the screen at the stage's end. Samus gets there sooner, off the stairs
; with the screen behind her (see Bank6_Simon), and the door would open in the
; middle of the screen. So not until the screen is there (RecentreCamera).
Bank6_AtExit:
        jsr Bank6_ScreenAtExit
        bne @no
        jsr $9F7A
        bcs @rts
        ; Stage 10's exit is on the last of three staggered blocks. Simon's head
        ; meets nothing and he jumps up them; each overhangs the one below by
        ; too little for Samus, so the block before it counts too, at its end.
        lda CurrentStage
        cmp #10
        bne @window
        lda ScrollHi
        cmp #5
        bne @window
        lda SimonY
        sec
        sbc #$7C
        cmp #8
        bcs @window
        lda ObjX
        cmp #$D8
        bcc @window
        pha
        lda SimonY
        pha
        lda #$40
        sta SimonY
        lda #$D0
        sta ObjX
        jsr $9F7A
        pla
        sta SimonY
        pla
        sta ObjX
        rts
@window:
        lda ObjX
        pha
        cmp #$80
        bcs @right
        adc #2
        bcc @try                ; (always)
@right:
        sbc #2
@try:
        sta ObjX
        jsr $9F7A
        pla                     ; keeps the carry
        sta ObjX
@rts:
        rts
@no:
        clc
        rts

; Equal if the screen is as far as it goes towards this stage's exit, or locked
; for a boss. The limits are the ones ScrollRight1 and ScrollLeft1 stop at.
Bank6_ScreenAtExit:
        lda BossLock
        beq @free
        lda #0
        rts
@free:
        lda ScrollLo
        bne @rts
        lda CurrentStage
        asl
        tax
        lda $FC13,x             ; the exit's x: in the right half, it's to the right
        bmi @right
        jsr $D025
        clc
        adc #1
        cmp ScrollHi
        rts
@right:
        jsr $D015
        cmp ScrollHi
@rts:
        rts

; =============================================================================
;@ seg $00 $8063 $8067 UpdateSprites: before the object loop
; =============================================================================
        jsr Bank0_Sprites
        nop

;@ seg $00 $800A $800D UpdateBackgroundGFX
        jmp Bank0_BgGfx

;@ seg $0F $FD77 $FD7E CHR loader: end
        ldx #HACK_CHR
        jmp FarCall

;@ seg $06 $9002 $9010 the credits: and the hero, Samus Aran (each letter a pair of tiles)
        .db $54,$54,$84,$60,$78,$88,$84,$54,$60,$82,$60,$7A,$54,$54

;@ seg $06 $A091 $A094 the status bar: no score
; (Written every other frame, as blank tiles. With the time's, they were a
; quarter of what fits in the vertical blank: see the notes on the split.)
        nop
        nop
        nop
;@ seg $06 $A0CD $A0D0 the status bar: no time and no health bar (the HUD has them)
        jmp $A110
;@ seg $06 $A237 $A23A the status bar: no boss's health bar (nor does it count, as ever)
        nop
        nop
        nop
;@ seg $06 $A2E8 $A2E9 the status bar: no double or triple shot icon
        rts

;@ seg $06 $A113 $A114 the status bar: no subweapon icon (sprites 7-16 are the HUD's)
        rts

;@ seg $06 $A1B0 $A1D0 the status bar: the subweapon box's sprites, off the screen
        .db $F8,$FB,$03,$80, $F8,$FD,$03,$88, $F8,$FD,$03,$90, $F8,$FB,$43,$98
        .db $F8,$9D,$03,$80, $F8,$FD,$03,$88, $F8,$FD,$03,$90, $F8,$9D,$43,$98

;@ seg $0F $E734 $E737 Simon touches an enemy: no "ugh" (Samus has her own)
        nop
        nop
        nop

;@ seg $0F $FA77 $FA7A the rosary's flash
        jsr Bank6_Flash

;@ seg $0F $C1C2 $C1CD the sound effect routine: its end
; Done with bank 0: "in the sound code" ends first, so that $7F set always means
; bank 0, for a late frame to go back to (Bank6_LateFrame).
        lda #$00
        sta $7F
        jsr $C1CF
        ldy $07F5
        rts

;@ seg $0F $C0C0 $C0CE NMI: a late frame
; (Replaces PPUMASK, the status bar split and the scroll, in Bank6_LateFrame,
; and leaves the sound as it was. A late NMI can land in any bank.)
        ldy #6
        jsr $C1D8               ; SwitchBank, not remembered: the bank goes back after
        jsr Bank6_LateFrame
        jsr $C0D7
        jmp $C0B9

;@ seg $0F $C097 $C09A NMI: music
        jsr Bank0_Music
;@ seg $0F $C0E4 $C0E7 NMI (a late frame): music
        jsr Bank0_Music

;@ seg $00 $83B5 $83B9 music: each channel
        jsr Bank0_SfxChan
        nop
;@ seg $00 $83C9 $83D1 music: the next channel's registers
        ; from the channel's base ($80 square 1 ... $D0 its sound effect
        ; square 2), not from $AC, which Bank0_SfxChan may have moved
        txa
        lsr
        lsr
        and #$0C
        tay
        clc
        nop

;@ seg $00 $BB01 $C000 bank 0: hooks
; Castlevania's music, then Samus's sound effects. A late frame's NMI can
; land in the middle of the hack; then the effects wait a frame.
Bank0_Music:
        jsr $838A               ; UpdateMusic
        lda HackDepth
        bne @rts
        lda SfxPtrHi            ; nothing playing: nothing to do
        ora SfxPtrHi+1
        ora SfxPtrHi+2
        ora SfxPtrHi+3
        beq @rts
        lda CurrentBank         ; FarCall maps this back: make it this bank
        pha
        lda #0
        sta CurrentBank
        ldx #HACK_SFX
        jsr FarCall
        pla
        sta CurrentBank
@rts:
        rts

; Castlevania's music channel X ($80 square 1, $90 square 2, $A0 triangle,
; $B0 noise, $C0/$D0 its sound effects on the squares) is about to write
; its registers, at $4000 + $AC. While one of Samus's effects has the
; channel, they go to $4018, where nothing listens.
Bank0_SfxChan:
        sty $AC                 ; replaced code
        cpx #$B0
        beq @noise
        cpx #$A0
        beq @tri
        cpx #$90
        beq @sq2
        cpx #$D0
        beq @sq2
        lda SfxPtrHi + SFX_SQ1  ; $80, $C0: square 1
        bne @mute
@sq2:
        lda SfxPtrHi + SFX_MULTI
        bne @mute
        beq @done
@tri:
        lda SfxPtrHi + SFX_TRI
        bne @mute
        beq @done
@noise:
        lda SfxPtrHi + SFX_NOISE
        beq @done
@mute:
        lda #$18
        sta $AC
@done:
        lda $02,x               ; replaced code
        rts

; Draw Samus first, then let the object loop start at slot 1: slot 0 (Simon)
; is drawn by the hack, unless it is something else (DrawAll).
; Castlevania's update buffer, flushed at the start of each NMI, with the
; status bar (rows 0-5 of both name tables) kept blank outside the title:
; anything written there is written as blank tiles. Then the dot that
; sprite 0 hits, and Samus's colours in sprite palette 0.
Bank0_BgGfx:
        lda $20                 ; how long the buffer is (see Bank0_Colours)
        cmp #BUFFER_LONG
        bcc @flush
        jsr Bank0_Colours
@flush:
        ; With the screen on for the split, only what fits in the vertical blank.
        ; Past it the PPU's address isn't set for the picture, sprite 0's dot
        ; isn't under it, the split gives up lines late, and the picture jumps.
        lda BufStart
        cmp $20
        bcc @start
        lda #0
@start:
        sta BufStart
        tay
        ldx #$FF
        bit HackState           ; HS_SPLIT: from last frame, before Bank0_Colours
        bvc @end
        lda $20                 ; not if it's getting full: the hack's RAM is above it
        cmp #BUFFER_FULL
        bcs @end
        tya
        clc
        adc #BUFFER_FITS
        tax
@end:
        stx BufEnd
@entry:
        ldx $0700,y
        bne @more
        jmp @done
@more:
        cpy BufEnd
        bcs @stop
        lda BufEnd              ; (no limit)
        cmp #$FF
        beq @put1
        lda $0701,y             ; tiles are a long entry: near the start
        cmp #$20
        bcs @put1
        tya
        sec
        sbc BufStart
        cmp #BUFFER_TILES
        bcc @put1
@stop:
        jmp @later
@put1:
        lda $FF
        and #$18
        ora $8007,x             ; the increment for this entry
        sta $2000
        iny
        lda $2002
        lda $0700,y
        sta $2006
        and #$FB
        cmp #$20
        bne @addr
        lda $0701,y
        cmp #$C0
        bcs @addr
        lda GameMode
        cmp #$0E                ; not down the shaft into stage 10, nor in the
        bcs @addr               ; ending: no status bar there
        cmp #4
        bcs @blank
        cmp #2                  ; the attract demo, played by Samus
        beq @blank
@addr:
        iny
        lda $0700,y
        sta $2006
        iny
@data:                          ; as Castlevania's
        lda $0700,y
        iny
        cmp #$FF
        beq @ff
@put:
        sta $2007
        jmp @data
@ff:
        lda $0700,y
        cmp #$03
        bcs @ffput
        jmp @entry
@ffput:
        lda #$FF                ; $FF and a byte of 3 or more: a $FF, then that byte
        bne @put
@blank:                         ; the status bar: blank tiles, the same count
        iny
        lda $0700,y
        sta $2006
        iny
        ldx #TILE_BLANK
@bdata:
        lda $0700,y
        iny
        cmp #$FF
        beq @bff
@bput:
        stx $2007
        jmp @bdata
@bff:
        lda $0700,y
        cmp #$03
        bcs @bput
        jmp @entry
@later:
        sty BufStart            ; the rest next frame: Castlevania adds to it,
        dec $20                 ; over the 0 that ended it ($CCEE)
        jsr Bank0_Colours
        lda $FF
        sta $2000
        rts
@done:
        lda #$00
        sta $0700
        sta BufStart
        lda $20
        cmp #BUFFER_LONG
        bcs @ctrl
        jsr Bank0_Colours
@ctrl:
        lda #$00
        sta $20
        lda $FF
        sta $2000
        rts

; The dot sprite 0 hits, Samus's colours in sprite palette 0, and the HUD's
; in palette 2 if Bank6_Split will put Castlevania's back: every frame, as
; the split does that every frame. After Castlevania's buffer, which may
; write palettes; but a long one (a stage loading writes $CF bytes, a column
; of a stage $9D) runs past the vertical blank, and with the screen off the
; PPU shows the colour its address points at: palette writes there would
; show as a line. So before a long one, which holds no palettes.
BUFFER_LONG = $80
BUFFER_FULL = $A0           ; the hack's RAM is at $CF, and a busy frame adds up to $29
BUFFER_TILES = $14
BUFFER_BUSY = $20           ; the rosary's flash and the HUD's digits wait
BUFFER_FITS = $28           ; with an entry after it (measured: $46 in all is too much)
Bank0_Colours:
        lda HackState
        and #~HS_SPLIT
        sta HackState
        lda GameMode            ; in play and the demo, not on the title or in
        cmp #2                  ; the ending (where slot 0 is the castle, in
        beq @samus              ; sprite palette 0)
        cmp #4
        bcc @none
        cmp #$0F
        bcs @none
@samus:
        lda $FE
        and #$18
        bne @colours
@none:
        rts
@colours:
        lda $FF                 ; increment by 1 (the buffer's last entry may
        and #$18                ; have been by 32)
        sta $2000
        lda $2002
        lda GameMode            ; (the shaft has no status bar)
        cmp #$0E
        beq @noDot
        lda #>STATUS_DOT
        sta $2006
        lda #<STATUS_DOT
        sta $2006
        lda #TILE_DOT
        sta $2007
@noDot:
        lda #$3F
        sta $2006
        lda #$11
        sta $2006
        lda SamusColours
        sta $2007
        ldx MissileToggle       ; Metroid's Palette01 or, with missiles, Palette03
        lda SamusColour2,x
        sta $2007
        lda SamusColours+2
        sta $2007
        ; the HUD's colours, if Bank6_Split will put Castlevania's back
        lda GameMode            ; where Castlevania splits for the status bar
        cmp #2                  ; (and so does Bank6_Split): the demo,
        bne @notDemo
        lda GameModeAux
        cmp #1
        beq @inPlay
        bne @rts
@notDemo:
        cmp #5                  ; play,
        bne @notPlay
        lda GameModeAux
        cmp #6
        beq @inPlay
        bne @rts
@notPlay:
        cmp #8                  ; doors, walking in, climbing to the next stage,
        bcc @rts
        cmp #$0C
        bcc @inPlay
        bne @rts
        lda GameModeAux         ; and a stage's end, up to part 8
        cmp #8
        bcs @rts
@inPlay:
        lda $1F
        bne @rts
        lda HackState
        ora #HS_SPLIT
        sta HackState
        lda #$3F
        sta $2006
        lda #$19
        sta $2006
        ldx #0
@hud:
        lda HudColours,x
        sta $2007
        inx
        cpx #3
        bne @hud
@rts:
        rts

; Metroid's Samus (its sprite palette 0), and its HUD (palette 1, here 2)
SamusColours:
        .db $16, $19, $27
SamusColour2:
        .db $19, $2C
HudColours:
        .db $12, $30, $21

Bank0_Sprites:
        sta $78                 ; replaced code: the sprite cycling offset
        sta $04
        ldx #HACK_DRAW
        jsr FarCall
        lda #0                  ; slot 0 drawn by the hack (carry): start at 1
        rol
        sta $05
        rts

; =============================================================================
;@ seg $08 $8000 $C000 hack bank
; =============================================================================

HackEntry:
        inc HackDepth
        jsr @go
        dec HackDepth           ; keeps the carry
        rts
@go:
        lda HackTable+1,x
        pha
        lda HackTable,x
        pha
        rts

HACK_DRAW = 0
HACK_SAMUS = 2
HACK_CV = 4
HACK_RESET = 6
HACK_CHR = 8
HACK_SFX = 10
HACK_STAIRCAM = 12
HackTable:
        .dw DrawAll-1, SamusFrame-1, CvFrame-1, HackReset-1, ChrLoaded-1, SfxUpdate-1, StairCamera-1

.include "draw.asm"
.include "samus.asm"
.include "bullets.asm"
.include "cv.asm"
.include "sfx.asm"
.include "hud.asm"
.include "chr.asm"
.include "../out/gen/samus_chr.asm"
.include "../out/gen/samus_frames.asm"

;@ seg $08 $BD00 $C000 hack bank: Castlevania's font
; A copy of bank 3 $BC08-$BF07, for the Game Over screen (see chr.asm).
        .incbin "../out/gen/cv_font.bin"
