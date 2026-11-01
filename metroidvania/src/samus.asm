; Samus, ported from Metroid's engine (labels and comments follow the m1disasm
; disassembly: UpdateSamus, SamusStand, SamusRun, ...). The logic, constants
; and order of operations are Metroid's. What changes is the world around her:
;
; - Collision: Metroid looks up 8x8 tiles in its room RAM; here the same
;   points are looked up in Castlevania's collision map (SolidAt, also 8x8).
;   Anything above the playfield ($30) is solid, so Samus can't jump into
;   the status bar.
; - Scrolling: Metroid scrolls when Samus leaves the middle of the screen
;   ($71-$8F); here that moves Castlevania's scroll ($2D-$2F) instead, up to
;   the limits Castlevania's own walking code checks. There is no vertical
;   scrolling; Castlevania's stages are one screen high.
; - Damage comes from Castlevania: its enemy contact code hurts Simon and
;   starts his knockback (action 5). The hack turns that into Metroid's hit.
;
; Samus's position is her centre in the level: SamusXHi:SamusXLo, SamusY.

SamusUpdate:
        jsr ReadJoy
        jsr CheckCvDamage
        jsr RidePlatform
        jsr CheckBombsTouchSamus
        jsr UpdateSamusProjectiles
        ; UpdateSamus
        jsr GoSamusHandler
        jsr SubtractHealth
        jsr CheckMissileToggle
        jsr RecentreCamera
        jmp SyncSimon

; ---- Input -------------------------------------------------------------------
; Metroid's ReadOnePad, from Castlevania's held buttons. Joy1Change is the
; newly pressed buttons, except that B counts as newly pressed whenever any
; button changes; Joy1Retrig repeats held buttons after 32 frames, then
; every 8.

ReadJoy:
        lda Joy1Status
        sta Temp0
        lda PadHeld
        sta Joy1Status
        eor Temp0
        beq @same
        lda Temp0
        and #~BTN_B
        sta Temp0
        eor Joy1Status
@same:
        and Joy1Status
        sta Joy1Change
        sta Joy1Retrig
        ldy #$20
        lda Joy1Status
        cmp Temp0
        bne @set
        dec RetrigDelay
        bne @rts
        sta Joy1Retrig
        ldy #$08
@set:
        sty RetrigDelay
@rts:
        rts

; ---- Handlers ----------------------------------------------------------------

GoSamusHandler:
        lda SamusStatus
        bmi @stand
        asl
        tax
        lda @table+1,x
        pha
        lda @table,x
        pha
        rts
@stand:
        jmp SamusStand
@table:
        .dw SamusStand-1, SamusRun-1, SamusJump-1, SamusRoll-1
        .dw SamusPntUp-1, SamusStand-1, SamusJump-1

SamusStand:
        lda Joy1Status
        and #~(BTN_SELECT | BTN_START)
        beq @noButtons
        jsr SetSamusStand_NoFootstep
        lda Joy1Status
@noButtons:
        and #BTN_DOWN | BTN_LEFT | BTN_RIGHT
        bne @dpad
        lda Joy1Change
        and #BTN_UP
        beq @fire
@dpad:
        jsr BitScan
        cmp #BUTTONBIT_DOWN
        bcs @notDir
        sta SamusDir
@notDir:
        tax
        lda ActionTable,x
        sta SamusStatus
@fire:
        lda Joy1Change
        ora Joy1Retrig
        asl
        bpl @jump
        jsr FireSamusProjectile
@jump:
        bit Joy1Change
        bpl @data
        lda #sa_Jump
        sta SamusStatus
@data:
        lda #$04
        jsr SetSamusData
        lda SamusStatus
        cmp #sa_Door
        bcs @rts
        asl
        tax
        lda @next+1,x
        pha
        lda @next,x
        pha
@rts:
        rts
@next:
        .dw NoOp-1, SetSamusRun-1, SetSamusJump-1, SetSamusRoll-1, SetSamusPntUp-1

ActionTable:
        .db sa_Run, sa_Run, sa_Roll, sa_PntUp

NoOp:
        rts

SetSamusRun:
        lda #$09
        sta WalkSoundDelay
        ldx #$00
        lda SamusAnimReset
        cmp #ObjAnim_SamusStand
        beq @set
        inx
        cmp #ObjAnim_SamusPntUp
        beq @set
        lda #ObjAnim_SamusFront
        jsr SetSamusNextAnim
@set:
        lda RunAnimationTbl,x
        sta SamusAnimReset
        ldx SamusDir
SetSamusRunAccel:
        lda RunAccelerationTbl,x
        sta SamusAccelX
        rts

RunAnimationTbl:
        .db ObjAnim_SamusRun, ObjAnim_SamusRunPntUp
RunAccelerationTbl:
        .db $30, $D0

SamusRun:
        ldx SamusDir
        lda SamusAccelY
        beq @onGround
        ldy SamusJumpDsp
        bit SamusSpeedY
        bmi @rising
        ; falling: unspin under 24 pixels of jump
        cpy #$18
        bcs @common
        lda #ObjAnim_SamusJump
        sta SamusAnimReset
        bcc @common
@rising:
        cpy #$18
        bcc @common
        lda SamusAnimReset
        cmp #ObjAnim_SamusJumpFire
        beq @noSpin
        lda #ObjAnim_SamusSalto
        sta SamusAnimReset
@noSpin:
        cpy #$20
        bcc @common
        lda Joy1Status
        and #BTN_UP
        beq @noAim
        lda #ObjAnim_SamusJumpPntUp
        sta SamusAnimReset
