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

.import ColorLo, ColorHi, AttrTable, ChrObjBanks, PageAlias, M7Anim
.import ComboIdx8, ComboIdxA, ComboTable

; VRAM layout, as word addresses.
OBJ2_HI    = $40            ; a second pair of sprite tables, for below a split
BGSET_HI   = $20            ; the first tile set of three: see set_hi
CLOUD_PAGE = 1              ; the CHR page of clouds, for parallax
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
irq_next:    .res 1         ; and the next one's: it becomes irq_line when it starts
.export irq_line, irq_next
opt_flags:   .res 1         ; Gimmick! 1.5's features: bit 0 up, in the menu's order
raw_pad:     .res 1         ; the pad, in the same order as the game's $F5
pad_prev:    .res 1
menu_open:   .res 1
menu_at:     .res 1
is_title:    .res 1
scroll_done: .res 1
map7:        .res 1         ; the world map is showing, in Mode 7
map7_t:      .res 1
tm_mask:     .res 1         ; layers it allows
parallax:    .res 1
band_pal:    .res 1
cam_lo:      .res 1
cam_hi:      .res 1
cam_prev:    .res 2
cam_acc:     .res 2
tm_now:      .res 1         ; what the game has switched on
overlay:     .res 1         ; and BG3, on the title screen or behind clouds
in_split:    .res 1         ; a split's interrupt has run this frame
.export in_split
.export irq_flag
force_blank: .res 1
vram_step:   .res 1
split_n:     .res 1         ; how many splits have changed the background's tiles this frame
split_open:  .res 1         ; this split's interrupt has started its own tile set
.export split_open
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
obj2_ready:  .res 1         ; the second tables hold what the last frame's splits asked for
obj_used:    .res 8         ; sprites use this slot of the second table: see convert_oam
set_wr:      .res 12        ; a split wrote this slot itself, so it must be copied soon
nmi_count:   .res 1
.export obj2_have
.export apu_regs, sb_cmd, sb_regs, apu_kick
apu_regs:    .res 32
apu_kick:    .res 5         ; new notes on the four channels, and DPCM started
apu_sent:    .res 24
sb_sent:     .res 16
bank_sent:   .res 1
spc_count:   .res 1
sb_cmd:      .res 1
sb_regs:     .res 16
hdma_tab:    .res 16
.export hdma_tab
attr_shadow: .res 128
oam_buf:     .res 544       ; with the high table, all zeros: small sprites, x under 256
data_left:   .res 1         ; tile writes that can go straight to VRAM, without a look at v
.export pal_dirty, cg_bg, cg_obj
pal_dirty:   .res 1
w6_bank:     .res 1
oam_ready:   .res 1
vf_limit:    .res 1         ; the line vram_flush may go on to work on colours until
oam_sent:    .res 1         ; nmi_work has sent this frame's sprites
scroll_hold: .res 1         ; $2000 comes next, with the rest of this split's scroll
split_cnt:   .res 1         ; scroll changes in this frame's splits
bg_at:       .res 1         ; the one that changed the tile set last frame
bg_at_new:   .res 1
spr_tmp:     .res 3         ; not tmp: a split's interrupt can land in the middle of the sprites, and uses that
load_first:  .res 1         ; the one stale sprite page this frame's sprites may wait on: see spr_check
band_n:      .res 1         ; the portal's blank sprites: see spr_check
band_top:    .res 1
band_end:    .res 1
band_tab:    .res 10
.export band_tab
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
        and #$3F
        sta b8
        bra fme_switch
fme_prgA:
        and #$3F
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
        ; From the NMI, count from the NES's line 241, 21 before its line 0. From a split,
        ; count from the line that split was meant for. Not by where the beam is: the game's
        ; NMI can start after vblank, when there is a lot to do first.
        lda in_split
        bne @line
        ; lines - 29 is the first line on the SNES, unless that is before the picture.
        lda itmp
        sec
        sbc #21 + CROP_TOP - 2  ; 2: where the game's handler has got to on the NES
        bcs @set
        lda #0
        bra @set
@line:  lda irq_line
        clc
        adc itmp
        bcs @never
@set:   cmp #225
        bcs @never
        sta irq_next
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
        bcc @out            ; a wait for the line here would make what follows late
        ; A further tile set for what comes below. It can only be copied in vblank, so
        ; the first frame of a new set still shows the old one.
        lda split_open
        bne @have
        lda split_n
        bne @flip           ; there is one further tile set
        inc split_n
        inc split_open
        lda split_cnt
        sta bg_at_new
        lda #0
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
@flip:  jsr show_split_set
        jmp fme_done

