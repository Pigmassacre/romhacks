; The SNES side of the port. The game's own 6502 code runs on the 65816 in emulation
; mode, in place, from a ROM bank that holds the banks the NES has mapped at that moment.
; Only instructions that touch NES hardware change: each becomes a JSR to a stub here.
;
; All of this runs from WRAM at $0800 and up, the part of the first 8 KB the NES game
; does not use, because that is the only memory every ROM bank can JSR to. It stays in
; emulation mode throughout, so an interrupt in here is just like one in the game's code.

.p816
.a8
.i8
.smart off

.include "hw.inc"

.import ColorLo, ColorHi, AttrTable, ChrBgBanks, ChrObjBanks
.import ComboIdx8, ComboIdxA, ComboTable

; VRAM layout, as word addresses.
OBJ2_HI    = $40            ; a second pair of sprite tables, for below a split
BGSET_HI   = $20            ; the first tile set of three: see set_hi
MAP_HI     = $60            ; nametable A at $6000, B at $6400
HIDDEN_Y   = $F0
PRG_HALF   = 16             ; which ROM banks' lower halves hold the NES banks, 4 in each
IRQ_EARLY  = 12             ; lines ahead of time to start a split's interrupt
CROP_TOP   = 8              ; the SNES's 224 lines start this far down the NES's 240

.segment "WVARS"
.export nmi_ptr, irq_ptr, nmi_flags, set_have
nmi_ptr:     .res 3         ; the game's NMI code, in the current ROM bank
irq_ptr:     .res 3
cur_pbr = nmi_ptr + 2
.export cur_pbr
back_ptr:    .res 3         ; fme_back, in the current ROM bank
fme_cmd:     .res 1
b8:          .res 1
bA:          .res 1
bC:          .res 1
ppu_ctrl:    .res 1
ppu_mask:    .res 1
ppu_w:       .res 1
ppu_tlo:     .res 1
ppu_thi:     .res 1
ppu_vlo:     .res 1
ppu_vhi:     .res 1
ppu_finex:   .res 1
ppu_buf:     .res 1
mirror:      .res 1
irq_lo:      .res 1
irq_hi:      .res 1
nmi_flags:   .res 1
irq_flag:    .res 1
irq_line:    .res 1         ; the SNES line the current split belongs on
in_split:    .res 1         ; a split's interrupt has run this frame
.export in_split
.export irq_flag
force_blank: .res 1
vram_step:   .res 1
split_n:     .res 1         ; how many splits have changed the background's tiles this frame
split_open:  .res 1         ; a split has changed tiles and not yet shown them
split_flip:  .res 1         ; the second sprite tables are showing
tmp:         .res 4
itmp:        .res 4         ; the same, for code that interrupts may run
vf_left:     .res 1
attr_until:  .res 1
attr_ch:     .res 1
attr_pg:     .res 1
attr_head:   .res 1
attr_tail:   .res 1
attr_chg:    .res 128       ; the shadow's bits that the map has yet to get
attr_q:      .res 128
attr_new:    .res 1
attr_col:    .res 1
attr_row:    .res 1
attr_lo:     .res 1
attr_hi:     .res 1
chr_want:    .res 8         ; what the game has mapped for the top of the picture
chr_obj:     .res 8         ; loaded in the sprite tables
set_want:    .res 12        ; BG slots 4-7 for each of the three tile sets
set_have:    .res 12
obj2_want:   .res 8         ; the sprite pages below a split
obj2_have:   .res 8
obj_base:    .res 1
obj_used:    .res 8         ; sprites use this slot of the second table: see convert_oam
set_wr:      .res 12        ; a split wrote this slot itself, so it must be copied soon
nmi_count:   .res 1
.export obj2_have
.export apu_regs, sb_cmd, sb_regs, apu_kick
apu_regs:    .res 32
apu_kick:    .res 4
sb_cmd:      .res 1
sb_regs:     .res 16
hdma_tab:    .res 16
.export hdma_tab
attr_shadow: .res 128
oam_buf:     .res 512
data_left:   .res 1         ; tile writes that can go straight to VRAM, without a look at v
.export pal_dirty, cg_bg, cg_obj
pal_dirty:   .res 1
w6_bank:     .res 1
oam_ready:   .res 1
cg_bg:       .res 32
cg_obj:      .res 32

.segment "WCODE"

; ---- The FME-7 --------------------------------------------------------------------

.export fme_cmd_a, fme_cmd_x, fme_cmd_y, fme_val_a, fme_val_x, fme_val_y
fme_cmd_a:
        sta fme_cmd
        rts
fme_cmd_x:
        stx fme_cmd
        rts
fme_cmd_y:
        sty fme_cmd
        rts

fme_val_x:
        php
        pha
        txa
        bra fme_val
fme_val_y:
        php
        pha
        tya
        bra fme_val
fme_val_a:
        php
        pha
fme_val:
        phx
        phy
        tay
        lda fme_cmd
        and #$0F
        asl a
        tax
        tya
        jmp (fme_jump,x)

fme_jump:
        .word fme_chr, fme_chr, fme_chr, fme_chr, fme_chr, fme_chr, fme_chr, fme_chr
        .word fme_6000, fme_prg8, fme_prgA, fme_prgC
        .word fme_mirror, fme_irqctl, fme_irqlo, fme_irqhi

fme_done:
        ply
        plx
        pla
        plp
        rts

