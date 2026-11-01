; Samus's sound effects: Metroid's, played back as the APU writes Metroid's
; sound engine made for them (src/sfxdata.asm), one frame of writes per
; frame, after Castlevania's music has had its turn.
;
; Each effect has a stream, like Metroid's SFX channels: noise, square 1,
; triangle, and "multi" (both squares, Samus getting hit). While a stream
; plays, Castlevania's music and sound effects on its channels write to
; $4018 instead, which does nothing (Bank0_SfxChan).

SFX_NOISE = 0
SFX_SQ1 = 1
SFX_TRI = 2
SFX_MULTI = 3

SFX_SamusWalk:
        lda #0
        .db $2C                 ; bit abs: skips the next lda
SFX_MissileLaunch:
        lda #1
        .db $2C
SFX_SamusJump:
        lda #2
        .db $2C
SFX_BulletFire:
        lda #3
        .db $2C
SFX_EnemyHit:
        lda #4
        .db $2C
SFX_EnergyPickup:
        lda #5
        .db $2C
SFX_MissilePickup:
        lda #6
        .db $2C
SFX_SamusDie:
        lda #7
        .db $2C
SFX_SamusBall:
        lda #8
        .db $2C
SFX_Beep:
        lda #9
        .db $2C
SFX_SamusHit:
        lda #10
        .db $2C
SFX_BombLaunch:
        lda #11
        .db $2C
SFX_BombExplode:
        lda #12
; A = effect: start it on its stream, over whatever that stream played.
; Keeps X and Y.
SfxStart:
        sta SfxSaveX
        txa
        pha
        tya
        pha
        ldx SfxSaveX
        ldy SfxStream,x
        lda #0
        sta SfxPtrHi,y          ; stop it first: the NMI plays streams
        sta SfxWait,y
        lda SfxLo,x
        sta SfxPtrLo,y
        lda SfxHi,x
        sta SfxPtrHi,y
        pla
        tay
        pla
        tax
        rts

SfxLo:
        .db <SfxWalk, <SfxMissileLaunch, <SfxJump, <SfxBulletFire, <SfxEnemyHit
        .db <SfxEnergyPickup, <SfxMissilePickup, <SfxDie, <SfxBall, <SfxBeep, <SfxHit
        .db <SfxBombLaunch, <SfxBombExplode
SfxHi:
        .db >SfxWalk, >SfxMissileLaunch, >SfxJump, >SfxBulletFire, >SfxEnemyHit
        .db >SfxEnergyPickup, >SfxMissilePickup, >SfxDie, >SfxBall, >SfxBeep, >SfxHit
        .db >SfxBombLaunch, >SfxBombExplode
SfxStream:
        .db SFX_NOISE, SFX_NOISE, SFX_SQ1, SFX_SQ1, SFX_SQ1
        .db SFX_SQ1, SFX_SQ1, SFX_TRI, SFX_TRI, SFX_TRI, SFX_MULTI
        .db SFX_TRI, SFX_NOISE

; Each NMI, after Castlevania's music (Bank0_Music).
SfxPtr = $BA                ; Castlevania's music is done with these by now

SfxUpdate:
        ldx #3
@stream:
        lda SfxPtrHi,x
        beq @next
        lda SfxWait,x
        beq @play
        dec SfxWait,x
        jmp @next
@play:
        lda SfxPtrLo,x
        sta SfxPtr
        lda SfxPtrHi,x
        sta SfxPtr+1
        ldy #0
@byte:
        lda (SfxPtr),y
        iny
        cmp #$80
        bcs @frame
        stx SfxSaveX            ; not Temp3: a late NMI may have stopped
        tax                     ; Castlevania in the middle of using it
        lda (SfxPtr),y
        iny
        sta $4000,x
        ldx SfxSaveX
        jmp @byte
@frame:
        cmp #$FF
        beq @end
        and #$3F
        sta SfxWait,x
        tya
        clc
        adc SfxPtr
        sta SfxPtrLo,x
        lda #0
        adc SfxPtr+1
        sta SfxPtrHi,x
        jmp @next
@end:
        lda #0
        sta SfxPtrHi,x
@next:
        dex
        bpl @stream
        rts

; Mutes a stream's effect if the game is paused (Castlevania silences its
; own sounds then).
SfxStopAll:
        lda #0
        ldx #3
@stop:
        sta SfxPtrHi,x
        dex
        bpl @stop
        rts

; Metroid shows missile mode in Samus's colours: Bank0_BgGfx does it.
SelectSamusPalette:
        rts

.include "sfxdata.asm"
