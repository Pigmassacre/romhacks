; Coyote time and jump buffering, from Gimmick! 2.
;
; Coyote time: a jump still works for COYOTE_FRAMES frames after Yumetaro
; walks off a ledge (or off an enemy, or his star is recalled from under him).
; Jump buffering: pressing A up to JUMPBUF_FRAMES - 1 frames before landing
; jumps on the frame he lands.
;
; Both are kept as frame stamps rather than countdowns, so time spent stunned
; (when this code does not run) still counts.

; Called from bank $1E $8199 instead of "A pressed and on the floor?", on
; every frame Yumetaro can move. Carry set: jump.
JumpCheck:
        jsr TapToggle
        lda Obj_OnFloor
        bpl @air
        lda FrameCount
        sta Floor_F
        lda #1
        sta Floor_On
@air:
        lda Pad_Pressed
        bpl @nopress            ; bit 7 = A
        lda FrameCount
        sta JumpBuf_F
        lda #1
        sta JumpBuf_On
@nopress:
        ; Let both go once they are too old.
        lda FrameCount
        sec
        sbc Floor_F
        cmp #COYOTE_FRAMES+1    ; 0 = on the floor this frame
        bcc @floorok
        lda #0
        sta Floor_On
@floorok:
        lda FrameCount
        sec
        sbc JumpBuf_F
        cmp #JUMPBUF_FRAMES
        bcc @bufok
        lda #0
        sta JumpBuf_On
@bufok:
        lda JumpBuf_On
        and Floor_On
        beq @no
        lda #0
        sta JumpBuf_On
        sta Floor_On            ; no second jump from the same ledge
        sec
        rts
@no:
        clc
        rts