@noAim:
        bit Joy1Status
        bmi @common
        jsr StopVertMovement
@common:
        lda #ObjAnim_SamusRun
        cmp SamusAnimReset
        bne @notRun
        lda #ObjAnim_SamusJump
        sta SamusAnimReset
@notRun:
        jsr SamusRun_CheckHorzMovementMidair
        jsr SamusJump_CheckFire
        jsr LCF2E
        lda #$02
        jmp SetSamusData
@onGround:
        jsr SetSamusRunAccel
        jsr SamusRun_SetAnim
        dec WalkSoundDelay
        bne @noStep
        lda #$09
        sta WalkSoundDelay
        jsr SFX_SamusWalk
@noStep:
        jsr LCF2E
        lda Joy1Change
        bpl @noJump
        jsr SetSamusJump
        lda #$12
        sta SamusHorzMax
        jmp SetSamusData_3
@noJump:
        ora Joy1Retrig
        asl
        bpl @noFire
        jsr SamusRun_Fire
@noFire:
        lda Joy1Status
        and #BTN_RIGHT | BTN_LEFT
        bne @held
        jsr SetSamusStand
        jmp SetSamusData_3
@held:
        jsr BitScan
        cmp SamusDir
        beq SetSamusData_3
        sta SamusDir
        jsr SetSamusRun
SetSamusData_3:
        lda #$03

; Metroid's SetSamusData: animate (A = frames per animation frame), check
; health, move, and (here) take the frame's radii instead of drawing it.
SetSamusData:
        jsr UpdateObjAnim
        jsr CheckHealthStatus
        jsr LavaAndMoveCheck
        jmp SetSamusRadius

SamusRun_SetAnim:
        lda Joy1Status
        and #BTN_UP
        lsr
        lsr
        lsr
        tax
        lda RunAnimationTbl,x
        cmp SamusAnimReset
        beq @rts
        jsr SetSamusAnim
        pla
        pla
        jmp SetSamusData_3
@rts:
        rts

SamusRun_Fire:
        jsr FireSamusProjectile
        lda Joy1Status
        and #BTN_UP
        bne @up
        lda #ObjAnim_SamusRunFire
        sta SamusAnimIndex
        rts
@up:
        lda SamusAnimIndex
        sec
        sbc SamusAnimReset
        and #$03
        tax
        lda @table,x
        jmp SetSamusNextAnim
@table:
        .db ObjAnim_SamusRunPntUpFire3, ObjAnim_SamusRunPntUpFire1
        .db ObjAnim_SamusRunPntUpFire2, ObjAnim_SamusRunPntUpFire3

CheckHealthStatus:
        lda SamusIsHit
        and #$20
        beq @noHit
        lda #$32
        sta SamusInvincible
        lda #$FF
        sta SamusKnockDir
        lda SamusKnockBomb
        sta SamusKnockBomb77
        beq @noDir
        bpl @noSfx
        jsr SFX_SamusHit
@noSfx:
        lda SamusIsHit
        and #$08
        lsr
        lsr
        lsr
        sta SamusKnockDir
@noDir:
        lda #$FD
        sta SamusSpeedY
        lda #$38
        sta SamusAccelY
        jsr IsSamusDead
        bne @noHit
        jmp CheckHealthBeep
@noHit:
        lda SamusInvincible
        beq CheckHealthBeep
        dec SamusInvincible
        ldx SamusKnockDir
        inx
        beq @blink
        jsr Adiv16
        cmp #$03
        bcs @fast
        ldy SamusAccelX
        bne @blink
        jsr LCF4E
@fast:
        dex
        bne @right
        jsr TwosComplement
@right:
        sta SamusSpeedX
@blink:
        lda SamusKnockBomb77
        bpl CheckHealthBeep
        lda FrameCounter
        and #$01
        bne CheckHealthBeep
        tay
        sty SamusAnimDelay
        ldy #FrameNone
        sty SamusAnimFrame
CheckHealthBeep:
        ldy HealthHi
        dey
        bmi @beep
        bne @clear
        lda HealthLo
        cmp #$70
        bcs @clear
@beep:
        lda FrameCounter
        and #$0F
        bne @clear
        jsr SFX_Beep
@clear:
        lda #$00
        sta SamusIsHit
        rts

IsSamusDead:
        lda SamusStatus
        cmp #sa_Dead
        beq @rts
        cmp #sa_Dead2
        beq @rts
        cmp #sa_Begin
@rts:
        rts

SubtractHealth:
        lda HealthChangeLo
        ora HealthChangeHi
        beq @rts
        jsr IsSamusDead
        beq ClearHealthChange
        lda HealthLo
        sta Temp3
        lda HealthChangeLo
        sec
        jsr Base10Subtract
        sta HealthLo
        lda HealthHi
        sta Temp3
        lda HealthChangeHi
        jsr Base10Subtract
        sta HealthHi
        lda HealthLo
        and #$F0
        ora HealthHi
        beq @dead
        bcs ClearHealthChange
@dead:
        lda #$00
        sta HealthLo
        sta HealthHi
        lda #sa_Dead
        sta SamusStatus
        jsr SFX_SamusDie
        jmp ClearHealthChange
@rts:
        rts

AddHealth:
        lda HealthLo
        sta Temp3
        lda HealthChangeLo
        clc
        jsr Base10Add
        sta HealthLo
        lda HealthHi
        sta Temp3
        lda HealthChangeHi
        jsr Base10Add
        sta HealthHi
        ; no energy tanks: the maximum is 99
        lda #$0F
        cmp HealthHi
        bcs ClearHealthChange
        and #$F9
        sta HealthHi
        lda #$99
        sta HealthLo
