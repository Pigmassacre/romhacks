; Tap to summon, from Gimmick! 2's options.
;
; Gimmick! 2 lets you choose between holding the button to summon the star
; (as in the original) and tapping it. Here Select switches between the two
; during play. In tap mode, tap B to start a star and tap B again to throw it.
; A second tap before the star is ready throws it as soon as it is. Recall
; works the same way: tap B while a star is out.
;
; Select is free: only the disabled debug code ever read it.

; Called every frame Yumetaro can move, from the jump hook.
TapToggle:
        lda Pad_Pressed
        and #BTN_SELECT
        beq @rts
        lda #0
        sta Tap_Throw
        lda Tap_Mode
        eor #1
        sta Tap_Mode
        beq @off
        lda #SND_TAP_ON
        jmp PlaySound
@off:
        lda #SND_TAP_OFF
        jmp PlaySound
@rts:
        rts

; Called from bank $1E $81DA instead of "is B held?", while the star is
; idle (0) or charging ($80-$A9). Carry set: treat B as held.
BHeld:
        lda Tap_Mode
        bne @tap
        lda Pad_Held            ; hold mode: the original test
        and #BTN_B
        cmp #BTN_B
        rts
@tap:
        lda Star_Status
        bmi @charging
        lda #0                  ; idle: a tap starts a star
        sta Tap_Throw
        lda Pad_Pressed
        and #BTN_B
        cmp #BTN_B
        rts
@charging:
        lda Pad_Pressed         ; a tap while charging asks for the throw
        and #BTN_B
        beq @asked
        lda #1
        sta Tap_Throw
@asked:
        lda Tap_Throw
        beq @held
        lda Star_Status
        cmp #STAR_READY
        bcc @held               ; not ready: keep charging
        lda #0
        sta Tap_Throw
        clc                     ; let go: it is thrown
        rts
@held:
        sec
        rts