fme_prg8:
        and #$1F
        sta b8
        bra fme_switch
fme_prgA:
        and #$1F
        sta bA
        bra fme_switch
fme_prgC:
        and #$1F
        sta bC
        jmp fme_done
fme_switch:
        ldx b8
        lda f:ComboIdx8,x
        ldx bA
        clc
        adc f:ComboIdxA,x
        tax
        lda f:ComboTable,x
        sta cur_pbr
        sta back_ptr + 2
        sta irq_ptr + 2
        pha
        plb
        ; Carry on from this same code, in the new bank's mirror of RAM.
        jml [back_ptr]
fme_back:
        jmp fme_done

; $6000-$7FFF shows a ROM bank, chosen once per stage. The SNES has the cartridge's RAM
; there and no way to map ROM, so the bank is copied in. The picture is off for this,
; on the NES's first frames of a stage.
fme_6000:
        and #$1F
        cmp w6_bank
        beq w6_same
        sta w6_bank
        tay
        lsr a
        lsr a
        clc
        adc #$C0 + PRG_HALF
        sta w6_src + 3
        tya
        and #3
        asl a
        asl a
        asl a
        asl a
        asl a
        sta w6_src + 2
        lda #$60
        sta w6_dst + 2
        ldy #$20            ; pages
        ldx #0
w6_src: lda f:$C00000,x
w6_dst: sta a:$6000,x
        inx
        bne w6_src
        inc w6_src + 2
        inc w6_dst + 2
        dey
        bne w6_src
w6_same:
        jmp fme_done

fme_mirror:
        and #3
        sta mirror
        tax
        lda mirror_sc,x
        sta BG1SC
        jmp fme_done
mirror_sc:
        .byte MAP_HI | 1, MAP_HI | 2, MAP_HI, MAP_HI | 4

fme_irqlo:
        sta irq_lo
        jmp fme_done
fme_irqhi:
        sta irq_hi
        jmp fme_done

; Bits 0 and 7 enable the interrupt and the count. Any write acknowledges it.
fme_irqctl:
        and #$81
        cmp #$81
        beq :+
        stz irq_flag
        lda nmi_flags
        sta NMITIMEN
        jmp fme_done
:       jsr arm_irq
        jmp fme_done

; The FME-7 counts CPU cycles and the SNES interrupts on a line. A NES line is 113.67
; cycles, so lines = count * 9 / 1024, near enough.
arm_irq:
        lda irq_hi
        sta WRMPYA
        lda #9
        sta WRMPYB
        nop
        nop
        nop
        nop
        lda irq_lo
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc RDMPYL
        sta itmp
        lda RDMPYH
        adc #0
        lsr a
        ror itmp
        lsr a
        ror itmp             ; lines from now
        cmp #0
        bne @never          ; 256 or more
        ; From vblank, count from the NES's line 241, 21 before its line 0. From a split,
        ; count from the line that split was meant for.
        jsr beam
        cmp #225
        bcc @line
        ; lines - 29 is the first line on the SNES, unless that is before the picture.
        lda itmp
        sec
        sbc #21 + CROP_TOP
        bcs @set
        lda #0
        bra @set
@line:  lda irq_line
        clc
        adc itmp
        bcs @never
@set:   cmp #225
        bcs @never
        sta irq_line
        ; Early, since the game's handler takes much longer here than on the NES. What it
        ; changes on screen waits for the line, in wait_line.
        sec
        sbc #IRQ_EARLY
        bcs :+
        lda #0
:       sta itmp
        jsr beam
        cmp itmp
        bcc :+
        cmp #225
        bcs :+
        ina
        sta itmp
:       lda itmp
        sta VTIMEL
        stz VTIMEH
        lda #$20
        sta irq_flag
        ora nmi_flags
        sta NMITIMEN
        rts
@never: stz irq_flag
        lda nmi_flags
        sta NMITIMEN
        rts

; The line the beam is on, with everything past 255 as 255.
beam:
        lda SLHV
        lda OPVCT
        sta itmp + 3
        lda OPVCT
        and #1
        beq :+
        lda #$FF
        rts
:       lda itmp + 3
        rts

; Wait for the line the current split is meant for, then for its hblank.
wait_line:
:       jsr beam
        cmp irq_line
        bcc :-
wait_hblank:
:       bit HVBJOY
        bvs :-
:       bit HVBJOY
        bvc :-
        rts

; Carry set when the beam is drawing the picture now.
picture_on:
        pha
        lda force_blank
        bne @no
        lda HVBJOY
        bmi @no
        pla
        sec
        rts
@no:    pla
        clc
        rts

; Is there time to copy a page before vblank ends? Carry set if so.
may_dma:
        pha
        lda force_blank
        bne @yes
        lda SLHV
        lda OPVCT
        sta itmp + 3
        lda OPVCT
        and #1
        bne @no             ; lines 256-261
        lda itmp + 3
        cmp #225
        bcc @no
        cmp #248
        bcs @no
@yes:   pla
        sec
        rts
@no:    pla
        clc
        rts

; Page in a, for the slot in fme_cmd.
fme_chr:
        tay
        lda fme_cmd
        and #7
        tax
        jsr picture_on
        bcs @split
        tya
        sta chr_want,x
        cpx #4
        bcc :+
        sta set_want - 4,x