ClearHealthChange:
        lda #$00
        sta HealthChangeLo
        sta HealthChangeHi
        rts

; Push away from a solid entity Samus touches (isHit bit 1). Castlevania's
; moving platforms never set it, so this is only ever the speed clear below.
LCF2E:
        lda SamusIsHit
        lsr
        and #$02
        beq RTS_X014
        bcs @fromRight
        lda SamusAccelX
        bmi RTS_X014
        bpl @flip
@fromRight:
        lda SamusAccelX
        bmi @flip
        bne RTS_X014
@flip:
        jsr TwosComplement
        sta SamusAccelX
ClearHorzMvmntData:
        ldy #$00
LCF4E:
        sty SamusSpeedX
        sty SamusSpeedSubX
RTS_X014:
        rts

SetSamusStand:
        lda SamusAccelX
        bne SetSamusStand_NoFootstep
        jsr SFX_SamusWalk
SetSamusStand_NoFootstep:
        jsr NoHorzMoveNoDelay
        sty SamusStatus
        lda Joy1Status
        and #BTN_UP
        bne SetSamusPntUp
        lda #ObjAnim_SamusStand
SetSamusAnim:
        sta SamusAnimReset
SetSamusNextAnim:
        sta SamusAnimIndex
        lda #$00
        sta SamusAnimDelay
        rts

SetSamusPntUp:
        lda #sa_PntUp
        sta SamusStatus
        lda #ObjAnim_SamusPntUp
        jsr SetSamusAnim
NoHorzMoveNoDelay:
        jsr StopHorzMovement
        sty SamusAnimDelay
        rts

SamusRun_CheckHorzMovementMidair:
        lda Joy1Status
        and #BTN_RIGHT | BTN_LEFT
        beq @none
        jsr BitScan
        tax
        jsr SetSamusRunAccel
        lda SamusAccelY
        bmi StopHorzMovement_rts
        lda SamusAnimReset
        cmp #ObjAnim_SamusSalto
        beq StopHorzMovement_rts
        stx SamusDir
        lda Table06+1,x
        jmp SetSamusAnim
@none:
        lda SamusAccelY
        bmi StopHorzMovement_rts
        beq StopHorzMovement_rts
        lda SamusAnimReset
        cmp #ObjAnim_SamusJump
        bne StopHorzMovement_rts
StopHorzMovement:
        jsr ClearHorzMvmntData
        sty SamusAccelX
StopHorzMovement_rts:
        rts

SetSamusJumpPntUp:
        ldy #ObjAnim_SamusJumpPntUp
        jmp LCFC5
SetSamusJump:
        ldy #ObjAnim_SamusJump
LCFC5:
        sty SamusAnimReset
        dey
        sty SamusAnimIndex
        lda #$04
        sta SamusAnimDelay
        lda #$00
        sta SamusJumpDsp
        lda #$FC
        sta SamusSpeedY
        jsr SFX_SamusJump
        ldy #$18                ; gravity without the high jump boots
        sty SamusAccelY
        rts

SamusJump:
        lda SamusJumpDsp
        bit SamusSpeedY
        bpl @move
        cmp #$20
        bcc @move
        bit Joy1Status
        bmi @move
        jsr StopVertMovement
@move:
        jsr SamusJump_CheckHorzMovement
        jsr LCF2E
        lda Joy1Status
        and #BTN_UP
        beq @noUp
        lda #ObjAnim_SamusJumpPntUp
        sta SamusAnimReset
        lda #sa_PntJump
        sta SamusStatus
@noUp:
        jsr SamusJump_CheckFire
        lda SamusAccelY
        bne @air
        lda SamusStatus
        cmp #sa_PntJump
        bne @stand
        jsr SetSamusPntUp
        bne @air
@stand:
        jsr SetSamusStand
@air:
        lda #$03
        jmp SetSamusData

SamusJump_CheckHorzMovement:
        ldx #$01
        ldy #$00
        lda Joy1Status
        lsr
        bcs @dir
        dex
        lsr
        bcc @done
        dex
        iny
@dir:
        cpy SamusDir
        beq @done
        lda SamusStatus
        cmp #sa_PntJump
        bne @notUp
        lda SamusAnimReset
        cmp Table04,y
        bne @anim
        lda Table04+1,y
        jmp @anim
@notUp:
        lda SamusAnimReset
        cmp Table06,y
        bne @anim
        lda Table06+1,y
@anim:
        jsr SetSamusAnim
        lda #$08
        sta SamusAnimDelay
        sty SamusDir
@done:
        stx SamusSpeedX
        rts

Table06:
        .db ObjAnim_SamusJump, ObjAnim_SamusJump, ObjAnim_SamusJump
Table04:
        .db ObjAnim_SamusJumpPntUp, ObjAnim_SamusJumpPntUp, ObjAnim_SamusJumpPntUp

SamusJump_CheckFire:
        lda Joy1Change
        ora Joy1Retrig
        asl
        bpl @rts
        lda SamusAnimReset
        cmp #ObjAnim_SamusJumpPntUp
        bne @forward
        jmp FireSamusProjectileUpwards
@forward:
        jsr FireSamusProjectileForwards
        lda #ObjAnim_SamusJumpFire
        jmp SetSamusAnim
@rts:
        rts

; Samus has the Maru Mari from the start.
SetSamusRoll:
        lda SamusAccelY
        bne @no
        ldx SamusDir
        lda #ObjAnim_SamusRoll
        sta SamusAnimReset
        lda #ObjAnim_SamusRunJump
        sta SamusAnimIndex
        lda RunAccelerationTbl,x
        sta SamusAccelX
        jmp SFX_SamusBall
