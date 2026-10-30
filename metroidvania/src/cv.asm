; Between Samus and Castlevania.
;
; Castlevania keeps using Simon's variables: enemies touch him at ObjX/ObjY
; (slot 0) within SimonHeight, the level collision and stage exits look at
; SimonXHi:SimonXLo and SimonY, and the stairs code moves him. Samus writes
; her position there every frame, and takes it back after Castlevania has
; moved Simon (stairs, walking in at a stage's start, respawning).
;
; Health: Castlevania's enemy code takes 8, 12 or 16 off SimonHP (of $40)
; per hit, and items and stage clears add to it. Samus has Metroid's energy,
; 99 at most (there are no energy tanks). The hack keeps SimonHP at $20 and
; turns each change of it into energy: one and a half energy per unit, so it
; takes as many hits to die as it did for Simon. A refill to $40 is a full
; refill.

CV_HP = $20

; At power-on (Castlevania's reset, after it clears zero page).
HackReset:
        lda #0
        ldx #$2F
@ram0:  sta $0100,x
        dex
        bpl @ram0
        ldx #$21
@ram1:  sta BulStatus,x
        dex
        bpl @ram1
        sta DebugFlags
        lda #$FF
        sta SamusKnockDir
        jmp FillHealth

FillHealth:
        lda #$90
        sta HealthLo
        lda #$09
        sta HealthHi
        rts

; Take over from Simon: where he stands, standing still.
ImportSimon:
        lda SimonXLo
        sta SamusXLo
        lda SimonXHi
        sta SamusXHi
        ldx SimonY
        inx
        stx SamusY
        lda ObjFacing
        and #1
        sta SamusDir
        lda #sa_Stand
        sta SamusStatus
        lda #ObjAnim_SamusStand
        jsr SetSamusAnim
        lda #ObjFrame_SamusStand
        sta SamusAnimFrame
        lda #$0F
        sta SamusRadiusY
        lda #$04
        sta SamusRadiusX
        lda #0
        sta SamusSpeedX
        sta SamusSpeedY
        sta SamusSpeedSubX
        sta SamusSpeedSubY
        sta SamusAccelX
        sta SamusAccelY
        sta SamusIsHit
        sta SamusInvincible
        lda #$FF
        sta SamusKnockDir
        lda #CV_HP
        sta LastHP
        sta SimonHP
        lda #0
        sta RideSlot
        lda HackState
        ora #HS_SAMUS
        sta HackState
        lda HealthLo
        ora HealthHi
        bne @rts
        jsr FillHealth
@rts:
        rts

; Called by the bank 6 hook instead of Simon's handler, for actions 0-5 and 9.
SamusFrame:
        lda HackState
        and #HS_SAMUS
        bne @ok
        jsr ImportSimon
@ok:
        lda #0
        sta ScrollDelta
        sta MoveDir
        sta StairDir
        lda HackState
        and #~(HS_KILL | HS_GROUND)
        sta HackState
        jsr SamusUpdate
        jsr CheckBossLock
        ; hearts are missiles: Metroid's sound for picking them up
        lda Hearts
        cmp LastHearts
        sta LastHearts
        beq @fall
        bcc @fall
        jsr SFX_MissilePickup
@fall:
        jmp CheckFall

; Castlevania hurt or healed Simon since last frame?
CheckCvDamage:
        lda SimonHP
        cmp #$40
        bne @notFull
        jsr FillHealth
        jmp @done
@notFull:
        jsr CvHPChange
        bcc @done
        ; hurt: HealthChange set
        ; knocked away from the enemy: Castlevania turned Simon to face it
        ldx SamusDir
        lda ObjAction
        cmp #5
        bne @noDir
        ldx ObjFacing
@noDir:
        txa
        asl
        asl
        asl
        ora #$20
        sta SamusIsHit
        lda #$FF
        sta SamusKnockBomb
@done:
        ; a hit also sets this for Simon's knockback ($96DC), which counts it
        ; down, and Samus has her own. Left set, the climb from stage 10 to 11
        ; goes wrong ($964D): she came in at floor 255, and fell through it.
        lda #0
        sta ObjAction
        sta $054C
        rts

; SimonHP against LastHP: a heal goes onto Samus's energy; a hurt (carry
; set) is left in HealthChange. Hits that take SimonHP below 0 are hurts.
CvHPChange:
        lda SimonHP
        bmi @hurt
        sec
        sbc LastHP
        beq @none
        bcc @hurt
        jsr EnergyOf            ; healed: A = units
        jsr AddHealth
        jsr SFX_EnergyPickup
@none:
        clc
        rts
@hurt:
        lda LastHP
        sec
        sbc SimonHP
        jsr EnergyOf
        sec
        rts

; A = SimonHP units -> HealthChange, 1.5 energy per unit, in BCD.
EnergyOf:
        sta Temp0
        lsr
        clc
        adc Temp0
        ldx #0
@tens:
        cmp #10
        bcc @ones
        sbc #10
        inx
        bne @tens
@ones:
        asl
        asl
        asl
        asl
        sta HealthChangeLo
        stx HealthChangeHi
        rts

; Simon's variables from Samus's.
SyncSimon:
        lda SamusXLo
        sta SimonXLo
        sec
        sbc ScrollLo
        sta ObjX
        lda SamusXHi
        sta SimonXHi
        ldx SamusY
        dex
        stx SimonY
        stx ObjY
        lda SamusDir
        sta ObjFacing
        lda SamusRadiusY
        sec
        sbc #3
        sta SimonHeight
        lda SamusInvincible
        cmp Invincible
        bcc @inv
        sta Invincible
@inv:
        lda #CV_HP
        sta SimonHP
        sta LastHP
        ; standing on the ground (for the stairs)
        lda SamusAccelY
        bne @air
        lda SamusStatus
        cmp #sa_Roll
        beq @air
        cmp #sa_Jump
        beq @air
        lda HackState
        ora #HS_GROUND
        sta HackState
@air:
        ; in the air, Simon is jumping (action 1): Castlevania's crushers
        ; ($8282) only hurt him then, and kill him otherwise
        ldx #0
        lda SamusAccelY
        bne @jump
        lda SamusStatus
        cmp #sa_Jump
        bne @action
@jump:
        inx
@action:
        stx ObjAction
        rts

; Dead, or fallen out of the level: Castlevania's death takes over.
CheckFall:
        lda SamusStatus
        cmp #sa_Dead
        beq @kill
        lda SamusY
        sec
        sbc SamusRadiusY
        cmp #$E0
        bcc @rts
        cmp #$F0
        bcs @rts
@kill:
        lda #0
        sta SimonHP
        lda HackState
        ora #HS_KILL
        and #~HS_SAMUS
        sta HackState
@rts:
        rts

; Castlevania moves Simon itself (stairs, walking in, dying): Samus follows.
; Hit on the stairs, Simon stays on them, stunned ($96C1): the hit is taken
; off Samus's energy now. Carry set if that kills her.
CvFrame:
        lda StairDir            ; as it was before StairCamera
        beq @dir
        sta MoveDir
        lda #0
        sta StairDir
@dir:
        lda HackState
        and #~HS_SAMUS
        sta HackState
        lda SimonXLo
        sta SamusXLo
        lda SimonXHi
        sta SamusXHi
        ldx SimonY
        inx
        stx SamusY
        lda ObjFacing
        and #1
        sta SamusDir
        lda ObjAction
        cmp #4
        beq @stairs
        cmp #6
        beq @stairs
        cmp #8
        bne @alive
        jsr ClearShots          ; dying
        clc
        rts
@stairs:
        jsr StairShots
        lda ObjAction
        cmp #4
        bne @alive
        jsr CvHPChange
        bcc @same
        jsr SubtractHealth
        jsr SFX_SamusHit
@same:
        lda #CV_HP
        sta SimonHP
        sta LastHP
        lda SamusStatus
        cmp #sa_Dead
        beq @rts                ; (carry set)
@alive:
        clc
@rts:
        rts

; Started away from the middle of the screen (MoveDir bit 2), Simon moves on
; the screen, not the screen: he only ever does that at a stage's ends, where
; it stops him. Samus's camera leaves her off the middle anywhere, and a long
; staircase took her off the edge of the screen: her x wrapped round, and the
; stairs with it. So the screen catches up, a pixel a frame, until Castlevania
; takes over at the middle. For the rest of this frame MoveDir says the screen
; moved, for the objects' sake; it goes back before Castlevania next looks.
StairCamera:
        lda ObjAction
        cmp #4
        bne @rts
        lda GameMode
        cmp #5
        bne @rts
        lda GameModeAux
        cmp #6
        bne @rts
        lda MoveDir
        and #4
        beq @rts
        lda MoveDir
        sta Temp3
        lda #0
        sta ScrollDelta
        lda ObjX
        cmp #$80
        beq @rts
        bcc @left
        jsr ScrollRight1
        bcs @rts
        dec ObjX
        bcc @moved              ; (always: ScrollRight1 left it clear)
@left:
        jsr ScrollLeft1
        bcs @rts
        inc ObjX
@moved:
        lda Temp3
        sta StairDir
@rts:
        rts

; On the stairs (and walking to them) B would start Simon's whip, drawn
; with Samus's tiles: it fires her beam forwards instead, and her shots
; keep moving.
StairShots:
        jsr ReadJoy
        lda PadPressed
        and #~BTN_B
        sta PadPressed
        jsr UpdateSamusProjectiles
        jsr CheckMissileToggle
        lda Joy1Change
        and #BTN_B
        beq @rts
        jmp FireSamusProjectileForwards
@rts:
        rts

CvMaxScreen:
        jmp $D015

CvMinScreen:
        jmp $D025

CvLoadColumn:
        jmp $D196