:       ; With the picture off the main thread may be part way through writing a map, and
        ; this may be the NMI. It waits for frame_done, when nothing is writing to VRAM.
        lda force_blank
        bne @out
        jsr load_top_slot
@out:   jmp fme_done
@split: tya
        sta obj2_want,x
        cpx #4
        bcc @flip
        ; A further tile set for what comes below. It can only be copied in vblank, so
        ; the first frame of a new set still shows the old one.
        lda split_open
        bne @have
        lda split_n
        cmp #2
        bcs @flip
        inc split_n
        inc split_open
        ; Start it from the set above.
        asl a
        asl a
        phx
        tax
        lda set_want,x
        sta set_want + 4,x
        lda set_want + 1,x
        sta set_want + 5,x
        lda set_want + 2,x
        sta set_want + 6,x
        lda set_want + 3,x
        sta set_want + 7,x
        plx
@have:  lda split_n
        asl a
        asl a
        sta tmp
        txa
        and #3
        ora tmp
        tax
        tya
        sta set_want,x
        lda #1
        sta set_wr,x
@flip:  jsr flip_sprites
        jmp fme_done

; Bring slot x up to date, if there is time. Keeps x.
load_top_slot:
        ldy chr_want,x
        cpx #4
        bcc @obj
        tya
        cmp set_have - 4,x
        beq @obj
        jsr may_dma
        bcc @obj
        sta set_have - 4,x
        lda #$80
        sta VMAINC
        stz VMADDL
        txa
        and #3
        asl a
        ora #BGSET_HI
        sta VMADDH
        jsr dma_bg_page
@obj:   cpx #4
        bcc :+
        lda obj_used,x
        beq @out
:       tya
        cmp chr_obj,x
        beq @out
        jsr may_dma
        bcc @out
        sta chr_obj,x
        jsr dma_obj_page
@out:   rts

; Page in y; the VRAM address is set. Keeps y.
dma_bg_page:
        tya
        phx
        tax
        lda f:ChrBgBanks,x
        plx
        sta A1B7
        tya
        and #$1F
        asl a
        asl a
        sta A1T7H
        stz A1T7L
        lda #1
        sta DMAP7
        lda #<VMDATAL
        sta BBAD7
        stz DAS7L
        lda #$04
        sta DAS7H
        lda #$80
        sta MDMAEN
        rts

; Page in y, slot in x. 2 KB for 64 sprite tiles, at slot * $400 words.
dma_obj_page:
        lda #$80
        sta VMAINC
        stz VMADDL
        txa
        asl a
        asl a
        ora obj_base
        sta VMADDH
        tya
        phx
        tax
        lda f:ChrObjBanks,x
        plx
        sta A1B7
        tya
        and #$0F
        asl a
        asl a
        asl a
        sta A1T7H
        stz A1T7L
        lda #1
        sta DMAP7
        lda #<VMDATAL
        sta BBAD7
        stz DAS7L
        lda #$08
        sta DAS7H
        lda #$80
        sta MDMAEN
        rts

; The tile sets, by the high byte of their VRAM address.
set_hi: .byte BGSET_HI, $30, $70

; At the next line, show the tiles and sprites a split changed to, once they are copied.
show_split_set:
        jsr flip_sprites
@bg:    lda split_open
        beq @out
        stz split_open
        lda split_n
        asl a
        asl a
        tax
        ldy #4
:       lda set_wr,x
        beq :+
        lda set_want,x
        cmp set_have,x
        bne @out
:       inx
        dey
        bne :--
        ldx split_n
        lda set_hi,x
        lsr a
        lsr a
        lsr a
        lsr a
        sta BG12NBA
@out:   rts

; The game sets the sprites' pages one by one: flip when the last one is right.
flip_sprites:
        lda split_flip
        bne @out
        ldx #4              ; the other slots follow when there is time
:       lda obj2_want,x
        cmp obj2_have,x
        bne @out
        dex
        bpl :-
        jsr wait_line
        lda #OBJ2_HI >> 5
        sta OBSEL
        inc split_flip
@out:   rts


; The NMI's work, before the game's code. Copy one page that a split wanted last frame,
; and start the frame from the sets above the split.
.export nmi_work
nmi_work:
        lda tmp
        pha
        lda tmp + 1
        pha
        lda tmp + 2
        pha
        lda tmp + 3
        pha
        jsr nmi_work2
        pla
        sta tmp + 3
        pla
        sta tmp + 2
        pla
        sta tmp + 1
        pla
        sta tmp
        rts
nmi_work2:
        jsr commit_palette
        stz split_n
        stz split_open
        stz split_flip
        stz irq_line
        stz in_split
        stz OBSEL
        lda #BGSET_HI >> 4
        sta BG12NBA
        lda #$40
        sta HDMAEN
        jsr scroll_now
        lda force_blank
        bne :+
        jsr load_page
        lda #234
        jsr attr_work
:       ldx #7
:       lda chr_want,x
        sta obj2_want,x
        dex
        bpl :-
        ldx #11
:       stz set_wr,x
        dex
        cpx #4
        bcs :-
        rts

; The game writes its scroll near the end of its NMI, later than the SNES's vblank allows.
; It has already decided: $FD, $FC and $FF if it finished the frame, or last time's.
scroll_now:
        lda $29
        bne @out            ; the picture is going off
        ldx #0
        lda $F0
        cmp #$AC
        beq :+
        ldx #$BA            ; $42 is $FC - $BA, the wrong way round