; Bring slot x up to date, if there is time. Keeps x.
load_top_slot:
        cpx #4
        bcc @obj
        lda map7
        bne @obj            ; the tile sets' place is the island's, for now
        lda set_want - 4,x
        cmp set_have - 4,x
        beq @obj
        jsr may_dma
        bcc @obj
        sta set_have - 4,x
        tay
        lda #$80
        sta VMAINC
        stz VMADDL
        txa
        and #3
        asl a
        asl a
        ora #BGSET_HI
        sta VMADDH
        jsr dma_bg_page
@obj:   ldy chr_want,x
        cpx #4
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

; Page in y; the VRAM address is set. Keeps y. Background tiles are 4 bits a pixel, as
; sprites are, and come from the same place: pages from $80 are the versions for parallax.
dma_bg_page:
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
set_hi: .byte BGSET_HI, $30

; At the next line, show the tiles and sprites a split changed to, once they are copied.
show_split_set:
        jsr flip_sprites
flip_bg:
        lda split_n
        beq flip_out
        asl a
        asl a
        tax
        ldy #4
@wr:    lda set_wr,x
        beq :+
        lda set_want,x
        cmp set_have,x
        bne flip_out
:       inx
        dey
        bne @wr
        jsr wait_line
        ldx split_n
flip_set:
        lda set_hi,x
        lsr a
        lsr a
        lsr a
        lsr a
        sta BG12NBA
        ; Below the split the backdrop is the game's again, not the sky, and no clouds.
        lda parallax
        beq flip_out
        lda tm_now
        sta TM
        stz CGADD
        lda cg_bg
        sta CGDATA
        lda cg_bg + 1
        sta CGDATA
flip_out:
        rts

; A split changes scroll and then tiles, and those stubs take lines to get through, where the
; NES takes moments. So on the scroll change that was followed by new tiles last frame, the
; tiles change too, if they are copied. The beam is in this line's hblank.
split_early:
        inc split_cnt
        lda split_cnt
        cmp bg_at
        bne flip_out
        ldx #4
:       lda set_want,x
        cmp set_have,x
        bne flip_out
        inx
        cpx #8
        bne :-
        ldx #1
        bra flip_set

; Below the first split, the sprites use what the splits left the pages as last frame.
flip_sprites:
        lda split_flip
        bne @out
        lda obj2_ready
        beq @out
        jsr wait_line
        lda #OBJ2_HI >> 5
        sta OBSEL
        inc split_flip
@out:   rts


.segment "BOOT"             ; only ever called from the NMI, in bank 0: there is room here

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
        ; Sprites before anything that could use up vblank. The game would send them next, if
        ; it has finished the frame.
        lda $F0
        cmp #$AC
        bne @not_done
        lda oam_ready
        beq @not_done
        jsr oam_send
        lda #1
        sta oam_sent
@not_done:
        jsr commit_palette
        jsr map_now
        lda map7
        beq :+
        jsr bg2_now
        rts
:
        stz split_n
        stz split_open
        stz split_cnt
        lda bg_at_new
        sta bg_at
        stz bg_at_new
        stz split_flip
        stz irq_line
        stz in_split
        stz OBSEL
        lda #BGSET_HI >> 4
        sta BG12NBA
        lda #$40
        sta HDMAEN
        jsr scroll_now
        jsr bg2_now
        jsr band_now
        jsr menu_tick
        lda force_blank
        bne :+              ; the main thread may be using VRAM
        ; Tiles, while there is sure to be time: the game's own call then finds its buffer empty.
        lda $F0
        cmp #$AC
        bne @no_tiles
        stz vf_limit
        jsr vram_flush_now
@no_tiles:
        ; Then sprites' pages, colours, the pages for below a split, and more colours.
        jsr top_pages
        bcs @copied         ; that was the time there was
        lda #240
        jsr attr_work
        lda attr_head
        cmp attr_tail
        bne @copied         ; colours first: tiles in the wrong palette show for longer
        jsr beam
        cmp #225
        bcc @copied         ; vblank has already gone
        cmp #244
        bcs @copied         ; a page would not finish in time
        jsr load_page
@copied:
        lda #252
        jsr attr_work
        ; Ready, if the slots that matter have what they asked for.
        ldy #1
        ldx #4