@no:
        lda #sa_Stand
        sta SamusStatus
        rts

SamusRoll:
        lda Joy1Change
        and #BTN_UP
        bne @tryStand
        bit Joy1Change
        bpl @ball
@tryStand:
        lda Joy1Status
        and #BTN_DOWN
        bne @ball
        ; break out of the ball, if there is room to stand
        lda SamusRadiusY
        clc
        adc #$08
        sta SamusRadiusY
        jsr ObjectCheckMoveUp
        bcc @ball
        lda SamusY
        sec
        sbc #$0B
        sta SamusY
        jsr SetSamusStand
        dec SamusAnimIndex
        jsr StopVertMovement
        lda #$04
        jmp SetSamusData
@ball:
        lda Joy1Change
        jsr BitScan
        cmp #BUTTONBIT_DOWN
        bcs @noTurn
        sta SamusDir
        lda #ObjAnim_SamusRoll
        jsr SetSamusAnim
@noTurn:
        ldx SamusDir
        jsr SetSamusRunAccel
        jsr LCF2E
        jsr CheckBombLaunch
        lda Joy1Status
        and #BTN_RIGHT | BTN_LEFT
        bne @moving
        jsr StopHorzMovement
@moving:
        lda #$02
        jmp SetSamusData

StopVertMovement:
        ldy #$00
        sty SamusSpeedY
        sty SamusSpeedSubY
        rts

SamusPntUp:
        lda Joy1Status
        and #BTN_UP
        bne @up
        lda #sa_Stand
        sta SamusStatus
@up:
        lda Joy1Status
        and #BTN_DOWN | BTN_LEFT | BTN_RIGHT
        beq @fire
        jsr BitScan
        cmp #BUTTONBIT_DOWN
        bcs @noDir
        sta SamusDir
@noDir:
        tax
        lda @statusTable,x
        sta SamusStatus
@fire:
        lda Joy1Change
        ora Joy1Retrig
        asl
        bpl @jump
        jsr FireSamusProjectile
@jump:
        bit Joy1Change
        bpl @data
        lda #sa_PntJump
        sta SamusStatus
@data:
        lda #$04
        jsr SetSamusData
        lda SamusStatus
        asl
        tax
        lda @next+1,x
        pha
        lda @next,x
        pha
        rts
@next:
        .dw SetSamusStand-1, SetSamusRun-1, NoOp-1, SetSamusRoll-1, NoOp-1
        .dw NoOp-1, SetSamusJumpPntUp-1, NoOp-1, NoOp-1, NoOp-1
@statusTable:
        .db sa_Run, sa_Run, sa_Roll

; ---- Animation -----------------------------------------------------------------

; A = frames to show each animation frame for.
UpdateObjAnim:
        ldy SamusAnimDelay
        beq @next
        dec SamusAnimDelay
        bne @rts
@next:
        sta SamusAnimDelay
        ldy SamusAnimIndex
@get:
        lda ObjectAnimIndexTbl,y
        cmp #FrameEnd
        beq @reset
        sta SamusAnimFrame
        iny
        sty SamusAnimIndex
@rts:
        rts
@reset:
        ldy SamusAnimReset
        jmp @get

; ObjDrawFrame reads the radii from the frame it draws; a blinking Samus
; keeps the last ones.
SetSamusRadius:
        ldx SamusAnimFrame
        cpx #FrameCount
        bcs @rts
        lda FrameRadY,x
        beq @rts
        sta SamusRadiusY
        lda FrameRadX,x
        sta SamusRadiusX
@rts:
        rts

; ---- Movement --------------------------------------------------------------------

; Castlevania has no lava. What is left is SamusMoveVertically and
; SamusMoveHorizontally.
LavaAndMoveCheck:
        lda SamusStatus
        cmp #sa_Dead
        bcc SamusMoveVertically
        rts
SamusMoveVertically:
        jsr VertAccelerate
        lda Temp0
        bpl @down
        jsr TwosComplement
        sta MoveCount
@up:
        jsr MoveSamusUp
        bcs @movedUp
        sec
        ror SamusSpeedY
        ror SamusSpeedSubY
        jmp SamusMoveHorizontally
@movedUp:
        dec MoveCount
        bne @up
@down:
        beq SamusMoveHorizontally
        sta MoveCount
@downLoop:
        jsr MoveSamusDown
        bcs @movedDown
        lda SamusStatus
        cmp #sa_Roll
        bne @landed
        lsr SamusSpeedY
        beq @landedNoBounce
        ror SamusSpeedSubY
        lda #$00
        sec
        sbc SamusSpeedSubY
        sta SamusSpeedSubY
        lda #$00
        sbc SamusSpeedY
        sta SamusSpeedY
        jmp SamusMoveHorizontally
@landed:
        jsr SFX_SamusWalk
@landedNoBounce:
        jsr StopVertMovement
        sty SamusAccelY
        beq SamusMoveHorizontally
@movedDown:
        dec MoveCount
        bne @downLoop
SamusMoveHorizontally:
        jsr HorzAccelerate
        lda Temp0
        bpl @right
        jsr TwosComplement
        sta MoveCount
@left:
        jsr MoveSamusLeft
        jsr CheckStopHorzMvmt
        dec MoveCount
        bne @left
@rts:
        rts
@right:
        beq @rts
        sta MoveCount
@rightLoop:
        jsr MoveSamusRight
        jsr CheckStopHorzMvmt
        dec MoveCount
        bne @rightLoop
        rts