:       txa
        beq @done_frame
        lda $42
        ldx $43
        ldy $44
        bra @set
@done_frame:
        lda $FD
        ldx $FC
        ldy $FF
@set:   pha
        and #7
        sta ppu_finex
        pla
        lsr a
        lsr a
        lsr a
        sta tmp + 2
        txa
        and #$38
        asl a
        asl a
        ora tmp + 2
        sta ppu_tlo
        txa
        and #7
        asl a
        asl a
        asl a
        asl a
        sta tmp + 2
        txa
        and #$C0
        asl a
        rol a
        rol a
        ora tmp + 2
        sta tmp + 2
        tya
        and #3
        asl a
        asl a
        ora tmp + 2
        sta ppu_thi
        jsr apply_scroll
@out:   rts

; One page, what matters most first: what the last frame's splits wrote, then the sprites'
; second table above the split, then the rest of the split sets and second sprite tables.
load_page:
        inc nmi_count
        ldx #4
@next:  lda set_wr,x
        beq :+
        lda set_want,x
        cmp set_have,x
        bne @load
:       inx
        cpx #12
        bne @next
        ldx #4
@obj:   lda obj2_want,x
        cmp obj2_have,x
        bne @load_obj
        dex
        bpl @obj
        ; Sprites' second table for the top of the picture
        ldx #7
@top:   lda obj_used,x
        beq :+
        lda chr_want,x
        cmp chr_obj,x
        beq :+
        sta chr_obj,x
        tay
        jmp dma_obj_page
:       dex
        cpx #4
        bcs @top
        ; Now and then, what no one has shown yet
        lda nmi_count
        and #7
        bne @out
        ldx #4
@rest:  lda set_want,x
        cmp set_have,x
        bne @load
        inx
        cpx #12
        bne @rest
        ldx #7
@rest2: lda obj2_want,x
        cmp obj2_have,x
        bne @load_obj
        dex
        cpx #5
        bcs @rest2
@out:   rts
@load_obj:
        sta obj2_have,x
        tay
        lda #OBJ2_HI
        sta obj_base
        jsr dma_obj_page
        stz obj_base
        rts
@load:  sta set_have,x
        tay
        lda #$80
        sta VMAINC
        stz VMADDL
        ; x = set * 4 + slot, and slots are $200 words.
        txa
        and #3
        asl a
        sta tmp
        txa
        lsr a
        lsr a
        phx
        tax
        lda set_hi,x
        plx
        ora tmp
        sta VMADDH
        jmp dma_bg_page

; $F06B in the game: slots 0-7 from $E1-$E8, in vblank. The same, without eight trips
; through the FME-7's registers. X and Y are the caller's.
.export chr_all
chr_all:
        phx
        phy
        ldx #7
@slot:  lda $E1,x
        cmp chr_want,x
        beq @same
        sta chr_want,x
        cpx #4
        bcc :+
        sta set_want - 4,x
:       lda force_blank
        bne @same
        jsr load_top_slot
@same:  dex
        bpl @slot
        lda #7
        sta fme_cmd
        ply
        plx
        lda $E8
        rts

; ---- PPU registers ----------------------------------------------------------------

; Stubs for stores: the value in a, with the game's flags and a on the stack.
.macro reg_stub name, target
.export .ident(.concat(name, "_a")), .ident(.concat(name, "_x")), .ident(.concat(name, "_y"))
.ident(.concat(name, "_x")):
        php
        pha
        txa
        jmp target
.ident(.concat(name, "_y")):
        php
        pha
        tya
        jmp target
.ident(.concat(name, "_a")):
        php
        pha
        jmp target
.endmacro

reg_stub "ppu_ctrl", ppu_ctrl_w
reg_stub "ppu_mask", ppu_mask_w
reg_stub "ppu_scroll", ppu_scroll_w
reg_stub "ppu_addr", ppu_addr_w

; A run of tiles needs nothing but the store, until v leaves the nametable's tiles.
.export ppu_data_a, ppu_data_x, ppu_data_y
ppu_data_x:
        php
        dec data_left
        bmi ppu_data_x_slow
        stx VMDATAL
        plp
        rts
ppu_data_x_slow:
        pha
        txa
        jmp ppu_data_w
ppu_data_y:
        php
        dec data_left
        bmi ppu_data_y_slow
        sty VMDATAL
        plp
        rts
ppu_data_y_slow:
        pha
        tya
        jmp ppu_data_w
ppu_data_a:
        php
        dec data_left
        bmi ppu_data_a_slow
        sta VMDATAL
        plp
        rts
ppu_data_a_slow:
        pha
        jmp ppu_data_w
reg_stub "sb_data", sb_data_w

reg_done:
        ply
        plx
        pla
        plp
        rts

ppu_ctrl_w:
        phx
        phy
        tay
        eor ppu_ctrl
        sta tmp + 1         ; what changed
        sty ppu_ctrl
        and #$FB
        bne @full
        ; Only the VRAM step, which the game changes all through its vblank.
        ldx #$FF
        stx data_left
        tya
        lsr a
        lsr a
        and #1
        sta vram_step
        jmp reg_done
