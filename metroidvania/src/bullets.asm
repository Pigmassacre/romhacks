; Samus's projectiles: Metroid's UpdateSamusProjectiles, UpdateBullet and
; UpdateBulletExplode.
;
; Each projectile also holds one of Castlevania's subweapon slots ($14-$16)
; as a thrown dagger that doesn't move, kept where the shot is. That is how
; shots hurt enemies and break candles: Castlevania's own subweapon code tests
; daggers against every object, and on a hit turns the dagger into a spark
; (AI $32). The hack then explodes the shot, as Metroid does when a bullet
; hits an enemy. Samus draws the shots; the daggers have no sprite.
;
; Long Beam: Castlevania's first whip upgrade. Without it shots die after 12
; frames, as in Metroid.

CV_SHOT_AI = $17            ; subweapon
CV_SPARK_AI = $32           ; what a dagger turns into when it hits
SHOT_HIT_WALL = $80         ; in BulDie, once a shot has exploded on a wall

UpdateSamusProjectiles:
        lda #0
        sta $79                 ; no double/triple shot drops for shots
        ldx #2
@loop:
        jsr DoOneSamusProjectile
        dex
        bpl @loop
        rts

DoOneSamusProjectile:
        lda BulStatus,x
        beq @rts
        cmp #wa_BulletExplode
        beq UpdateBulletExplode
        jmp UpdateBullet
@rts:
        rts

UpdateBulletExplode:
        lda BulAnimFrame,x
        cmp #FrameNone
        beq @done
        jmp BulletAnim
@done:
        lda #0
        sta BulStatus,x
        rts

UpdateBullet:
        ; UpdateBullet_DeleteIfOffScreen
        jsr BulletScreenX
        bcs @delete
        ; UpdateBullet_ExplodeIfHitSprite: did Castlevania's dagger hit?
        lda ObjAI+$14,x
        cmp #CV_SHOT_AI
        beq @noHit
        cmp #CV_SPARK_AI
        bne @gone               ; Castlevania removed it
        ; a spark: a hit, unless Castlevania only took it off at the edge of
        ; the screen (it does that with sparks too). Metroid's shot flies on
        ; until it is off the screen.
        jsr BulletScreenX
        cmp #$10
        bcc @gone
        cmp #$F0
        bcs @gone
        jsr FreeCvShot
        jsr SFX_EnemyHit
        jsr UpdateBullet_Explode
        jmp BulletAnim
@gone:
        jsr FreeCvShot          ; CvShotSync puts it back
@noHit:
        ; UpdateBullet_CollisionWithBG
        lda BulXLo,x
        sta ColXLo
        lda BulXHi,x
        sta ColXHi
        lda BulY,x
        sta ColY
        stx Temp3
        jsr SolidCell
        ldx Temp3
        tay
        bne @wall
        ; UpdateBullet_Move
        lda BulY,x
        clc
        adc BulSpeedY,x
        cmp #$F0
        bcs @delete
        sta BulY,x
        lda BulSpeedX,x
        bmi @left
        clc
        adc BulXLo,x
        sta BulXLo,x
        bcc @moved
        inc BulXHi,x
        bcs @moved
@left:
        clc
        adc BulXLo,x
        sta BulXLo,x
        bcs @moved
        dec BulXHi,x
@moved:
        ; CheckBulletStat: short beams die
        lda WhipLevel
        bne BulletAnim
        dec BulDie,x
        bne BulletAnim
@delete:
        lda #0
        sta BulStatus,x
        jmp FreeCvShot
@wall:
        jsr FreeCvShot
        lda #SHOT_HIT_WALL      ; for Bank6_ShotsBreakBlocks
        sta BulDie,x
        jsr UpdateBullet_Explode
        jmp BulletAnim
UpdateBullet_Explode:
        lda #ObjAnim_BulletHit
        ldy BulStatus,x
        cpy #wa_Missile
        bne @bullet
        lda #ObjAnim_MissileExplode
@bullet:
        sta BulAnimReset,x
        sta BulAnimIndex,x
        lda #0
        sta BulAnimDelay,x
        lda #wa_BulletExplode
        sta BulStatus,x
        rts
; Animate (one frame each) and keep the dagger on the shot.
BulletAnim:
        lda BulAnimDelay,x
        beq @next
        dec BulAnimDelay,x
        bne @cv
@next:
        lda #1
        sta BulAnimDelay,x
        ldy BulAnimIndex,x
@get:
        lda ObjectAnimIndexTbl,y
        cmp #FrameEnd
        beq @reset
        sta BulAnimFrame,x
        iny
        tya
        sta BulAnimIndex,x
@cv:
        jmp CvShotSync
@reset:
        lda BulAnimReset,x
        tay
        jmp @get

FreeCvShot:
        lda #0
        sta ObjAI+$14,x
        rts

; Shot X's dagger: on screen where the shot is.
CvShotSync:
        lda BulStatus,x
        cmp #wa_BulletExplode
        beq @rts
        jsr BulletScreenX
        sta ObjX+$14,x
        lda BulY,x
        sta ObjY+$14,x
        lda ObjAI+$14,x
        bne @rts
        lda #CV_SHOT_AI
        sta ObjAI+$14,x
        lda #0
        sta ObjBonus+$14,x      ; a dagger: gone after one hit
        sta ObjPose+$14,x
        sta ObjFlags+$14,x
        sta ObjVX+$14,x
        sta ObjVXSub+$14,x
        sta ObjVY+$14,x
        sta ObjVYSub+$14,x
        lda #1
        sta ObjAction+$14,x     ; already thrown: the AI only applies its speed
        lda #$FF
        sta ObjLastHit+$14,x
@rts:
        rts

; A = shot x on screen; carry set if it is off the screen.
BulletScreenX:
        lda BulXLo,x
        sec
        sbc ScrollLo
        pha
        lda BulXHi,x
        sbc ScrollHi
        cmp #1                  ; 0: on screen
        pla
        rts
