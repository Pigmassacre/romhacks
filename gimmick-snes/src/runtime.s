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
.import ComboIdx8, ComboIdxA, ComboIdxC, ComboTable

; VRAM layout, as word addresses.
BGSET_HI   = $20            ; three 4 KB tile sets, $1000 words apart, from $2000
MAP_HI     = $60            ; nametable A at $6000, B at $6400
HIDDEN_Y   = $F0
CROP_TOP   = 8              ; the SNES's 224 lines start this far down the NES's 240

.segment "WVARS"
.export nmi_ptr, irq_ptr, nmi_flags, split_n, split_open, set_have
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
force_blank: .res 1
vram_step:   .res 1
split_n:     .res 1         ; how many splits have changed the background's tiles this frame
split_open:  .res 1         ; a split has changed tiles and not yet shown them
tmp:         .res 4
attr_new:    .res 1
attr_col:    .res 1
attr_row:    .res 1
attr_lo:     .res 1
attr_hi:     .res 1
chr_obj:     .res 8         ; loaded in the sprite tables
set_want:    .res 12        ; BG slots 4-7 for each of the three tile sets
set_have:    .res 12
.export apu_regs, sb_cmd, sb_regs, apu_kick
apu_regs:    .res 32
apu_kick:    .res 4
sb_cmd:      .res 1
sb_regs:     .res 16
hdma_tab:    .res 16
.export hdma_tab
attr_shadow: .res 128
oam_buf:     .res 512

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
        .word fme_done, fme_prg8, fme_prgA, fme_prgC
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
fme_switch:
        ldx b8
        lda f:ComboIdx8,x
        ldx bA
        clc
        adc f:ComboIdxA,x
        ldx bC
        clc
        adc f:ComboIdxC,x
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
        bra fme_done

fme_mirror:
        and #3
        sta mirror
        tax
        lda mirror_sc,x
        sta BG1SC
        bra fme_done
mirror_sc:
        .byte MAP_HI | 1, MAP_HI | 2, MAP_HI, MAP_HI | 4

fme_irqlo:
        sta irq_lo
        bra fme_done
fme_irqhi:
        sta irq_hi
        bra fme_done

; Bits 0 and 7 enable the interrupt and the count. Any write acknowledges it.
fme_irqctl:
        and #$81
        cmp #$81
        beq :+
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
        sta tmp
        lda RDMPYH
        adc #0
        lsr a
        ror tmp
        lsr a
        ror tmp             ; lines from now
        bne @never          ; 256 or more
        ; Where is the beam? In vblank the NES is at line 241, 21 before line 0.
        lda SLHV
        lda OPVCT
        sta tmp + 1
        lda OPVCT
        and #1
        bne @vblank
        lda tmp + 1
        cmp #225
        bcc @line
@vblank:
        ; lines - 29 is the first line on the SNES, unless that is before the picture.
        lda tmp
        sec
        sbc #21 + CROP_TOP
        bcs @set
        lda #0
        bra @set
@line:  clc
        adc tmp
        bcs @never
@set:   cmp #225
        bcs @never
        sta VTIMEL
        stz VTIMEH
        lda nmi_flags
        ora #$20
        sta NMITIMEN
        rts
@never: lda nmi_flags
        sta NMITIMEN
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
        sta tmp + 3
        lda OPVCT
        and #1
        bne @no             ; lines 256-261
        lda tmp + 3
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
        cpx #4
        bcc @obj
        ; The first tile set, for the top of the picture
        tya
        sta set_want - 4,x
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
@obj:   tya
        cmp chr_obj,x
        beq @out
        jsr may_dma
        bcc @out
        sta chr_obj,x
        jsr dma_obj_page
@out:   jmp fme_done
@split: cpx #4
        bcc @out            ; the picture below a split has no sprites
        ; A further tile set for what comes below. It can only be copied in vblank, so
        ; the first frame of a new set still shows the old one.
        lda split_open
        bne @have
        lda split_n
        cmp #2
        bcs @out
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
        bra @out

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

; At the next line, show the tile set the split changed to, if it has been copied.
show_split_set:
        lda split_open
        beq @out
        stz split_open
        lda split_n
        asl a
        asl a
        tax
        ldy #4