@rdy:   lda obj2_want,x
        cmp obj2_have,x
        beq @rdy2
        ldy #0
@rdy2:  dex
        bpl @rdy
        sty obj2_ready
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

; What the game has mapped for the top of the picture, before anything else takes up vblank:
; by the time it says so itself, in chr_all, there is rarely time left. Sprites first, starting
; with the one the sprites are waiting on. Carry set if anything was copied.
top_pages:
        lda $F0
        cmp #$AC
        bne @none           ; the game is part way through a frame
        stz tmp
        ldx load_first
        bmi :+
        jsr top_obj
:       ldx #0
@obj:   cpx #4
        bcc :+
        lda obj_used,x
        beq @obj_next
:       jsr top_obj
        bcs @done
@obj_next:
        inx
        cpx #8
        bne @obj
        ; The background's pages wait for colours: tiles in the wrong palette show for longer.
        lda attr_head
        cmp attr_tail
        bne @done
        ldx #4
@bg:    lda set_want - 4,x
        cmp set_have - 4,x
        beq @bg_next
        jsr top_room
        bcs @done
        sta set_have - 4,x
        tay
        lda #$80
        sta VMAINC
        stz VMADDL
        txa
        and #3
        asl a
        asl a
        ora #BGSET_HI
        sta VMADDH
        jsr dma_bg_page
        inc tmp
@bg_next:
        inx
        cpx #8
        bne @bg
@done:  lda tmp
        beq @none
        sec
        rts
@none:  clc
        rts

; Slot x, if it needs it and there is time. Carry set when there is none.
top_obj:
        lda $E1,x
        cmp chr_obj,x
        beq @ok
        jsr top_room
        bcs @out
        sta chr_obj,x
        tay
        jsr dma_obj_page
        inc tmp
@ok:    clc
@out:   rts

; Room for one more page? One always; a second if the game has no tiles to send. Keeps a.
top_room:
        pha
        jsr beam
        cmp #225
        bcc @no             ; vblank has already gone
        cmp #246
        bcs @no             ; it would not finish in time
        lda tmp
        beq @yes
        cmp #2
        bcs @no
        lda $FA
        bne @no
        lda attr_head
        cmp attr_tail
        bne @no
        jsr beam
        cmp #238            ; or the sprites themselves would be late
        bcs @no
@yes:   pla
        clc
        rts
@no:    pla
        sec
        rts

; The portal hides what is coming out of it with the NES's limit of 8 sprites on a line: 8
; blank ones at once, ahead of the rest. The SNES has no such limit, so sprites go off for
; those lines. The table is lines, then TM's value for them.
band_now:
        lda #$40
        ldx band_n
        cpx #8
        bcc @off
        lda tm_now
        ora overlay
        and tm_mask
        sta tmp + 2
        lda band_top
        beq @off2
        cmp #$80
        bcs @off2           ; never so low
        sta band_tab
        lda tmp + 2
        sta band_tab + 1
        lda band_end
        sec
        sbc band_top
        clc
        adc #16
        cmp #$80
        bcs @off2
        sta band_tab + 2
        lda tmp + 2
        and #$EF
        sta band_tab + 3
        lda #1
        sta band_tab + 4
        lda tmp + 2
        sta band_tab + 5
        stz band_tab + 6
        lda #$50
@off:   sta HDMAEN
        rts
@off2:  lda #$40
        sta HDMAEN
        rts

; The options menu, from the title screen. It sits on BG3 in place of the notices.
MENU_MAP   = $7800
MENU_ITEMS = 5
.import MenuRowLo, MenuRowHi
menu_tick:
        lda raw_pad
        tay
        eor pad_prev
        sty pad_prev
        and raw_pad
        sta itmp            ; newly pressed
        lda is_title
        bne @title
        stz menu_open
        rts
@title: lda menu_open
        bne @open
        lda itmp
        and #$20            ; Select
        beq @out
        inc menu_open
        stz menu_at
        jmp menu_draw
@open:  lda itmp
        beq @out
        and #$20
        beq :+
        stz menu_open
        rts
:       lda itmp
        and #$08            ; Up
        beq :+
        dec menu_at
        bpl @moved
        lda #MENU_ITEMS - 1
        sta menu_at
        bra @moved
:       lda itmp
        and #$04            ; Down
        beq :+
        inc menu_at
        lda menu_at
        cmp #MENU_ITEMS
        bcc @moved
        stz menu_at
        bra @moved
