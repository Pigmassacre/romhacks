; Skipping stones, from Gimmick! 2.
;
; In the original game a star that touches water sinks. In Gimmick! 2 a star
; that hits water fast enough skips off it, a little lower and slower each
; time, until it is too slow and sinks. Here it is the same: if it is moving
; sideways at SKIP_MIN_VX or more, it bounces back up at 3/4 of the speed it
; came down with (at most SKIP_MAX_VY) and loses 1/8 of its sideways speed.
; A bounce slower than SKIP_MIN_VY sinks it. It can be ridden while it skips,
; as after any bounce.
;
; The physics routine ($F596) kills anything whose feet are in a lethal tile
; when it starts. Water is the lethal kind with a splash ($7F00 != 0). So this
; runs just before the star's physics, and lifts the star out of the water
; tile before the physics can see it there.

; Called from bank $1D $8151 with bank $1D at $8000, after the star's floor
; bounce and before its physics.
WaterSkip:
        jsr StarInWater
        bcc @done
        jsr Skip
@done:
        lda Obj_VY+1            ; replaced by the hook
        sta $0397
        rts

; Carry set if the star's feet are in water. Then $03 = the surface's Y
; inside that tile.
StarInWater:
        lda Obj_YTile+1
        and #$0F
        cmp #$0C
        bcs @no                 ; below the map: the physics ignores tiles
        sta $02                 ; row
        ldy Obj_XTile+1         ; the tile at its feet, the way $F596 finds it
        lda $F0BC,y
        sta $06
        lda $F13C,y
        ldy CurScreen
        clc
        adc $F66C,y
        sta $07
        ldy $02
        lda ($06),y
        tay
        lda $7D00,y
        bne @no                 ; not lethal
        lda $7F00,y
        beq @no                 ; lethal but not water (spikes, pits)
        tay
        lda $F5F9,y             ; where the surface is in the tile
        sta $03
        sec
        rts
@no:
        clc
        rts

; Bounce it off the water, or leave it to sink.
Skip:
        lda Obj_VX+1            ; fast enough sideways?
        bpl @vxpos
        eor #$FF
        clc
        adc #1
@vxpos:
        cmp #SKIP_MIN_VX
        bcc @sink
        lda Obj_VY+1
        bmi @sink
        lsr a                   ; bounce = 3/4 of vy, at most SKIP_MAX_VY
        lsr a
        sta $04
        lda Obj_VY+1
        sec
        sbc $04
        cmp #SKIP_MAX_VY
        bcc @capped
        lda #SKIP_MAX_VY
@capped:
        cmp #SKIP_MIN_VY
        bcs @skip
@sink:
        rts                     ; the physics sinks it, as in the original
@skip:
        eor #$FF
        clc
        adc #1
        sta Obj_VY+1

        lda Obj_VX+1            ; vx -= vx / 8, toward 0
        cmp #$80
        ror a
        cmp #$80
        ror a
        cmp #$80
        ror a
        sta $04
        lda Obj_VX+1
        sec
        sbc $04
        sta Obj_VX+1
        sta $03A1               ; the speed it reverses with off a wall

        lda Obj_YSub+1          ; a splash on the surface where it hit
        pha
        lda $03
        sta Obj_YSub+1
        lda #FX_SPLASH
        ldy #1
        jsr FxStartAtStar
        pla
        sta Obj_YSub+1

        lda #$F0                ; out of the water tile: feet 1 px above it
        sta Obj_YSub+1
        dec Obj_YTile+1
        lda #$40
        sta Obj_Standable+1     ; ride it across
        lda #SND_SPLASH
        jmp PlaySound
