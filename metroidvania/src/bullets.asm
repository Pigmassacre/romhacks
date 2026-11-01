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
;
; Bombs (Metroid's CheckBombLaunch, BombInit, BombCountdown, BombExplode) take the
; same slots. Their blast's dagger moves around from frame to frame, to cover the
; blast, and it's put back after each hit, up to BOMB_HITS of them.

CV_SHOT_AI = $17            ; subweapon
CV_SPARK_AI = $32           ; what a dagger turns into when it hits
SHOT_HIT_WALL = $80         ; in BulDie, once a shot has exploded on a wall
BOMB_FUSE = $18             ; in BulDie: every other frame
BOMB_HITS = 2               ; in BulSpeedX: what a blast has left

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
        bne @notExplode
        jmp UpdateBulletExplode
@notExplode:
        cmp #wa_LayBomb
        bcc @bullet
        cmp #wa_Missile
        bcs @bullet
        jmp UpdateBomb
@bullet:
        jmp UpdateBullet
@rts:
        rts

UpdateBomb:
        cmp #wa_BombCount
        beq @countdown
        cmp #wa_BombExplode
        beq @explode
        lda #ObjAnim_BombTick
        jsr BombAnimStart
        lda #BOMB_FUSE
        sta BulDie,x
        inc BulStatus,x
        bne BombAnim
@countdown:
        lda FrameCounter
        lsr
        bcc BombAnim
        dec BulDie,x
        bne BombAnim
        lda #ObjAnim_BombExplode
        jsr BombAnimStart
        inc BulStatus,x
        lda #SHOT_HIT_WALL      ; for Bank6_ShotsBreakBlocks
        sta BulDie,x
        lda #BOMB_HITS
        sta BulSpeedX,x
        jsr SFX_BombExplode
        jmp BombAnim
@explode:
        lda BulAnimFrame,x
        cmp #FrameNone
        bne @going
        lda #0
        sta BulStatus,x
        jsr FreeCvShot
        jmp BombAnim
@going:
        jsr BlastDagger
BombAnim:
        lda BulAnimDelay,x
        beq @next
        dec BulAnimDelay,x
        bne @rts
@next:
        lda #3
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
@rts:
        rts
@reset:
        ldy BulAnimReset,x
        jmp @get

; A = animation
BombAnimStart:
        sta BulAnimReset,x
        sta BulAnimIndex,x
        lda #0
        sta BulAnimDelay,x
        rts

; The dagger of bomb X's blast, somewhere else in it each frame. Only well inside the
; screen: at the edges Castlevania takes sparks off by itself, and the x can wrap.
BlastDagger:
        jsr BulletScreenX
        bcs @free
        cmp #$10
        bcc @free
        cmp #$F0
        bcs @free
        lda ObjAI+$14,x
        beq @place
        cmp #CV_SHOT_AI
        beq @place
        cmp #CV_SPARK_AI
        bne @removed
        dec BulSpeedX,x
        jsr FreeCvShot
        jsr SFX_EnemyHit
        jmp @place
@removed:
        jsr FreeCvShot
@place:
        lda BulSpeedX,x
        beq @free
        jsr CvShotSync
        jmp BlastPlace
@free:
        jmp FreeCvShot

; The dagger, off to one side or the other as the frames go.
BlastPlace:
        lda FrameCounter
        and #$03
        tay
        lda BlastDx,y
        clc
        adc ObjX+$14,x
        sta ObjX+$14,x
        lda BlastDy,y
        clc
        adc ObjY+$14,x
        sta ObjY+$14,x
        rts
BlastDx:
        .db 0, -12, 12, 0
BlastDy:
        .db 0, 0, 0, -12

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
        bcc @onScreen
        jmp @delete
@onScreen:
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
        lda BulStatus,x
        cmp #wa_WaveBeam
        bne @notWave
        jsr WaveSpeeds
@notWave:
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

; Castlevania takes over for good (dying, doors, a stage's end): nothing
; moves the shots any more, so they end, with their daggers.
ClearShots:
        ldx #2
@shot:
        lda #0
        sta BulStatus,x
        lda ObjAI+$14,x
        cmp #CV_SHOT_AI
        bne @next
        jsr FreeCvShot
@next:
        dex
        bpl @shot
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
        sta ObjPoseStep+$14,x
        lda #1
        sta ObjAction+$14,x     ; already thrown: the AI only applies its speed
        lda #$80                ; no pose animation ($F1DB): the slot may still
        sta ObjPoseTimer+$14,x  ; hold the spark of the last hit, and drew it
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

; Metroid's CheckBombLaunch: B in the ball, on the ground, with a slot free.
CheckBombLaunch:
        lda Joy1Change
        ora Joy1Retrig
        asl
        bpl @rts
        lda SamusSpeedY
        bne @rts
        ldx #0
@slot:
        lda BulStatus,x
        beq @found
        inx
        cpx #3
        bne @slot
@rts:
        rts
@found:
        lda SamusXHi
        sta BulXHi,x
        lda SamusXLo
        sta BulXLo,x
        lda SamusY
        clc
        adc #4
        sta BulY,x
        lda #wa_LayBomb
        sta BulStatus,x
        lda #ObjFrame_Bomb0     ; (drawn before its first update)
        sta BulAnimFrame,x
        jmp SFX_BombLaunch

; Metroid's bomb <--> Samus detection: touching a blast throws her, with no damage.
; Bomb X's radius is that of the frame it shows.
CheckBombsTouchSamus:
        ldx #2
@bomb:
        lda BulStatus,x
        cmp #wa_BombExplode
        beq @blast
@next:
        dex
        bpl @bomb
        rts
@blast:
        ldy #$10
        lda BulAnimFrame,x
        cmp #$4D
        beq @radius
        ldy #$0C
        cmp #$3C
        beq @radius
        cmp #$49
        beq @radius
        ldy #0
@radius:
        sty Temp2
        lda #2
        sta Temp3               ; bit 2, then y's sign, then x's
        tya
        clc
        adc SamusRadiusY
        sta Temp0
        lda BulY,x
        sec
        sbc SamusY
        bcs @yPos
        eor #$FF
        adc #1
        inc Temp3
@yPos:
        cmp Temp0
        bcs @next
        asl Temp3
        lda Temp2
        clc
        adc SamusRadiusX
        sta Temp0
        lda BulXLo,x
        sec
        sbc SamusXLo
        sta Temp1
        lda BulXHi,x
        sbc SamusXHi
        bpl @xPos
        tay
        lda #0
        sec
        sbc Temp1
        sta Temp1
        tya
        eor #$FF
        adc #0
        inc Temp3
@xPos:
        bne @next
        lda Temp1
        cmp Temp0
        bcs @next
        lda Temp1
        beq @store
        lda #1
@store:
        sta SamusKnockBomb
        lda Temp3
        asl
        asl
        asl
        ora SamusIsHit
        sta SamusIsHit
        jmp @next

; ---- Wave Beam ----------------------------------------------------------------------
; Metroid's UpdateWaveBullet: a new step of its path each frame, up or forwards.
; BulWave: bit 7 fired up, bit 6 fired left, the rest the step.
WAVE_STEPS = 12

; Y = the shot.
CheckHorizontalWaveBulletFire:
        lda SamusDir
        beq CheckWaveFire
        lda #$40
        bne CheckWaveFire
CheckVerticalWaveBulletFire:
        lda #$80
CheckWaveFire:
        sta BulWave,y
        lda Upgrades
        and #UP_WAVE
        beq @rts
        lda MissileToggle
        bne @rts
        cpy #1                  ; (the middle shot weaves the other way)
        bne @step
        lda BulWave,y
        ora #WAVE_STEPS / 2
        sta BulWave,y
@step:
        lda #wa_WaveBeam
        sta BulStatus,y
        lda #ObjAnim_WaveBeam
        jsr SetBulletAnim
        jmp SFX_WaveFire
@rts:
        rts

; Shot X's speeds this frame.
WaveSpeeds:
        lda BulWave,x
        and #$0F
        tay
        lda BulWave,x
        bmi @up
        lda WaveTbl,y
        sta BulSpeedY,x
        lda BulWave,x
        and #$40
        beq @right
        lda #-3
        bne @x
@right:
        lda #3
@x:
        sta BulSpeedX,x
        jmp @next
@up:
        lda #0
        sec
        sbc WaveTbl,y
        sta BulSpeedX,x
        lda #-3
        sta BulSpeedY,x
@next:
        inc BulWave,x
        lda BulWave,x
        and #$0F
        cmp #WAVE_STEPS
        bne @rts
        lda BulWave,x
        and #$C0
        sta BulWave,x
@rts:
        rts
WaveTbl:
        .db -7, -5, -1, 1, 5, 7, 7, 5, 1, -1, -5, -7

; ---- Screw Attack -------------------------------------------------------------------
; Metroid's IsScrewAttackActive: carry clear while she spins with it, or rises in a
; straight jump.
IsScrewAttackActive:
        sec
        ldy SamusStatus
        dey
        bne @rts
        lda Upgrades
        and #UP_SCREW
        beq @rts
        lda SamusAnimReset
        cmp #ObjAnim_SamusSalto
        beq @active
        cmp #ObjAnim_SamusJump
        sec
        bne @rts
        bit SamusSpeedY
        bpl @rts
@active:
        cmp SamusAnimIndex
@rts:
        rts

; Enemies can't touch her while it's active. It hurts them as a blast does, with a
; dagger in a free shot slot, moved around her, and a rest after each hit: a hit every
; frame would end any boss on contact.
SCREW_REST = $10

ScrewAttackUpdate:
        ldx #2
@free:
        lda BulStatus,x
        bne @nextFree
        lda ObjAI+$14,x
        beq @nextFree
        cmp #CV_SPARK_AI
        bne @remove
        lda #SCREW_REST         ; it hit
        sta ScrewWait
        jsr SFX_EnemyHit
@remove:
        jsr FreeCvShot
@nextFree:
        dex
        bpl @free
        lda ScrewWait
        beq @noWait
        dec ScrewWait
@noWait:
        jsr IsScrewAttackActive
        bcs @rts
        lda Invincible
        cmp #2
        bcs @touch
        lda #2
        sta Invincible
@touch:
        lda ScrewWait
        bne @rts
        ldx #2
@slot:
        lda BulStatus,x
        beq @place
        dex
        bpl @slot
@rts:
        rts
@place:
        lda SamusXLo
        sta BulXLo,x
        lda SamusXHi
        sta BulXHi,x
        lda SamusY
        sta BulY,x
        jsr BulletScreenX
        bcs @rts
        cmp #$10
        bcc @rts
        cmp #$F0
        bcs @rts
        jsr CvShotSync
        jmp BlastPlace