@full:
        ; t: nametable select
        tya
        and #3
        asl a
        asl a
        sta tmp
        lda ppu_thi
        and #$F3
        ora tmp
        sta ppu_thi
        ldx #$FF
        stx data_left
        ; VRAM step: VMAINC's low bit says 1 or 32
        tya
        lsr a
        lsr a
        and #1
        sta vram_step
        jsr picture_on
        bcs @on
        ; NMI enable, in vblank or with the picture off. It keeps an armed line interrupt.
        tya
        and #$80
        sta nmi_flags
        ora irq_flag
        sta NMITIMEN
        lda tmp + 1
        and #3
        beq reg_done
        jsr apply_scroll
        jmp reg_done
@on:    jsr mid_scroll
        jmp reg_done

ppu_mask_w:
        phx
        phy
        sta ppu_mask
        tay
        ; Hide the left 8 pixels where the game asks: bits 1 and 2 show them.
        and #2
        eor #2
        lsr a
        sta tmp
        tya
        and #4
        eor #4
        asl a
        asl a
        ora tmp
        sta TMW
        tya
        and #$18
        beq @off
        lsr a
        lsr a
        lsr a
        lsr a               ; carry = BG, a = sprites
        rol a
        ; now bit 1 is sprites, bit 0 BG; TM wants them at bits 4 and 0
        tay
        and #1
        sta tmp
        tya
        and #2
        asl a
        asl a
        asl a
        ora tmp
        sta TM
        stz force_blank
        lda #$0F
        sta INIDISP
        jmp reg_done
@off:   lda #$80
        sta force_blank
        sta INIDISP
        jmp reg_done

; lda/ldx/ldy $2002. N and Z come from the value.
.export ppu_status_a, ppu_status_x, ppu_status_y
ppu_status_a:
        stz ppu_w
        lda HVBJOY
        and #$80
        rts
ppu_status_x:
        stz ppu_w
        pha
        lda HVBJOY
        and #$80
        tax
        pla
        cpx #0
        rts
ppu_status_y:
        stz ppu_w
        pha
        lda HVBJOY
        and #$80
        tay
        pla
        cpy #0
        rts

ppu_scroll_w:
        phx
        phy
        ldy ppu_w
        bne @second
        ; x: coarse into t, fine apart
        tay
        and #7
        sta ppu_finex
        tya
        lsr a
        lsr a
        lsr a
        sta tmp
        lda ppu_tlo
        and #$E0
        ora tmp
        sta ppu_tlo
        inc ppu_w
        jmp reg_done
@second:
        stz ppu_w
        ; y: fine into bits 12-14, coarse into bits 5-9, keeping the nametable
        tay
        and #7
        asl a
        asl a
        asl a
        asl a
        sta tmp
        tya
        and #$C0
        asl a
        rol a
        rol a
        ora tmp
        sta tmp
        lda ppu_thi
        and #$0C
        ora tmp
        sta ppu_thi
        tya
        and #$38
        asl a
        asl a
        sta tmp
        lda ppu_tlo
        and #$1F
        ora tmp
        sta ppu_tlo
        jsr picture_on
        bcs @on
        jsr apply_scroll
        jmp reg_done
@on:    jsr mid_scroll
        jmp reg_done

ppu_addr_w:
        phx
        phy
        ldy ppu_w
        bne @second
        and #$3F
        sta ppu_thi
        inc ppu_w
        jmp reg_done
@second:
        stz ppu_w
        ldx #$FF
        stx data_left       ; negative: the next store looks at v
        sta ppu_tlo
        sta ppu_vlo
        lda ppu_thi
        sta ppu_vhi
        jsr picture_on
        bcc :+
        jsr mid_scroll_v
:       jmp reg_done

; y from t in tmp, its nametable bit in tmp + 1.
t_y:
        lda ppu_thi
        and #$70
        lsr a
        lsr a
        lsr a
        lsr a
        sta tmp
        lda ppu_thi
        and #3
        lsr a
        ror a
        ror a
        ora tmp
        sta tmp
        lda ppu_tlo
        and #$E0
        lsr a
        lsr a
        ora tmp
        sta tmp
        lda ppu_thi
        and #8
        lsr a
        lsr a
        lsr a
        sta tmp + 1
        rts

; Horizontal scroll from t.
apply_h:
        lda ppu_tlo
        and #$1F
        asl a
        asl a
        asl a
        ora ppu_finex
        sta BG1HOFS
        lda ppu_thi
        and #4
        lsr a
        lsr a
        sta BG1HOFS
        rts

; Write t to the SNES scroll, for the frame to come. A nametable's 30 rows are followed
; by the next one's on the NES, and by 2 rows that are not drawn in the SNES map, so an
; HDMA table adds 16 lines where the picture crosses them.
apply_scroll:
        jsr apply_h
        jsr t_y
        lda tmp
        clc
        adc #CROP_TOP - 1
        sta hdma_tab + 1
        lda tmp + 1
        adc #0
        sta hdma_tab + 2
        ; Lines before the map's y reaches 240
        lda #240 - CROP_TOP
        sec
        sbc tmp
        beq @crossed
        bcc @crossed
        ldx #0
        cmp #$80
        bcc @last
        ; This format's counts stop at 127, so two entries say the same.
        sbc #$7F
        ldy #$7F
        sty hdma_tab
        ldy hdma_tab + 1
        sty hdma_tab + 4
        ldy hdma_tab + 2
        sty hdma_tab + 5
        ldx #3