:       lda set_want,x
        cmp set_have,x
        bne @out
        inx
        dey
        bne :-
        lda split_n
        clc
        adc #BGSET_HI >> 4
        sta BG12NBA
@out:   rts

wait_hblank:
:       bit HVBJOY
        bvs :-
:       bit HVBJOY
        bvc :-
        rts

; Copy a page of tile sets 1 and 2 that a split asked for. From the NMI, once a frame.
.export load_split_sets
load_split_sets:
        ldx #4
@next:  lda set_want,x
        cmp set_have,x
        bne @load
        inx
        cpx #12
        bne @next
        rts
@load:  sta set_have,x
        tay
        lda #$80
        sta VMAINC
        stz VMADDL
        ; x = set * 4 + slot. Sets are $1000 words apart and slots $200.
        txa
        and #$FC
        asl a
        asl a
        sta tmp
        txa
        and #3
        asl a
        ora tmp
        clc
        adc #BGSET_HI
        sta VMADDH
        jmp dma_bg_page

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
reg_stub "ppu_data", ppu_data_w
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
        ; bit 0 sprites, bit 1... put them where TM wants them
        tay
        and #2
        lsr a
        sta tmp
        tya
        and #1
        asl a
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
        jsr wait_hblank
        jsr apply_h
        jmp show_split_set

; $2006 with the picture on moved v, so y jumps too: this line shows row y of the map.
mid_scroll_v:
        jsr t_y
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
        jsr wait_hblank
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
        stz VMAINC
        sta VMADDH
        lda ppu_vlo
        sta VMADDL
        sty VMDATAL
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
        lda ppu_vlo
        and #$1F
        tax
        lda palette_index,x
        sta CGADD
        tya
        and #$3F
        tax
        lda f:ColorLo,x
        sta CGDATA
        lda f:ColorHi,x
        sta CGDATA
        ; $3F00 and $3F10 are one colour, the backdrop.
        lda ppu_vlo
        and #$0F
        bne @next
        stz CGADD
        lda f:ColorLo,x
        sta CGDATA
        lda f:ColorHi,x
        sta CGDATA
        bra @next

; An attribute byte (in y) sets the palette of the 16 tiles in its 4 quarters.
ppu_attr:
        lda tmp
        beq :+
        lda #64
:       sta tmp + 1
        lda ppu_vlo
        and #$3F
        sta tmp + 2         ; index 0-63
        clc
        adc tmp + 1
        tax
        tya
        eor attr_shadow,x
        bne :+
        jmp @out
:
        sta tmp + 3         ; the bits that changed
        tya
        sta attr_shadow,x
        sta attr_new
        lda #$80
        sta VMAINC
        lda tmp + 2
        and #7
        asl a
        asl a
        sta attr_col
        lda tmp + 2
        lsr a
        lsr a
        lsr a
        sta attr_row
        ldx #0
@quarter:
        lda tmp + 3
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
        ora tmp
        ora #MAP_HI
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
@same:  lsr tmp + 3
        lsr tmp + 3
        lsr attr_new
        lsr attr_new
        inx
        cpx #4
        beq @out
        jmp @quarter
@out:   rts

; ---- $4014: sprites ---------------------------------------------------------------

; NES sprites 8x16 each become two SNES sprites, since it has no size that shape. Each
; keeps its place in the order, so priority comes out the same.
.macro convert_sprites buf, first
.local @sprite, @hide, @stored, @flip, @next
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
        lda $0202,x
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
        bne @sprite
.endmacro

.export oam_dma_a
oam_dma_a:
        php
        pha
        phx
        phy
        convert_sprites oam_buf, 0
        convert_sprites oam_buf + 256, $80
        stz OAMADDL
        stz OAMADDH
        stz DMAP7
        lda #<OAMDATA
        sta BBAD7
        lda #<oam_buf
        sta A1T7L
        lda #>oam_buf
        sta A1T7H
        stz A1B7
        stz DAS7L
        lda #2
        sta DAS7H
        lda #$80
        sta MDMAEN
        ply
        plx
        pla
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
