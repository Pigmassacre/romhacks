; Star recall, from Gimmick! 2.
;
; In the original game B does nothing while a star is out: you wait until it
; has rolled to a stop and vanished, or left the screen. In Gimmick! 2,
; summoning a new star recalls the old one. Here, pressing B while the star
; is thrown, travelling through a tube or vanishing does the same. The old
; star flies back to Yumetaro, and the new star starts charging over his head
; at once.
;
; Fireballs and bombs are items, not the star, and are left alone.

; Called from bank $1E $81C3 (the player's star code), bank $1E at $8000.
; Carry clear: run the charge code. Carry set: skip it.
StarButton:
        lda Star_Status
        beq @charge             ; no star: charge as usual
        cmp #STAR_VANISH
        bcs @out                ; vanishing
        cmp #STAR_CHARGE0+1
        bcs @charge             ; $80-$A9: being charged
@out:                           ; thrown, in a tube, or vanishing
        lda Star_Type
        bne @busy               ; a fireball or bomb: leave it alone
        lda Pad_Pressed
        and #BTN_B
        beq @busy
        lda Obj_Flags           ; behind the background (a doorway), or
        ora BLockout            ; just used an item: no charging, as before
        bne @busy
        jsr Recall
@charge:
        clc
        rts
@busy:
        sec
        rts

; Take the star away and start the ghost where it was. With the status back
; at 0, the charge code that runs next starts a new star as usual.
Recall:
        lda #FX_RECALL
        ldy #0
        jsr FxStartAtStar
        lda #SND_RECALL         ; plays over the start of the charge sound
        jsr PlaySound
        lda #STAR_NONE
        sta Star_Status
        sta Obj_Standable+1     ; nobody can stand on it now
        sta Obj_StoodOn+1
        sta Obj_Timer2+1
        ldy #4                  ; and its after-images go with it
-       sta Trail_Status,y
        dey
        bpl -
        ; B+Up picks a fireball or bomb item for the charge. The item code ran
        ; earlier this frame and skipped that while the star was out.
        lda Pad_Held
        and #BTN_UP
        beq @star
        lda Item_Slot0
        cmp #ITEM_FIREBALL
        bcc @star
        sbc #1                  ; fireball 2 -> weapon 1, bomb 3 -> weapon 2
        sta Star_Type
@star:
        rts