@last:  sta hdma_tab,x
        lda hdma_tab + 1,x
        clc
        adc #16
        sta hdma_tab + 4,x
        lda hdma_tab + 2,x
        adc #0
        sta hdma_tab + 5,x
        lda #1
        sta hdma_tab + 3,x
        stz hdma_tab + 6,x
        rts
@crossed:
        lda hdma_tab + 1
        clc
        adc #16
        sta hdma_tab + 1
        lda hdma_tab + 2
        adc #0
        sta hdma_tab + 2
        lda #1
        sta hdma_tab
        stz hdma_tab + 3
        rts

; A scroll register written with the picture on: from the next line, x comes from t.
mid_scroll:
        ; A late write from the NMI: nmi_work has already set this frame's scroll.
        lda in_split
        beq :+
        jsr wait_line
        jsr apply_h
        jmp show_split_set
:       rts
        jsr apply_h
        jmp show_split_set

; $2006 with the picture on moved v, so y jumps too: this line shows row y of the map.
mid_scroll_v:
        lda in_split
        bne :+
        rts
:       jsr t_y
        lda SLHV
        lda OPVCT
        sta tmp + 2
        lda OPVCT
        lda tmp
        sec
        sbc tmp + 2
        tay
        lda tmp + 1
        sbc #0
        tax
        jsr wait_line
        stz HDMAEN
        sty BG1VOFS
        stx BG1VOFS
        jsr apply_h
        jmp show_split_set

; Which SNES nametable each NES one lands on, for each FME-7 mirroring mode.
mirror_nt:
        .byte 0, 1, 0, 1
        .byte 0, 0, 1, 1
        .byte 0, 0, 0, 0
        .byte 1, 1, 1, 1

palette_index:
        .byte 0, 1, 2, 3,       4, 5, 6, 7,       8, 9, 10, 11,       12, 13, 14, 15
        .byte 128, 129, 130, 131,  144, 145, 146, 147,  160, 161, 162, 163,  176, 177, 178, 179

ppu_data_w:
        phx
        phy
        tay                 ; the byte
        stz data_left
        lda ppu_vhi
        and #$3F
        cmp #$3F
        beq @palette
        cmp #$20
        bcc @next           ; CHR is ROM
        ; The nametable number and the mirroring pick the SNES map.
        and #$0C
        lsr a
        lsr a
        sta tmp
        lda mirror
        asl a
        asl a
        ora tmp
        tax
        lda mirror_nt,x
        asl a
        asl a
        sta tmp             ; +$400 words for map B
        lda ppu_vhi
        and #3
        cmp #3
        bne @tile
        lda ppu_vlo
        cmp #$C0
        bcs @attr
        lda #3
@tile:  ora tmp
        ora #MAP_HI
        ldx vram_step
        stx VMAINC
        sta VMADDH
        lda ppu_vlo
        sta VMADDL
        sty VMDATAL
        jsr plan_run
@next:  lda vram_step
        beq @one
        lda ppu_vlo
        clc
        adc #32
        sta ppu_vlo
        bcc @out
        inc ppu_vhi
        bra @out
@one:   inc ppu_vlo
        bne @out
        inc ppu_vhi
@out:   jmp reg_done
@attr:  jsr ppu_attr
        bra @next
@palette:
        ; Kept apart and sent at the start of vblank: 32 writes from here take too long.
        tya
        and #$3F
        tax
        lda f:ColorLo,x
        sta tmp
        lda f:ColorHi,x
        sta tmp + 1
        lda ppu_vlo
        and #$1F
        asl a
        tax
        lda tmp
        sta cg_bg,x
        lda tmp + 1
        sta cg_bg + 1,x
        txa
        and #$1F
        bne :+
        ; $3F00 and $3F10 are one colour, the backdrop.
        lda tmp
        sta cg_bg
        sta cg_obj
        lda tmp + 1
        sta cg_bg + 1
        sta cg_obj + 1
:       lda #1
        sta pal_dirty
        jmp @next

; Send the colours the game has changed. From the NMI.
commit_palette:
        lda pal_dirty
        beq @out
        stz pal_dirty
        stz CGADD
        ldx #0
:       lda cg_bg,x
        sta CGDATA
        inx
        cpx #32
        bne :-
        ldx #0
        ldy #128
@set:   sty CGADD
:       lda cg_obj,x
        sta CGDATA
        inx
        txa
        and #7
        bne :-
        tya
        clc
        adc #16
        tay
        cpx #32
        bne @set
@out:   rts

; Stop a run of tiles early, because something else is about to use VRAM: v goes back
; to where the run has got to.
end_run:
        lda data_left
        bmi @out
        ldx vram_step
        bne @down
        lda ppu_vlo
        sec
        sbc data_left
        sta ppu_vlo
        bcs @done
        dec ppu_vhi
        bra @done
@down:  stz tmp + 1
        ldx #5
:       asl a
        rol tmp + 1
        dex
        bne :-
        sta tmp
        lda ppu_vlo
        sec
        sbc tmp
        sta ppu_vlo
        lda ppu_vhi
        sbc tmp + 1
        sta ppu_vhi
@done:  lda #$FF
        sta data_left
@out:   rts

; After a tile: how many more can go straight to VRAM, which steps by itself, before v
; leaves the tiles. v moves past them now, since those stores will not touch it.
plan_run:
        lda vram_step
        bne @down
        lda ppu_vhi
        and #3
        cmp #3
        php
        lda #$FE
        plp
        bne :+
        lda #$BE