CheckStopHorzMvmt:
        bcs @rts
        lda #$01
        sta MoveCount
        lda SamusAccelY
        bne @rts
        lda SamusStatus
        cmp #sa_Roll
        beq @rts
        jmp SetSamusStand
@rts:
        rts

; Gravity: $38 hit, $1A falling, $18 jumping.
VertAccelerate:
        lda SamusAccelY
        bne @air
        lda #$18
        sta SamusHorzMax
        lda SamusY
        clc
        adc SamusRadiusY
        and #$07
        bne @fall
        jsr ObjectCheckMoveDown
        bcc @air
@fall:
        lda #$1A
        sta SamusAccelY
@air:
        ldx #$05
        lda SamusSpeedSubY
        clc
        adc SamusAccelY
        sta SamusSpeedSubY
        lda SamusSpeedY
        adc #$00
        sta SamusSpeedY
        bpl @downward
        lda #$00
        cmp SamusSpeedSubY
        sbc SamusSpeedY
        cmp #$06
        ldx #$FA
        bne @cap
@downward:
        cmp #$05
@cap:
        bcc @apply
        jsr StopVertMovement
        stx SamusSpeedY
@apply:
        lda SamusSubY
        clc
        adc SamusSpeedSubY
        sta SamusSubY
        lda #$00
        adc SamusSpeedY
        sta Temp0
        rts

HorzAccelerate:
        lda SamusHorzMax
        jsr Amul16
        sta Temp0
        sta Temp2
        lda SamusHorzMax
        jsr Adiv16
        sta Temp1
        sta Temp3
        lda SamusSpeedSubX
        clc
        adc SamusAccelX
        sta SamusSpeedSubX
        tax
        lda #$00
        bit SamusAccelX
        bpl @pos
        lda #$FF
@pos:
        adc SamusSpeedX
        sta SamusSpeedX
        tay
        bpl @right
        lda #$00
        sec
        sbc SamusSpeedSubX
        tax
        lda #$00
        sbc SamusSpeedX
        tay
        lda #$00
        sec
        sbc Temp0
        sta Temp0
        lda #$00
        sbc Temp1
        sta Temp1
@right:
        cpx Temp2
        tya
        sbc Temp3
        bcc @under
        lda Temp0
        sta SamusSpeedSubX
        lda Temp1
        sta SamusSpeedX
@under:
        lda SamusSubX
        clc
        adc SamusSpeedSubX
        sta SamusSubX
        lda #$00
        adc SamusSpeedX
        sta Temp0
        rts

MoveSamusUp:
        lda SamusY
        sec
        sbc SamusRadiusY
        and #$07
        bne @free
        jsr ObjectCheckMoveUp
        bcc @rts
@free:
        dec SamusY
        inc SamusJumpDsp
        sec
@rts:
        rts

MoveSamusDown:
        lda SamusY
        clc
        adc SamusRadiusY
        and #$07
        bne @free
        jsr ObjectCheckMoveDown
        bcc @rts
@free:
        lda SamusY
        cmp #$FF                ; fell out of the level: Castlevania kills her
        beq @rts
        inc SamusY
        dec SamusJumpDsp
        sec
@rts:
        rts

; Moving one pixel sideways scrolls the level instead while Samus is outside
; the middle of the screen ($71-$8F), as in Metroid, until the level ends.
MoveSamusLeft:
        lda SamusXLo
        sec
        sbc SamusRadiusX
        and #$07
        bne @free
        jsr ObjectCheckMoveLeft
        bcc @rts
@free:
        jsr SamusScreenX
        cmp #$71
        bcs @walk
        jsr ScrollLeft1
        bcc @moved
        jsr SamusScreenX        ; it can't scroll (the level's start, a boss): walk
@walk:
        cmp #$08 + 2            ; the screen's edges are Simon's ($98CB, $98E9):
                                ; he stops short of $08 and $F0
        bcc @blocked
@moved:
        lda SamusXLo
        bne @lo
        dec SamusXHi
@lo:
        dec SamusXLo
        sec
@rts:
        rts
@blocked:
        clc
        rts

MoveSamusRight:
        lda SamusXLo
        clc
        adc SamusRadiusX
        and #$07
        bne @free
        jsr ObjectCheckMoveRight
        bcc @rts
@free:
        jsr SamusScreenX
        cmp #$8F
        bcc @walk
        jsr ScrollRight1
        bcc @moved
        jsr SamusScreenX
@walk:
        cmp #$F0 - 1
        bcs @blocked
@moved:
        inc SamusXLo
        bne @rts1
        inc SamusXHi
@rts1:
        sec
@rts:
        rts
@blocked:
        clc
        rts

; A = Samus's x on screen
SamusScreenX:
        lda SamusXLo
        sec
        sbc ScrollLo
        rts

; Metroid's camera only moves when Samus does, so she stays where she is on
; the screen. But Castlevania moves her on the screen, not the screen, up the
; stairs: she comes off them as far over as $F0, with nothing to see ahead of
; her, and a stage's exit (on the screen, at the last scroll) out of reach.
; Outside the middle, the screen catches up a pixel a frame.
RecentreCamera:
        jsr SamusScreenX
        cmp #$71
        bcc @left
        cmp #$8F + 1
        bcc @rts
        jmp ScrollRight1
@left:
        jmp ScrollLeft1
@rts:
        rts