:       lda itmp
        and #$D3            ; A, B, Start, Left, Right: switch it
        beq @out
        ldx menu_at
        lda f:menu_bits,x
        eor opt_flags
        sta opt_flags
        ; Tap mode is the game's now: this is where it starts from, and Select changes it.
        ldx #0
        and #OPT_TAP
        beq :+
        inx
:       stx TAP_MODE
@moved: jmp menu_draw
@out:   rts

menu_bits:
        .byte OPT_RECALL, OPT_SKIP, OPT_TAP, OPT_COYOTE, OPT_BUFFER

; The cursor and every item's ON or OFF, in the low bytes of the map.
menu_draw:
        stz VMAINC
        ldy #0
@row:   tyx
        lda f:MenuRowLo,x
        sta itmp + 1
        lda f:MenuRowHi,x
        sta itmp + 2
        lda itmp + 1
        sta VMADDL
        lda itmp + 2
        sta VMADDH
        ldx #0              ; blank
        cpy menu_at
        bne :+
        ldx #94             ; the arrow
:       stx VMDATAL
        lda itmp + 1
        clc
        adc #18
        sta VMADDL
        lda itmp + 2
        adc #0
        sta VMADDH
        tyx
        lda f:menu_bits,x
        and opt_flags
        beq @off
        lda #15             ; O
        sta VMDATAL
        lda #14             ; N
        sta VMDATAL
        stz VMDATAL
        bra @next
@off:   lda #15             ; O
        sta VMDATAL
        lda #6              ; F
        sta VMDATAL
        sta VMDATAL
@next:  iny
        cpy #MENU_ITEMS
        bne @row
        rts

; The world map, in Mode 7. It is the screen with $4A = 0 and these pages for the background,
; with $90 at 0 the first time, from the title, and 1 after a stage.
MODE7_BANK = $DA
M7_FRAMES  = 72
M7_AT      = 48 * 8
map_now:
        lda map7
        bne @on
        lda $4A
        bne @out
        lda $E5
        cmp #$54
        bne @out
        lda $E6
        cmp #$55
        bne @out
        jmp map_enter
@on:    lda $4A
        bne @leave
        lda $E5
        cmp #$54
        bne @leave
        lda map7_t
        cmp #M7_FRAMES
        bcs @rest
        ; Matrix for this frame
        asl a
        asl a
        asl a
        tax
        ldy #0
:       lda f:M7Anim,x
        sta M7A,y
        lda f:M7Anim + 1,x
        sta M7A,y
        inx
        inx
        iny
        cpy #4
        bne :-
        inc map7_t
@out:   rts
@rest:  bne @out
        ; The last frame: square on, and the sprites line up with it.
        inc map7_t
        stz M7A
        lda #1
        sta M7A
        stz M7B
        stz M7B
        stz M7C
        stz M7C
        stz M7D
        lda #1
        sta M7D
        lda #$FF
        sta tm_mask
        lda tm_now
        sta TM
        rts
@leave: stz map7
        lda #$09
        sta BGMODE
        stz M7SEL
        stz OBSEL
        stz obj_base
        lda #$FF
        sta tm_mask
        ; Everything in the first half of VRAM has gone: ask for it again.
        ldx #7
:       sta set_have,x
        sta chr_obj,x
        sta obj2_have,x
        dex
        bpl :-
        rts

map_enter:
        ; This takes more than a frame: no NMI inside this NMI.
        stz NMITIMEN
        lda #$80
        sta INIDISP
        stz HDMAEN
        ; Mode 7's map bytes then its tile bytes, 16 KB each
        stz VMAINC
        stz VMADDL
        stz VMADDH
        lda #0
        sta DMAP7
        lda #<VMDATAL
        sta BBAD7
        stz A1T7L
        stz A1T7H
        lda #MODE7_BANK
        sta A1B7
        stz DAS7L
        lda #$40
        sta DAS7H
        lda #$80
        sta MDMAEN
        sta VMAINC
        stz VMADDL
        stz VMADDH
        lda #<VMDATAH
        sta BBAD7
        stz A1T7L
        lda #$40
        sta A1T7H
        lda #MODE7_BANK
        sta A1B7
        stz DAS7L
        lda #$40
        sta DAS7H
        lda #$80
        sta MDMAEN
        ; Sprites from the second tables, as the first half of VRAM is the island now.
        lda #OBJ2_HI
        sta obj_base
        lda #OBJ2_HI >> 5
        sta OBSEL
        ldx #7