:       sec
        sbc ppu_vlo
        bcs :+
        lda #0
:       cmp #$7F
        bcc :+
        lda #$7F
:       sta data_left
        clc
        adc ppu_vlo
        sta ppu_vlo
        rts
@down:  lda ppu_vhi
        and #3
        asl a
        asl a
        asl a
        sta tmp + 1
        lda ppu_vlo
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp + 1
        sta tmp + 1         ; row
        lda #29
        sec
        sbc tmp + 1
        bcs :+
        lda #0
:       sta data_left
        stz tmp + 1
        ldx #5
:       asl a
        rol tmp + 1
        dex
        bne :-
        clc
        adc ppu_vlo
        sta ppu_vlo
        lda ppu_vhi
        adc tmp + 1
        sta ppu_vhi
        rts

; $F3D3 in the game: write the buffer of VRAM updates at $0170 in vblank. Each entry is
; high and low address, then a count with bit 7 for stepping down, then the bytes. A high
; byte of 0 stands for a reset of the VRAM address. This does the job of its loop with
; the tiles going straight to VRAM. It may change X, Y and A, as that does.
.export vram_flush
vram_flush:
        stz ppu_w
        ldy #0
        ldx #$FF
        stx data_left
@entry: cpy $FA
        bcc :+
        stz $FA
        lda #252
        jmp attr_work
:       lda $0170,y
        bne :+
        iny
        bra @entry
:       sta ppu_vhi
        sta ppu_thi
        iny
        lda $0170,y
        sta ppu_vlo
        sta ppu_tlo
        iny
        lda $0170,y
        iny
        tax
        ; The step goes in the shadow too, as the game's write to $2000 would do.
        lda $FF
        and #$FB
        cpx #$80
        bcc :+
        ora #4
:       sta ppu_ctrl
        txa
        and #$7F
        sta vf_left
        cpx #$80
        lda #0
        rol a
        sta vram_step
        ; Tiles on the way across or down stay in the map, unless they reach attributes.
        lda ppu_vhi
        cmp #$3F
        bcs @slow
        and #3
        cmp #3
        bne @fast
        lda ppu_vlo
        cmp #$C0 - 64       ; well short of the attributes, on the last page
        bcs @slow
@fast:  lda vram_step
        bne @slow           ; down: a column may reach attributes
        ; Would it leave the page?
        lda ppu_vlo
        clc
        adc vf_left
        bcs @slow
        phy
        lda ppu_vhi
        and #$0C
        lsr a
        lsr a
        sta tmp
        lda mirror
        asl a
        asl a
        ora tmp
        tax
        lda mirror_nt,x
        asl a
        asl a
        sta tmp
        lda ppu_vhi
        and #3
        ora tmp
        ora #MAP_HI
        stz VMAINC
        sta VMADDH
        lda ppu_vlo
        sta VMADDL
        ply
        ldx vf_left
:       lda $0170,y
        sta VMDATAL
        iny
        dex
        bne :-
        jmp @entry
@slow:  ; palettes, attributes and columns, a byte at a time as the game would
        lda #$FF
        sta data_left
:       lda $0170,y
        phy
        jsr ppu_data_a
        ply
        iny
        dec vf_left
        bne :-
        jmp @entry

; An attribute byte (in y) sets the palette of the 16 tiles in its 4 quarters. That is too
; much work for vblank when a column of them comes along, so they queue up. The tiles
; are mostly off screen so far: a frame or two of delay does not show.
ppu_attr:
        lda tmp
        beq :+
        lda #64
:       sta tmp + 1
        lda ppu_vlo
        and #$3F
        clc
        adc tmp + 1
        tax
        tya
        eor attr_shadow,x
        beq @out
        pha
        tya
        sta attr_shadow,x
        pla
        ldy attr_chg,x
        bne @queued
        ldy attr_tail
        sta attr_chg,x
        txa
        sta attr_q,y
        iny
        tya
        and #$7F
        sta attr_tail
        bra @run
@queued:
        ora attr_chg,x
        sta attr_chg,x
@run:   lda force_blank
        beq @out
        lda #$FF
        jmp attr_work
@out:   rts

; Work through the queue until the beam reaches line a, or to the end with the picture off.
.export attr_work
attr_work:
        sta attr_until
@item:  ldx attr_head
        cpx attr_tail
        beq @done
        lda force_blank
        bne @go
        jsr beam
        cmp #225
        bcc @done
        cmp attr_until
        bcs @done
@go:    ldx attr_head
        lda attr_q,x
        tay
        inx
        txa
        and #$7F
        sta attr_head
        jsr attr_item
        bra @item
@done:  rts

; y = the shadow's index
attr_item:
        tyx
        lda attr_chg,x
        sta attr_ch
        stz attr_chg,x
        lda attr_shadow,x
        sta attr_new
        ; map A or B
        tya
        and #$40
        beq :+
        lda #4
:       ora #MAP_HI
        sta attr_pg
        lda #$80
        sta VMAINC
        tya
        and #7
        asl a
        asl a
        sta attr_col
        tya
        and #$38
        lsr a
        lsr a
        lsr a
        sta attr_row
        ldx #0