; Scroll one pixel, as Castlevania's MovingRightA/MovingLeftA would with a
; speed of 1. Carry clear if it scrolled. The limits are the ones
; Castlevania's walking code checks ($9849-$9897): the stage's last screen
; ($D015) and the screen before its first ($D025), and none while a boss
; locks the screen.
ScrollRight1:
        lda BossLock
        bne @no
        jsr CvMaxScreen
        cmp ScrollHi
        bne @ok
        lda ScrollLo
        beq @no
@ok:
        inc ScrollLo
        bne @hi
        inc ScrollHi
@hi:
        jsr CheckBossLock
        dec ScrollDelta
        lda #1
        sta MoveDir
        jsr LoadColumn
        clc
        rts
@no:
        sec
        rts

; Castlevania loads each 64 pixel column's enemy generator and candles as it
; scrolls into view ($D196, by MoveDir), when a frame ends with the scroll on
; a column's edge ($F5EA). Simon scrolls a pixel a frame and never misses
; one; Samus can scroll two and step over an edge (and the zombies of the
; hall before the Phantom Bat came on into its fight), so the edges are
; looked for at every pixel. Castlevania doesn't load a column twice.
LoadColumn:
        lda ScrollLo
        and #$3F
        bne @rts
        jmp CvLoadColumn
@rts:
        rts

; Castlevania's StrangeCode19 ($9967), from Simon's moving code, every
; frame: the screen locks for the boss when it is at exactly the boss's
; screen (the table at $FC5E: floor in the high nibble, screen in the low
; one), whichever way it got there. Simon scrolls a pixel a frame; Samus is
; checked every frame and at every pixel she scrolls, so she can't scroll
; past it.
BossScreens = $FC5E
CheckBossLock:
        lda BossLock
        bne @rts
        lda ScrollLo
        bne @rts
        ldx CurrentStage
        lda BossScreens,x
        lsr
        lsr
        lsr
        lsr
        cmp Floor
        bne @rts
        lda BossScreens,x
        and #$0F
        cmp ScrollHi
        bne @rts
        lda #$3F
        sta $60
        cpx #$12
        beq @lock
        lda #$01                ; the music fades for the boss's
        sta $E2
@lock:
        lda #$01
        sta BossLock
@rts:
        rts

ScrollLeft1:
        lda BossLock
        bne @no
        ldy ScrollHi
        lda ScrollLo
        bne @same
        dey
@same:
        sty Temp1
        jsr CvMinScreen
        cmp Temp1
        beq @no
        lda ScrollLo
        bne @lo
        dec ScrollHi
@lo:
        dec ScrollLo
        jsr CheckBossLock
        inc ScrollDelta
        lda #2
        sta MoveDir
        jsr LoadColumn
        clc
        rts
@no:
        sec
        rts

; ---- Collision ----------------------------------------------------------------------
; Metroid's ObjectCheckMove*: carry clear if Samus can't move that way. Only
; when her edge is on an 8 pixel line are the 8x8 cells beyond it looked at.

ObjectCheckMoveUp:
        lda SamusRadiusY
        clc
        adc #$08
        jmp ObjectCheckMoveVertical

ObjectCheckMoveDown:
        jsr PlatformBelow
        bcs @ground
        lda #$00
        sec
        sbc SamusRadiusY
        jsr ObjectCheckMoveVertical
        bcc @rts
        ; The holes stairs make in a floor are one cell wide, and so is she:
        ; right over one she would fall through (she once did, coming off stage
        ; 7's first stairs, to her death), though Simon's feet are too far apart
        ; to. With floor on both sides, it is floor.
        lda ColY
        and #$07
        bne @free
        lda SamusRadiusX
        cmp #$04
        bne @free
        lda SamusXLo
        sec
        sbc #$0C
        sta ColXLo
        and #$07
        bne @free
        lda SamusXHi
        sbc #0
        sta ColXHi
        jsr SolidCell
        beq @free
        lda ColXLo
        clc
        adc #$10
        sta ColXLo
        bcc @right
        inc ColXHi
@right:
        jsr SolidCell
        beq @free
@ground:
        clc
@rts:
        rts
@free:
        sec
        rts

ObjectCheckMoveVertical:
        ; the row: y - A
        eor #$FF
        sec
        adc SamusY
        sta ColY
        and #$07
        bne @free
        ; the cells from x - radius to x + radius - 1
        lda SamusXLo
        sec
        sbc SamusRadiusX
        sta ColXLo
        lda SamusXHi
        sbc #0
        sta ColXHi
        ldx ColXLo
        lda SamusRadiusX
        asl
        jsr CellsSpanned
        sta ColCount
@loop:
        jsr SolidCell
        bne @blocked
        dec ColCount
        beq @free
        lda ColXLo
        clc
        adc #8
        sta ColXLo
        bcc @loop
        inc ColXHi
        bcs @loop
@free:
        sec
        rts
@blocked:
        clc
        rts

ObjectCheckMoveLeft:
        lda SamusRadiusX
        clc
        adc #$08
        jmp ObjectCheckMoveHorizontal

ObjectCheckMoveRight:
        lda #$00
        sec
        sbc SamusRadiusX
ObjectCheckMoveHorizontal:
        ; the column: x - A (A is signed)
        sta Temp0
        lda SamusXLo
        sec
        sbc Temp0
        sta ColXLo
        lda SamusXHi
        bit Temp0
        bmi @neg
        sbc #0
        jmp @hi
@neg:
        sbc #$FF
@hi:
        sta ColXHi
        lda ColXLo
        and #$07
        bne @free
        ; the rows from y - radius to y + radius - 1
        lda SamusY
        sec
        sbc SamusRadiusY
        sta ColY
        tax
        lda SamusRadiusY
        asl
        jsr CellsSpanned
        sta ColCount
@loop:
        jsr SolidCell
        bne @blocked
        dec ColCount
        beq @free
        lda ColY
        clc
        adc #8
        sta ColY
        bcc @loop
@free:
        sec
        rts
@blocked:
        clc
        rts

; Castlevania's moving platforms (stages 4, 5 and 10: AI 1 in slots
; $17-$1A, drawn 32 pixels wide around ObjX, their top at ObjY) are ground
; too. Carry set if Samus's feet are on one; RideSlot is then that one.
PlatformBelow:
        ldx CurrentStage
        lda PlatformStages,x
        bne @stage
        clc
        rts