:       lda $E1,x
        sta chr_want,x
        sta chr_obj,x
        tay
        jsr dma_obj_page
        dex
        bpl :-
        lda #7
        sta BGMODE
        lda #$80            ; nothing outside the map
        sta M7SEL
        lda #<(M7_AT + 128)
        sta M7X
        lda #>(M7_AT + 128)
        sta M7X
        lda #<(M7_AT + 112 + 7)
        sta M7Y
        lda #>(M7_AT + 112 + 7)
        sta M7Y
        lda #<M7_AT
        sta BG1HOFS
        lda #>M7_AT
        sta BG1HOFS
        lda #<(M7_AT + 7)
        sta BG1VOFS
        lda #>(M7_AT + 7)
        sta BG1VOFS
        lda #1
        sta map7
        stz map7_t
        sta tm_mask         ; the island alone, until it has arrived
        sta TM
        lda force_blank
        bne :+
        lda #$0F
        sta INIDISP
:       bit RDNMI
        lda nmi_flags
        ora irq_flag
        sta NMITIMEN
        rts

; The game writes its scroll near the end of its NMI, later than the SNES's vblank allows.
; It has already decided: $FD, $FC and $FF if it finished the frame, or last time's.
scroll_now:
        stz scroll_done
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
        inc scroll_done
        ; The camera, as 9 bits
        lda ppu_tlo
        asl a
        asl a
        asl a
        ora ppu_finex
        sta cam_lo
        lda ppu_thi
        lsr a
        lsr a
        and #1
        sta cam_hi
@out:   rts

; BG3: the notices on the title screen, clouds behind stages that have them. $4A is 1 in
; play, where the clouds' page is at $E6 or $E7.
bg2_now:
        ldx #0
        stx parallax
        stx is_title
        bra @begin
@off:   jmp @really_off
@done2: jmp @done
@begin: lda $4A
        cmp #2              ; the title, coming back to it
        beq @title
        cmp #3
        bne @not_title
        lda $90             ; the title the first time; the credits have this set
        bne @off
@title: lda $E6
        cmp #$65            ; 4A = 2 is also the credits, with other pages
        bne @off
        lda #1
        sta is_title
        lda menu_open
        beq :+
        lda #$78
        bra :++
:       lda #$6C
:       sta BG3SC
        stz BG3HOFS
        stz BG3HOFS
        stz BG3VOFS
        stz BG3VOFS
        ldx #4
        bra @done2
@not_title:
        cmp #1
        bne @off
        lda $90
        beq @off
        lda $E6
        cmp #CLOUD_PAGE
        beq :+
        lda $E7
        cmp #CLOUD_PAGE
        bne @off
:       ldy $1B
        cpy #7
        bcs @off
        lda cloud_sc,y
        beq @off
        sta BG3SC
        inc parallax
        lda cloud_pal,y
        cmp band_pal
        beq :+
        sta band_pal
        lda #1
        sta pal_dirty
:       lda cloud_y,y
        sta BG3VOFS
        lda cloud_yh,y
        sta BG3VOFS
        ; Half the camera's speed: a jump is a new screen, not movement.
        lda cam_lo
        sec
        sbc cam_prev
        sta tmp + 2
        lda cam_hi
        sbc cam_prev + 1
        and #1              ; 9 bits, so x is -256 to 255
        beq :+
        lda tmp + 2
        cmp #$C0
        bcs @neg
        bra @moved
:       lda tmp + 2
        cmp #$40
        bcs @moved
        clc
        adc cam_acc
        sta cam_acc
        bcc @moved
        inc cam_acc + 1
        bra @moved
@neg:   clc
        adc cam_acc
        sta cam_acc
        bcs @moved
        dec cam_acc + 1
@moved: lda cam_lo
        sta cam_prev
        lda cam_hi
        sta cam_prev + 1
        lda cam_acc + 1
        lsr a
        sta tmp + 3
        lda cam_acc
        ror a
        sta BG3HOFS
        lda tmp + 3
        and #3
        sta BG3HOFS
        ; The sky is the backdrop now: the colour that was its tile.
        lda band_pal
        asl a
        asl a
        asl a
        tax
        stz CGADD
        lda cg_bg + 2,x
        sta CGDATA
        lda cg_bg + 3,x
        sta CGDATA
        ldx #4
        bra @done
@really_off:
        ldx #0
        ; Without parallax the backdrop is the game's own.
        stz CGADD
        lda cg_bg
        sta CGDATA
        lda cg_bg + 1
        sta CGDATA