@quarter:
        lda attr_ch
        and #3
        beq @same
        ; word = map + group row * 128 + (quarter bit 1) * 64 + col * 4 + (quarter bit 0) * 2
        txa
        and #1
        asl a
        ora attr_col
        sta attr_lo
        lda attr_row
        lsr a
        sta attr_hi
        lda #0
        ror a
        ora attr_lo
        sta attr_lo
        txa
        and #2
        beq :+
        lda attr_lo
        clc
        adc #64
        sta attr_lo
        bcc :+
        inc attr_hi
:       lda attr_hi
        ora attr_pg
        sta attr_hi
        lda attr_new
        and #3
        asl a
        asl a
        tay
        lda attr_lo
        sta VMADDL
        lda attr_hi
        sta VMADDH
        sty VMDATAH
        sty VMDATAH
        lda attr_lo
        clc
        adc #32
        sta VMADDL
        lda attr_hi
        adc #0
        sta VMADDH
        sty VMDATAH
        sty VMDATAH
@same:  lsr attr_ch
        lsr attr_ch
        lsr attr_new
        lsr attr_new
        inx
        cpx #4
        bne @quarter
        rts

; ---- $4014: sprites ---------------------------------------------------------------

; NES sprites 8x16 each become two SNES sprites, since it has no size that shape. Each
; keeps its place in the order, so priority comes out the same.
.macro convert_sprites buf, first
.local @sprite, @hide, @stored, @flip, @next, @even
        ldx #first
        ldy #0
@sprite:
        lda $0200,x
        cmp #$EF
        bcs @hide
        sbc #CROP_TOP - 2   ; carry is clear: subtract one more
        sta tmp
        lda $0203,x
        sta buf,y
        sta buf + 4,y
        lda $0201,x
        and #$FE
        sta buf + 2,y
        ina
        sta buf + 6,y
        lda $0201,x
        and #1
        sta tmp + 1
        beq @even
        ; The second table: most slots there go unused, and loading them costs time.
        lda $0201,x
        phx
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        lda #1
        sta obj_used + 4,x
        plx
@even:  lda $0202,x
        phx
        tax
        lda f:AttrTable,x
        plx
        ora tmp + 1
        sta buf + 3,y
        sta buf + 7,y
        lda $0202,x
        bmi @flip
        lda tmp
        sta buf + 1,y
        clc
        adc #8
        sta buf + 5,y
        bra @next
@flip:  lda tmp
        sta buf + 5,y
        clc
        adc #8
        sta buf + 1,y
        bra @next
@hide:  lda #HIDDEN_Y
        sta buf + 1,y
        sta buf + 5,y
@next:  tya
        clc
        adc #8
        tay
        inx
        inx
        inx
        inx
        txa
        and #$7F
        beq :+
        jmp @sprite
:
.endmacro

.export oam_dma_a
oam_dma_a:
        php
        pha
        phx
        phy
        lda oam_ready
        bne @ready
        jsr convert_oam
@ready: stz oam_ready
        stz OAMADDL
        stz OAMADDH
        stz DMAP5
        lda #<OAMDATA
        sta BBAD5
        lda #<oam_buf
        sta A1T5L
        lda #>oam_buf
        sta A1T5H
        stz A1B5
        stz DAS5L
        lda #2
        sta DAS5H
        lda #$20
        sta MDMAEN
        ply
        plx
        pla
        plp
        rts

; The game calls this when the frame is done and it will wait for vblank: the time to
; convert its sprites, since that takes most of a vblank. The code it replaces is
; lda #$AC, sta $F0.
.export frame_done
frame_done:
        phx
        phy
        jsr convert_oam
        lda force_blank
        beq @on
        jsr end_run
        ldx #7
:       jsr load_top_slot
        dex
        bpl :-
@on:
        lda #1
        sta oam_ready
        lda #$AC
        sta $F0
        ply
        plx
        rts

convert_oam:
        php
        stz obj_used + 4
        stz obj_used + 5
        stz obj_used + 6
        stz obj_used + 7
        convert_sprites oam_buf, 0
        convert_sprites oam_buf + 256, $80
        plp
        rts

; ---- Sound ------------------------------------------------------------------------

sb_data_w:
        phx
        ldx sb_cmd
        sta sb_regs,x
        plx
        pla
        plp
        rts

.export sb_cmd_a, sb_cmd_x, sb_cmd_y
sb_cmd_a:
        php
        pha
        and #$0F
        sta sb_cmd
        pla
        plp
        rts
sb_cmd_x:
        php
        pha
        txa
        and #$0F
        sta sb_cmd
        pla
        plp
        rts
sb_cmd_y:
        php
        pha
        tya
        and #$0F
        sta sb_cmd
        pla
        plp
        rts

; ---- Start-up, called from the boot code ------------------------------------------

.export runtime_init
runtime_init:
        lda #<fme_back
        sta back_ptr
        lda #>fme_back
        sta back_ptr + 1
        lda #$80
        sta force_blank
        lda #$FF
        sta w6_bank
        sta data_left
        ldx #7
:       sta obj2_have,x
        dex
        bpl :-
        rts

; lda $2007, which the game only does in code that never ran in the survey.
.segment "WCODE"
.export ppu_data_read_a, ppu_data_read_x, ppu_data_read_y
ppu_data_read_a:
        lda #0
        rts
ppu_data_read_x:
        ldx #0
        rts
ppu_data_read_y:
        ldy #0
        rts