@stage:
        ldx #$17
@loop:
        lda ObjAI,x
        cmp #1
        bne @next
        lda ObjPose,x
        cmp #CV_PLATFORM_POSE
        bne @next
        lda SamusY
        clc
        adc SamusRadiusY
        cmp ObjY,x
        bne @next
        ; overlap: |Samus's x on screen - ObjX| < 16 + her radius. ObjX is
        ; where the platform was put after last frame's scrolling: compare
        ; with the scroll as it was then (Samus may have scrolled since;
        ; ScrollDelta is by how much, backwards).
        jsr SamusScreenX
        sec
        sbc ScrollDelta
        sec
        sbc ObjX,x
        bcs @pos
        eor #$FF
        adc #1
@pos:
        sec
        sbc SamusRadiusX
        bcc @on
        cmp #16
        bcs @next
@on:
        stx RideSlot
        lda ObjX,x
        clc
        adc ScrollLo
        clc
        adc ScrollDelta
        sta RideLastX
        sec
        rts
@next:
        inx
        cpx #$1B
        bne @loop
        clc
        rts

PlatformStages:
        .db 0,0,0,0,1,1,0,0,0,0,1,0,0,0,0,0,0,0,0,0

; Standing on a platform, Samus moves with it (before her own movement).
; Sideways only her lower half meets walls: stage 10's platform carries Simon
; under a rock that leaves less than Samus's height above it (his head never
; meets walls), and she would be scraped off into the water.
RidePlatform:
        ldx RideSlot
        beq @rts
        lda #0
        sta RideSlot
        lda SamusAccelY
        bne @rts                ; she left it
        lda ObjAI,x
        cmp #1
        bne @rts
        ; up or down with it
        lda ObjY,x
        sec
        sbc SamusRadiusY
        sta SamusY
        ; sideways: how far it moved in the level
        lda ObjX,x
        clc
        adc ScrollLo
        tay
        sec
        sbc RideLastX
        beq @rts
        sta MoveCount
        lda SamusY
        pha
        lda SamusRadiusY
        pha
        clc
        adc SamusY
        sec
        sbc #8
        sta SamusY
        lda #8
        sta SamusRadiusY
        lda MoveCount
        bmi @left
@right:
        jsr MoveSamusRight
        dec MoveCount
        bne @right
        beq @done
@left:
        eor #$FF
        clc
        adc #1
        sta MoveCount
@leftLoop:
        jsr MoveSamusLeft
        dec MoveCount
        bne @leftLoop
@done:
        pla
        sta SamusRadiusY
        pla
        sta SamusY
@rts:
        rts

; A = a length from X on: how many 8 pixel cells it touches.
CellsSpanned:
        sta Temp0
        txa
        and #$07
        clc
        adc Temp0
        adc #$07
        lsr
        lsr
        lsr
        rts

; Z clear if the 8x8 cell at ColXHi:ColXLo, ColY is solid. Above the
; playfield counts as solid (Samus jumps far higher than Simon, and mustn't
; leave it), below it as empty. Except below her middle: then she is above
; the playfield herself, coming in from the top (down the shaft into stage
; 10, where Castlevania drops Simon in at y 0), and falls in.
SolidCell:
        lda DebugFlags
        bmi @empty
        lda ColY
        cmp #$30
        bcs @field
        cmp SamusY
        bcs @empty
        bcc @solid
@field:
        cmp #$E0
        bcs @empty
        sta $10
        lda #0
        sta $11
        lda ColXLo
        sta $12
        lda ColXHi
        sta $13
        jsr SolidAt
        lda $14
        rts
@solid:
        lda #1
        rts
@empty:
        lda #0
        rts

; ---- Weapons -------------------------------------------------------------------------

FireSamusProjectile:
        lda Joy1Status
        and #BTN_UP
        beq FireSamusProjectileForwards
        jmp FireSamusProjectileUpwards

; Y = a free projectile (0-2), Z set if there is one. Missiles only use
; slot 0, as Metroid's only use $03D0.
SearchOpenSamusProjectileSlot:
        ldy #0
@loop:
        lda BulStatus,y
        beq @found
        iny
        cpy #3
        bne @loop
        tya                     ; none: Z clear (cpy left it set)
        rts
@found:
        lda MissileToggle
        beq @rts
        cpy #0
@rts:
        rts

FireSamusProjectileForwards:
        jsr SearchOpenSamusProjectileSlot
        bne @exit
        jsr InitBullet
        lda #$0C
        sta BulDie,y
        ldx SamusDir
        lda BulletSpeedXTable,x
        sta BulSpeedX,y
        lda #$00
        sta BulSpeedY,y
        jsr CheckHorizontalMissileLaunch
        ; at the arm cannon
        lda BulStatus,y
        asl
        ora SamusDir
        and #$03
        tax
        lda BulletForwardsOffsetXTable,x
        sta Temp0
        lda #-$06
        sta Temp1
        jsr PlaceBulletAtArmCannon
        lda BulStatus,y
        cmp #wa_RegularBeam
        bne @exit
        jsr SFX_BulletFire