@done:  stx overlay
        lda tm_now
        beq :+
        ora overlay
        and tm_mask
        sta TM
:       rts

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
        cpx #8
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
        cpx #8
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
        ; x = 4 + slot, and slots are $400 words.
        txa
        and #3
        asl a
        asl a
        ora #$30
        sta VMADDH
        jmp dma_bg_page

; Send the colours the game has changed. From the NMI.
commit_palette:
        lda pal_dirty
        beq @out
        stz pal_dirty
        ; BG1 is 16 colours a palette: the NES's three, then the backdrop's colour for its
        ; black when that has to be solid. BG3's are in the gaps, 5-7 for the clouds.
        ldy #0
@pal:   tya
        asl a
        asl a
        asl a
        asl a
        ina
        sta CGADD
        tya
        asl a
        asl a
        asl a
        tax
        lda cg_bg + 2,x
        sta CGDATA
        lda cg_bg + 3,x
        sta CGDATA
        lda cg_bg + 4,x
        sta CGDATA
        lda cg_bg + 5,x
        sta CGDATA
        lda cg_bg + 6,x
        sta CGDATA
        lda cg_bg + 7,x
        sta CGDATA
        lda cg_bg
        sta CGDATA
        lda cg_bg + 1
        sta CGDATA
        iny
        cpy #4
        bne @pal
        lda band_pal
        asl a
        asl a
        asl a
        tax
        lda #5
        sta CGADD
        inx
        inx
        ldy #6
:       lda cg_bg,x
        sta CGDATA
        inx
        dey
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

.segment "WCODE"

; For each stage: BG2's map (0 for none), the palette its clouds use and where they sit.
cloud_sc:  .byte $70, $70, $00, $74, $00, $00, $00
cloud_pal: .byte 1, 1, 0, 3, 0, 0, 0
cloud_y:   .byte <(7), <(7 - 40), 0, <(7), 0, 0, 0
cloud_yh:  .byte >(7), >(7 - 40), 0, >(7), 0, 0, 0

; $F06B in the game: slots 0-7 from $E1-$E8, in vblank. The same, without eight trips
; through the FME-7's registers. X and Y are the caller's.
.export chr_all
chr_all:
        phx
        phy
        ldx #7
@slot:  lda $E1,x
        sta chr_want,x
        cpx #4
        bcc :+
        ; With parallax the page's version with see-through sky takes its place.
        ldy parallax
        beq @plain
        phx
        tax
        lda f:PageAlias,x
        plx
@plain: sta set_want - 4,x
:       lda force_blank
        bne :+
        jsr load_top_slot   ; which also picks up what there was no time for last frame
:       dex
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
reg_stub "ppu_scroll_hold", ppu_scroll_hold_w
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

; The last $2005 before a $2000, as a split's handler has it: the scroll takes effect in one
; go, at the $2000, or the lines between would show the wrong nametable.
ppu_scroll_hold_w:
        lda #1
        sta scroll_hold
        pla
        pha
        jmp ppu_scroll_w

ppu_ctrl_w:
        phx
        phy
        tay
        eor ppu_ctrl
        sta tmp + 1         ; what changed
        sty ppu_ctrl
        and #$FB
        bne @full
        lda scroll_hold
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
        stz scroll_hold
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
        beq :+
        cmp nmi_flags
        beq :+
        ; This can bring an NMI at once, here, before the game has reached its wait for
        ; one, and that NMI would write the game's copy of this register back: set that.
        sty $44
:       sta nmi_flags
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
        sta tm_now
        ora overlay
        and tm_mask
        sta TM
        stz force_blank
        lda #$0F
        sta INIDISP
        jmp reg_done
@off:   lda #$80
        sta force_blank
        sta INIDISP
        stz tm_now
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
        stz scroll_hold
        jsr apply_scroll
        jmp reg_done
@on:    lda scroll_hold
        bne :+
        jsr mid_scroll
:       jmp reg_done

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
        lda map7
        bne :+
        lda scroll_done
        beq :++
:       rts                 ; nmi_work has set this frame's, and $2006 has since upset t
:       jsr apply_h
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
        jsr split_early
        jmp show_split_set
:       rts

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
        jsr split_early
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
        lda #255
        sta vf_limit
vram_flush_now:
        stz ppu_w
        ldy #0
        ldx #$FF
        stx data_left
@entry: cpy $FA
        bcc :+
        stz $FA
        lda vf_limit
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
        bcc :+
        jmp @slow
