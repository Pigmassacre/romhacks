; Effects: up to FX_SLOTS extra star-bank metasprites, drawn with the star's
; own draw routine. The recalled star flying home and the splash of a skip
; are effects. They do not collide with anything.
;
; Each slot has a kind, a frame counter (0 = free) and a position.
FX_RECALL       = 0         ; the old star flies to where the new one is charging
FX_SPLASH       = 1         ; a splash stays where it was made

; Start an effect of kind A at slot 1's position (the star). Uses the slot
; given in Y (0 or 1).
FxStartAtStar:
        sta FX_Kind,y
        lda #1
        sta FX_T,y
        lda Obj_YSub+1
        sta FX_YSub,y
        lda Obj_YTile+1
        sta FX_YTile,y
        lda Obj_XSub+1
        sta FX_XSub,y
        lda Obj_XTile+1
        sta FX_XTile,y
        lda Obj_Facing+1
        sta FX_Facing,y
        rts

; Called from bank $1D $8469, the start of the star's draw routine, with bank
; $1D at $8000. Draws the effects, then does the two instructions the hook
; replaced.
FxDraw:
        ldy #FX_SLOTS-1
@slot:
        sty FX_Cur
        jsr FxOne
        ldy FX_Cur
        dey
        bpl @slot
        lda Obj_YSub+1          ; replaced by the hook
        sta $0424
        rts

FxOne:
        lda FX_T,y
        beq @rts
        ldx FX_Kind,y
        cmp FxLength,x
        bcs @kill
        lda FX_YTile,y          ; Yumetaro went to another vertical screen
        eor Obj_YTile
        and #$F0
        beq @show
@kill:
        lda #0
        sta FX_T,y
@rts:
        rts
@show:
        cpx #FX_RECALL
        bne @draw
        lda FX_T,y
        cmp #2
        bcc @draw               ; first frame: where the old star was
        jsr FxHome
@draw:
        ; pick the frame
        ldx FX_Kind,y
        lda FX_T,y
        cpx #FX_RECALL
        bne @splash
        lda #STAR_FRAME_STAR
        bne @frame
@splash:
        sec                     ; frame (T - 1) / 2: 2 game frames each
        sbc #1
        lsr a
        clc
        adc #STAR_FRAME_SPLASH
@frame:
        sta FX_Frame
        jsr FxPut
        ldy FX_Cur
        lda FX_T,y
        clc
        adc #1
        sta FX_T,y
        rts

; Lengths in frames, +1.
FxLength:
        .db GHOST_LEN+1, SPLASH_LEN+1

; Move slot Y a quarter of the way to where a charging star sits: one tile
; above Yumetaro's feet.
FxHome:
        lda Obj_XSub
        sec
        sbc FX_XSub,y
        sta $02
        lda Obj_XTile
        sbc FX_XTile,y
        jsr Quarter
        lda FX_XSub,y
        clc
        adc $02
        sta FX_XSub,y
        lda FX_XTile,y
        adc $03
        sta FX_XTile,y

        lda Obj_YSub
        sec
        sbc FX_YSub,y
        sta $02
        lda Obj_YTile
        sbc FX_YTile,y
        sec
        sbc #1                  ; one tile up
        jsr Quarter
        lda FX_YSub,y
        clc
        adc $02
        sta FX_YSub,y
        lda FX_YTile,y
        adc $03
        sta FX_YTile,y
        rts

; $03:$02 = (A:$02) / 4, signed, rounding down.
Quarter:
        cmp #$80
        ror a
        ror $02
        cmp #$80
        ror a
        ror $02
        sta $03
        rts

; Draw slot Y with frame FX_Frame, standing in for slot 1 for a moment.
FxPut:
        lda Obj_YSub+1
        sta Save_Area+0
        lda Obj_YTile+1
        sta Save_Area+1
        lda Obj_XSub+1
        sta Save_Area+2
        lda Obj_XTile+1
        sta Save_Area+3
        lda Obj_Frame+1
        sta Save_Area+4
        lda Obj_Facing+1
        sta Save_Area+5
        lda Obj_Flags+1
        sta Save_Area+6

        lda FX_YSub,y
        sta Obj_YSub+1
        lda FX_YTile,y
        sta Obj_YTile+1
        lda FX_XSub,y
        sta Obj_XSub+1
        lda FX_XTile,y
        sta Obj_XTile+1
        lda FX_Facing,y
        sta Obj_Facing+1
        lda FX_Frame
        sta Obj_Frame+1
        lda #0                  ; in front of the background
        ldx FX_Kind,y
        cpx #FX_RECALL
        bne @flags
        lda FrameCount          ; the star's palette flicker
        and #1
@flags:
        sta Obj_Flags+1
        lda #<StarFrames
        sta $00
        lda #>StarFrames
        sta $01
        ldx #1
        jsr DrawMetasprite

        lda Save_Area+0
        sta Obj_YSub+1
        lda Save_Area+1
        sta Obj_YTile+1
        lda Save_Area+2
        sta Obj_XSub+1
        lda Save_Area+3
        sta Obj_XTile+1
        lda Save_Area+4
        sta Obj_Frame+1
        lda Save_Area+5
        sta Obj_Facing+1
        lda Save_Area+6
        sta Obj_Flags+1
        rts