@exit:
        lda #ObjAnim_SamusStandFire
        jmp SetSamusNextAnim

BulletForwardsOffsetXTable:
        .db $0C, -$0C, $08, -$08
BulletSpeedXTable:
        .db $04, -$04

FireSamusProjectileUpwards:
        jsr SearchOpenSamusProjectileSlot
        bne @exit
        jsr InitBullet
        lda #$0C
        sta BulDie,y
        lda #$FC
        sta BulSpeedY,y
        lda #$00
        sta BulSpeedX,y
        jsr CheckVerticalMissileLaunch
        ldx SamusDir
        lda BulletUpwardsOffsetXTable,x
        sta Temp0
        lda BulStatus,y
        and #$01
        tax
        lda BulletUpwardsOffsetYTable,x
        sta Temp1
        jsr PlaceBulletAtArmCannon
        lda BulStatus,y
        cmp #wa_RegularBeam
        bne @exit
        jsr SFX_BulletFire
@exit:
        ldx SamusDir
        ldy StandAimUpFireAnimTbl,x
        lda SamusAccelY
        beq @stand
        ldy AimUpFireMidairAnimTbl,x
@stand:
        lda SamusStatus
        cmp #sa_Run
        beq @rts
        tya
        jmp SetSamusNextAnim
@rts:
        rts

StandAimUpFireAnimTbl:
        .db ObjAnim_SamusPntUpFire, ObjAnim_SamusPntUpFire
AimUpFireMidairAnimTbl:
        .db ObjAnim_SamusJumpPntUpFire, ObjAnim_SamusJumpPntUpFire
BulletUpwardsOffsetXTable:
        .db $01, -$01
BulletUpwardsOffsetYTable:
        .db -$14, -$10

InitBullet:
        lda #wa_RegularBeam
        sta BulStatus,y
        lda #ObjAnim_RegularBullet
SetBulletAnim:
        sta BulAnimReset,y
        sta BulAnimIndex,y
        tax
        lda ObjectAnimIndexTbl,x
        sta BulAnimFrame,y
        lda #$00
        sta BulAnimDelay,y
        rts

; Temp0 = dx, Temp1 = dy from Samus's centre.
PlaceBulletAtArmCannon:
        lda SamusY
        clc
        adc Temp1
        sta BulY,y
        lda Temp0
        bmi @neg
        clc
        adc SamusXLo
        sta BulXLo,y
        lda SamusXHi
        adc #0
        sta BulXHi,y
        jmp @cv
@neg:
        clc
        adc SamusXLo
        sta BulXLo,y
        lda SamusXHi
        adc #$FF
        sta BulXHi,y
        jmp @cv
@cv:
        tya
        tax
        jmp CvShotSync

NoMissile:
        rts

CheckHorizontalMissileLaunch:
        lda MissileToggle
        beq NoMissile
        cpy #0
        bne NoMissile
        ldx SamusDir
        lda HorizontalMissileAnims,x
CheckMissileLaunchCommon:
        jsr SetBulletAnim
        jsr SFX_MissileLaunch
        lda #wa_Missile
        sta BulStatus,y
        lda #$FF
        sta BulDie,y
        ; a missile costs a heart
        dec Hearts
        bne @rts
        dec MissileToggle
        jmp SelectSamusPalette
@rts:
        rts

HorizontalMissileAnims:
        .db ObjAnim_MissileRight, ObjAnim_MissileLeft

CheckVerticalMissileLaunch:
        lda MissileToggle
        beq @rts
        cpy #0
        bne @rts
        lda #ObjAnim_MissileUp
        bne CheckMissileLaunchCommon
@rts:
        rts

; Select toggles missiles, while there are hearts to fire.
CheckMissileToggle:
        lda Hearts
        beq @rts
        lda Joy1Change
        ora Joy1Retrig
        and #BTN_SELECT
        beq @rts
        lda MissileToggle
        eor #$01
        sta MissileToggle
        jmp SelectSamusPalette
@rts:
        rts

; ---- Helpers -----------------------------------------------------------------------

TwosComplement:
        eor #$FF
        clc
        adc #$01
        rts

Amul16:
        asl
        asl
        asl
        asl
        rts

Adiv16:
        lsr
        lsr
        lsr
        lsr
        rts

BitScan:
        stx Temp3
        ldx #$00
@loop:
        lsr
        bcs @done
        inx
        cpx #$08
        bne @loop
@done:
        txa
        ldx Temp3
        rts

; BCD: Temp3 +/- A; see Metroid's Base10Add. Temp1/Temp2 are the nibbles.
Base10Add:
        jsr ExtractNibbles
        adc Temp1
        cmp #$0A
        bcc @lo
        adc #$05
@lo:
        clc
        adc Temp2
        sta Temp2
        lda Temp3
        and #$F0
        adc Temp2
        bcc @noCarry
@carry:
        adc #$5F
        sec
        rts
@noCarry:
        cmp #$A0
        bcs @carry
        rts

Base10Subtract:
        jsr ExtractNibbles
        sbc Temp1
        sta Temp1
        bcs @hi
        adc #$0A
        sta Temp1
        lda Temp2
        adc #$0F
        sta Temp2
@hi:
        lda Temp3
        and #$F0
        sec
        sbc Temp2
        bcs @done
        adc #$A0
        clc
@done:
        ora Temp1
        rts

ExtractNibbles:
        pha
        and #$0F
        sta Temp1
        pla
        and #$F0
        sta Temp2
        lda Temp3
        and #$0F
        rts