:       and #3
        cmp #3
        bne @fast
        lda ppu_vlo
        cmp #$C0 - 64       ; well short of the attributes, on the last page
        bcc @fast
        jmp @slow
@fast:  lda vram_step
        bne @column
        ; Would it leave the page?
        lda ppu_vlo
        clc
        adc vf_left
        bcc @run
        jmp @slow
@column:
        ; Would it reach the attributes? The game sends a column like this every frame.
        lda ppu_vhi
        and #3
        asl a
        asl a
        asl a
        sta tmp
        lda ppu_vlo
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        clc
        adc vf_left
        cmp #31
        bcc @run
        jmp @slow
@run:   phy
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
        ldx vram_step
        stx VMAINC
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
.local @sprite, @hide, @flip, @next, @even
        ldx #first
        ldy #0
@sprite:
        lda $0200,x
        cmp #$EF
        bcs @hide
        sbc #CROP_TOP - 2   ; carry is clear: subtract one more
        sta spr_tmp
        jsr spr_check
        bcs @hide
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
        sta spr_tmp + 1
@even:  lda $0202,x
        phx
        tax
        lda f:AttrTable,x
        plx
        ora spr_tmp + 1
        sta buf + 3,y
        sta buf + 7,y
        lda $0202,x
        bmi @flip
        lda spr_tmp
        sta buf + 1,y
        clc
        adc #8
        sta buf + 5,y
        bra @next
@flip:  lda spr_tmp
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
        lda oam_sent
        beq :+
        stz oam_sent
        bra @out
:       lda oam_ready
        bne @ready
        jsr convert_oam
@ready: jsr oam_send
@out:   ply
        plx
        pla
        plp
        rts

; All of OAM, by DMA. Past the end of vblank this would corrupt it, the high table for good
; if that were not sent too.
oam_send:
        stz oam_ready
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
        lda #<544
        sta DAS5L
        lda #2
        sta DAS5H
        lda #$20
        sta MDMAEN
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

; Sprite x of the game's: its CHR slot, and whether its page will be there in time. Only one
; stale page is sure to be copied in vblank, so sprites on any other stay off for this frame,
; since the NES's bank switch is instant and a sprite on the wrong page is garbage. Carry set
; to hide it. Keeps x and y; spr_tmp is the sprite's line.
spr_check:
        lda $0201,x
        cmp #$80
        bne @not_band
        lda $0202,x
        cmp #$20
        bne @not_band
        ; One of the portal's blanks
        lda band_n
        bne :+
        lda spr_tmp
        sta band_top
        sta band_end
:       inc band_n
        lda spr_tmp
        cmp band_top
        bcs :+
        sta band_top
:       cmp band_end
        bcc :+
        sta band_end
:       sec
        rts
@not_band:
        ; The status bar's sprites, whose second table is not ready: they would be garbage.
        lda obj2_ready
        bne :+
        lda $4A
        cmp #1
        bne :+
        lda $0200,x
        cmp #$C0
        bcc :+
        lda $90
        beq :+
        sec
        rts
:       phx
        lda $0201,x
        and #1
        asl a
        asl a
        sta spr_tmp + 2
        lda $0201,x
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora spr_tmp + 2
        tax
        cpx #4
        bcc :+
        lda #1
        sta obj_used,x
:       lda force_blank
        ora map7
        bne @ok
        lda $E1,x
        cmp chr_obj,x
        beq @ok
        lda load_first
        bmi @claim
        txa
        cmp load_first
        beq @ok
        plx
        sec
        rts
@claim: stx load_first
@ok:    plx
        clc
        rts

convert_oam:
        php
        lda #$FF
        sta load_first
        stz band_n
        stz obj_used + 4
        stz obj_used + 5
        stz obj_used + 6
        stz obj_used + 7
        convert_sprites oam_buf, 0
        convert_sprites oam_buf + 256, $80
        plp
        rts

; ---- Gimmick! 1.5, as options ---------------------------------------------------------

; Its hooks come here. Off: what the game had there. On: 1.5's own routine, by its far call.
; The carry says what 1.5's routines say, for the branch after the hook.
OPT_RECALL = 1
OPT_SKIP   = 2
OPT_TAP    = 4
OPT_COYOTE = 8
OPT_BUFFER = 16
FLOOR_F    = $0487          ; 1.5's RAM: see src/gimmick-1.5/defs.asm
JUMPBUF_ON = $048A
TAP_MODE   = $048B

