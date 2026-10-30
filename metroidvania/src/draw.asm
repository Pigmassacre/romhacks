; Drawing Samus with Castlevania's sprite allocator.
;
; Castlevania fills sprite RAM from $0244 on (sprites 0-16 are its status
; bar's), starting at a different sprite each frame so that crowded lines
; flicker instead of dropping the same sprites. $04 is the next sprite's
; offset and $07 how many are left. Each object's sprites go at $04, which
; then steps by $C4 (mod $100, skipping $00-$43).

OamPos          = $04
OamLeft         = $07

; Carry set if slot 0 is Samus and the hack draws it: Castlevania's sprite
; loop then starts at slot 1. Clear where slot 0 is something else: the
; title's bat, the castle falling in the ending.
DrawAll:
        jsr RestoreFont
        jsr RestoreSamusChr
        lda GameMode
        cmp #2
        beq @game               ; the attract demo: Samus plays it
        cmp #4
        bcs @notTitle
        jsr NewGame             ; the title
        jsr HideHud             ; (the demo left it up)
        clc
        rts
@notTitle:
        cmp #$0F
        bcc @game
        lda #$F8                ; the ending: no status bar, so no sprite 0
        sta $0200
        jsr HideHud
        clc
        rts
@game:
        cmp #$0E                ; down the shaft: no status bar, no sprite 0
        bne @split
        lda #$F8
        sta $0200
        bne @sprite0
@split:
        jsr $C13F               ; sprite 0 (main.asm)
@sprite0:
        jsr InPlay              ; where Castlevania has its status bar: play
        beq @hud                ; (not while a stage or a floor loads),
        lda GameMode
        cmp #8                  ; doors, walking in, climbing to the next stage,
        bcc @hideHudMode
        cmp #$0C
        bcc @hud
        bne @hideHudMode
        lda GameModeAux         ; and a stage's end, until the screen goes dark
        cmp #8
        bcc @hud
@hideHudMode:
        jsr HideHud             ; (every frame: cheap enough, with no HUD to draw)
        jmp @noHud
@hud:
        jsr DrawHud
@noHud:
        ; a whip upgrade stops the game a moment and flashes Simon through the
        ; palettes ($FAEF): Samus too, or it just looks like a hang
        lda WhipFlash
        beq @attr
        lda ObjPal
        and #3
@attr:
        sta DrawAttr
        jsr InPlay              ; Samus's own handlers only run in play
        beq @inPlay
        jsr ClearShots
        lda HackState
        and #~HS_SAMUS
        sta HackState
@inPlay:
        lda HackState
        and #HS_SAMUS
        bne @samus
        jsr FollowSimon
        bcc @draw
        jmp @shots              ; hidden, as Simon is
@samus:
        lda SamusXLo
        sec
        sbc ScrollLo
        sta DrawX
        lda SamusY
        sta DrawY
        lda SamusDir
        sta DrawDir
@draw:
        ; while enemies can't touch her (after a hit, or the invisibility
        ; potion), she blinks, as Simon does ($9BC2): on even frames, as
        ; Metroid's own blink after a hit
        lda Invincible
        beq @shown
        lda FrameCounter
        and #$01
        beq @shots
@shown:
        lda SamusAnimFrame
        jsr DrawFrame
@shots:
        lda #0
        sta DrawDir
        ldx #2
@shot:
        lda BulStatus,x
        beq @next
        stx $05                 ; free until the object loop starts
        jsr BulletScreenX
        bcs @next1
        sta DrawX
        lda BulY,x
        sta DrawY
        lda BulAnimFrame,x
        jsr DrawFrame
@next1:
        ldx $05
@next:
        dex
        bpl @shot
        sec
        rts

; Z set in play: mode 5, part 6, or the attract demo (mode 2, part 1).
InPlay:
        lda GameMode
        cmp #2
        beq @demo
        cmp #5
        bne @rts
        lda GameModeAux
        cmp #6
@rts:
        rts
@demo:
        lda GameModeAux
        cmp #1
        rts

; On the title: whatever the demo or the last game left, Samus starts the
; next one afresh (ImportSimon does the rest).
NewGame:
        jsr FillHealth
        lda #0
        sta MissileToggle
        lda HackState
        and #~HS_SAMUS
        sta HackState
        rts