.import Far_StarButton, Far_Jump, Far_FxDraw, Far_Water, Far_BHeld
.export opt_flags
.export opt_jump, opt_star, opt_bheld, opt_fx, opt_water, pad_read

; "A newly pressed and on the floor?" Coyote time, buffering and Select share a routine, so
; those that are off are kept from happening: no memory of the floor or of the press.
opt_jump:
        lda opt_flags
        and #OPT_TAP | OPT_COYOTE | OPT_BUFFER
        bne @on
        lda $F5
        and $036E
        cmp #1              ; carry set if not 0
        rts
@on:    lda opt_flags
        and #OPT_TAP
        bne :+
        lda $F5
        and #$DF            ; Select does nothing
        sta $F5
:       lda opt_flags
        and #OPT_COYOTE
        bne :+
        lda $ED
        sec
        sbc #8
        sta FLOOR_F
:       lda opt_flags
        and #OPT_BUFFER
        bne :+
        stz JUMPBUF_ON
:       jmp Far_Jump

; Skip the charge code while a star is thrown, in a tube or vanishing?
opt_star:
        lda opt_flags
        and #OPT_RECALL
        beq :+
        jmp Far_StarButton
:       lda $91
        cmp #1
        beq @skip
        cmp #2
        beq @skip
        cmp #$D0
        rts                 ; carry set from $D0
@skip:  sec
        rts

opt_bheld:
        lda opt_flags
        and #OPT_TAP
        beq :+
        jmp Far_BHeld
:       lda $F7
        and #$40
        cmp #$40
        rts

opt_fx:
        lda opt_flags
        and #OPT_RECALL | OPT_SKIP
        beq :+
        jmp Far_FxDraw
:       lda $9B
        sta $0424
        rts

opt_water:
        lda opt_flags
        and #OPT_SKIP
        beq :+
        jmp Far_Water
:       lda $C3
        sta $0397
        rts

; The game reads the pad here. A copy for the menu; with the menu open, the game sees nothing.
pad_read:
        lda $4016
        lsr a
        rol raw_pad
        lda menu_open
        beq :+
        lda #0
        rts
:       lda raw_pad
        and #1
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

; A store to APU register a: a channel's fourth register starts a note.
.export apu_indexed
apu_indexed:
        cmp #$10
        bcs @out
        tax
        and #3
        cmp #3
        bne @out
        txa
        lsr a
        lsr a
        tax
        inc apu_kick,x
@out:   rts

; Send the SPC700 what has changed. Called from the game's NMI, just after its sound code.
.export sound_hook
sound_hook:
        sta fme_cmd
        php
        pha
        phx
        phy
        ldx #$1E
        jsr spc_send
        ; The SPC700's sweep moves its copy of a period: a new note sends it again.
        ldy #3
@sw:    lda apu_kick,y
        beq :+
        tya
        asl a
        asl a
        tax
        lda apu_regs + 2,x
        eor #$FF
        sta apu_sent + 2,x
        lda apu_regs + 3,x
        eor #$FF
        sta apu_sent + 3,x
:       dey
        bpl @sw
        ldy #0
@apu:   lda apu_regs,y
        cmp apu_sent,y
        beq :+
        sta apu_sent,y
        tyx
        jsr spc_send
:       iny
        cpy #$16
        bne @apu
        ldy #0
@sb:    lda sb_regs,y
        cmp sb_sent,y
        beq :+
        sta sb_sent,y
        tya
        ora #$20
        tax
        lda sb_regs,y
        jsr spc_send
:       iny
        cpy #16
        bne @sb
        ; The new notes, whose length counter comes from a register sent just now
        ldy #0
@kick:  lda apu_kick,y
        beq :+
        lda #0
        sta apu_kick,y
        tya
        clc
        adc #$18
        tax
        lda #0
        jsr spc_send
:       iny
        cpy #4
        bne @kick
        lda bC
        cmp bank_sent
        beq :+
        sta bank_sent
        ldx #$1D
        jsr spc_send
:       lda apu_kick + 4
        beq :+
        stz apu_kick + 4
        lda apu_regs + $15
        ldx #$1C
        jsr spc_send
:       ldx #$1F
        jsr spc_send
        ply
        plx
        pla
        plp
        rts

; A value in a for the register in x.
spc_send:
        stx APUIO1
        sta APUIO2
        inc spc_count
        lda spc_count
        sta APUIO0
:       cmp APUIO0
        bne :-
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
        sta tm_mask
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