; Castlevania is moving Simon (walking in, through a door, up stairs):
; Samus is where he is, running while he moves. Carry set: she is hidden.
; Castlevania moves Simon up stairs a pixel every other frame, so she only
; stands still once he has been still for two frames.
FollowStill     = SamusJumpDsp  ; frames Simon has not moved (Samus's own is not current)

FollowSimon:
        lda ObjX
        sta DrawX
        ldx ObjY
        inx
        stx DrawY
        lda ObjFacing
        and #1
        sta DrawDir
        sta SamusDir
        lda ObjAction
        cmp #8
        bne @alive
        pla                     ; dying: SamusDeath draws her instead
        pla
        jsr SamusDeath
        sec
        rts
@alive:
        lda ObjPose
        cmp #$19                ; at the castle gate, his back to us
        bne @notGate
        lda #ObjFrame_SamusFront
        sta SamusAnimFrame
        clc
        rts
@notGate:
        lda GameMode
        cmp #8
        bne @shown
        lda GameModeAux
        cmp #2
        beq @shown              ; walking through it
        bcs @stand              ; after it, the scroll carries her: standing, as Simon
        sec                     ; at a door: hidden, as Simon is, while the screen
        rts                     ; scrolls to it and it opens
@shown:
        lda ObjX
        cmp FollowX
        bne @moved
        lda ObjY
        cmp FollowY
        beq @still
        ldx ObjAction           ; straight down, not on the stairs: falling
        cpx #4                  ; (down the shaft into stage 10), in the air
        beq @moved
        cpx #6
        beq @moved
        sta FollowY
        lda #0
        sta FollowStill
        lda #ObjAnim_SamusJump
        sta SamusAnimReset
        lda #ObjFrame_SamusJump
        sta SamusAnimFrame
        clc
        rts
@moved:
        lda ObjX
        sta FollowX
        lda ObjY
        sta FollowY
        lda #0
        sta FollowStill
@run:
        lda SamusAnimReset
        cmp #ObjAnim_SamusRun
        beq @anim
        lda #ObjAnim_SamusRun
        jsr SetSamusAnim
@anim:
        lda #3
        ldx ObjAction
        cpx #4
        bne @delay
        lda #6                  ; on the stairs: slower, as Simon climbs
@delay:
        jsr UpdateObjAnim
        clc
        rts
@still:
        lda FollowStill
        cmp #2
        bcs @stand
        inc FollowStill
        bcc @run
@stand:
        lda #ObjAnim_SamusStand
        sta SamusAnimReset
        lda #ObjFrame_SamusStand
        sta SamusAnimFrame
        clc
        rts

; Draw Metroid frame A at DrawX, DrawY (screen), facing left when DrawDir
; is 1. Each sprite is: dy, tile, attributes, dx. Samus's frames reach 32
; pixels from her centre at most, so while she is that far inside the screen
; nothing can wrap, and the sprites go straight in; nearer the edge, sprites
; that would wrap around are left out.
DrawFrame:
        cmp #FrameCount
        bcc @inTable
        rts
@inTable:
        tax
        lda DrawDir
        bne @left
        lda FramePtrHi,x
        beq @rts
        sta Ptr+1
        lda FramePtrLo,x
        sta Ptr
        jmp @go
@left:
        lda FrameLPtrHi,x
        beq @rts
        sta Ptr+1
        lda FrameLPtrLo,x
        sta Ptr
@go:
        ldy #0
        lda (Ptr),y
        sta DrawCount
        iny
        ldx OamPos
        lda OamLeft
        bmi @rts
        ; near an edge?
        lda DrawX
        sec
        sbc #$20
        cmp #$C0
        bcs @edge
        lda DrawY
        sec
        sbc #$20
        cmp #$B0
        bcs @edge
@fast:
        lda (Ptr),y
        iny
        clc
        adc DrawY
        sta $0200,x
        lda (Ptr),y
        iny
        sta $0201,x
        lda (Ptr),y
        iny
        ora DrawAttr
        sta $0202,x
        lda (Ptr),y
        iny
        clc
        adc DrawX
        sta $0203,x
        lda NextOam,x
        tax
        dec OamLeft
        bmi @done
        dec DrawCount
        bne @fast
@done:
        stx OamPos
@rts:
        rts

@edge:
        lda (Ptr),y
        iny
        sta Temp0
        clc
        adc DrawY
        sta Temp1
        bit Temp0
        bmi @yneg
        bcs @skip3
        bcc @yok
@yneg:
        bcc @skip3
@yok:
        cmp #$EF
        bcs @skip3
        lda (Ptr),y
        iny
        sta Temp2
        lda (Ptr),y
        iny
        ora DrawAttr
        sta Temp3
        lda (Ptr),y
        iny
        sta Temp0
        clc
        adc DrawX
        bit Temp0
        bmi @xneg
        bcs @skip
        bcc @xok
@xneg:
        bcc @skip
@xok:
        sta $0203,x
        lda Temp1
        sta $0200,x
        lda Temp2
        sta $0201,x
        lda Temp3
        sta $0202,x
        lda NextOam,x
        tax
        dec OamLeft
        bmi @done
@skip:
        dec DrawCount
        bne @edge
        beq @done
@skip3:
        iny
        iny
        iny
        bne @skip

; Samus exploding (Metroid's ObjFrame_SamusExplode, drawn by ObjDrawFrame's
; explode placement): six pieces fly out in arcs, spinning, for 25 frames,
; while Castlevania's death plays. ExplodeCount counts the frames.
ExplodeCount = SamusJumpDsp

SamusDeath:
        lda SamusStatus
        cmp #sa_Dead2
        beq @going
        lda #sa_Dead2
        sta SamusStatus
        lda #0
        sta ExplodeCount
        jsr SFX_SamusDie
@going:
        inc ExplodeCount
        lda ExplodeCount
        cmp #$19
        bcs @rts
        ; Metroid's frame data moves the explosion up 4 (and y - 1 for OAM)
        lda DrawY
        sec
        sbc #5
        sta DrawY
        ldx #5
@piece:
        lda OamLeft
        bmi @rts
        ; y: arc table for the row (top, middle, bottom), plus the piece's place
        txa
        lsr
        tay
        lda ExplodeIndexTbl,y
        clc
        adc ExplodeCount
        tay
        lda ExplodePlacementTbl-1,y
        clc
        adc ExplodeBaseY,x
        sta Temp1
        ; spin: Metroid flips the pieces every frame; vertically flipped, an
        ; 8x16 piece shows its tile in the lower half, so move it up
        lda ExplodeCount
        and #$03
        tay
        lda ExplodeRotationTbl,y
        sta Temp3
        bpl @noV
        lda Temp1
        sec
        sbc #8
        sta Temp1
@noV:
        lda Temp1
        clc
        adc DrawY
        sta Temp1
        ; x: 2 pixels a frame, out to the piece's side
        lda ExplodeCount
        asl
        sta Temp0
        txa
        lsr
        bcs @right
        lda #0
        sec
        sbc Temp0
        sta Temp0
@right:
        lda Temp0
        clc
        adc ExplodeBaseX,x
        clc
        adc DrawX
        sta Temp0
        ldy OamPos
        lda Temp1
        sta $0200,y
        lda ExplodeTiles,x
        sta $0201,y
        lda Temp3
        sta $0202,y
        lda Temp0
        sta $0203,y
        lda NextOam,y
        sta OamPos
        dec OamLeft
        dex
        bpl @piece
@rts:
        rts

ExplodeIndexTbl:
        .db 0, 24, 48
ExplodePlacementTbl:
        .db $FC,$F8,$F4,$F0,$EE,$EC,$EA,$E8,$E7,$E6,$E6,$E5,$E5,$E4,$E4,$E3
        .db $E5,$E7,$E9,$EB,$EF,$F3,$F7,$FB
        .db $FE,$FC,$FA,$F8,$F6,$F4,$F2,$F0,$EE,$ED,$EB,$EA,$E9,$E8,$E7,$E6
        .db $E6,$E6,$E6,$E6,$E8,$EA,$EC,$EE
        .db $FE,$FC,$FA,$F8,$F7,$F6,$F5,$F4,$F3,$F2,$F1,$F1,$F0,$F0,$EF,$EF
        .db $EF,$EF,$EF,$EF,$F0,$F0,$F1,$F2
ExplodeBaseY:
        .db $F4, $F4, $FC, $FC, $04, $04
ExplodeBaseX:
        .db $F8, $00, $F8, $00, $F8, $00
ExplodeRotationTbl:
        .db $00, $80, $C0, $40
