; Power-on, the interrupt vectors and the cartridge header, in ROM bank 0.

.p816
.a8
.i8
.smart off

.include "hw.inc"

.import __WCODE_LOAD__, __WCODE_RUN__, __WCODE_SIZE__
.import band_tab, split_open, irq_line, irq_next, in_split, irq_flag, nmi_ptr, irq_ptr, cur_pbr, nmi_flags, hdma_tab, set_have
.import nmi_work, runtime_init
.import FirstBank, NesNmi, NesIrq, NesReset, SpcAddr, SpcSize, SpcEntry
SPC_BLOB = $D80000          ; tools/build.py puts these there
OVERLAY = $DE0000

.segment "BOOT"

reset:
        sei
        clc
        xce
        rep #$38
        .a16
        .i16
        ldx #$1FFF
        txs
        lda #0
        tcd
        sep #$20
        .a8
        ; Run from the fast mirror of this bank.
        jml $800000 | fast
fast:
        lda #1
        sta MEMSEL
        lda #$80
        sta INIDISP
        stz NMITIMEN
        stz HDMAEN
        stz MDMAEN

        ; Clear all of WRAM by DMA from a zero byte in ROM.
        stz WMADDL
        stz WMADDM
        stz WMADDH
        lda #$08
        sta DMAP7
        lda #<WMDATA
        sta BBAD7
        ldx #zero
        stx A1T7L
        stz A1B7
        stz DAS7L
        stz DAS7H
        lda #$80
        sta MDMAEN          ; 64 KB
        sta MDMAEN          ; 64 KB more

        ; The registers
        ldx #$2101
:       stz $00,x
        inx
        cpx #$2134
        bne :-
        ; VRAM
        lda #$80
        sta VMAINC
        stz VMADDL
        stz VMADDH
        lda #$09
        sta DMAP7
        lda #<VMDATAL
        sta BBAD7
        ldx #zero
        stx A1T7L
        stz A1B7
        stz DAS7L
        stz DAS7H
        lda #$80
        sta MDMAEN
        ; CGRAM
        stz CGADD
        ldx #512
:       stz CGDATA
        dex
        bne :-

        ; OAM: sprites out of the way, all small.
        stz OAMADDL
        stz OAMADDH
        ldx #128
:       stz OAMDATA
        lda #$F0
        sta OAMDATA
        stz OAMDATA
        stz OAMDATA
        dex
        bne :-
        ldx #32
:       stz OAMDATA
        dex
        bne :-

        ; The handlers, into RAM at $0800 and up
        lda #$00
        sta DMAP7
        lda #<WMDATA
        sta BBAD7
        ldx #__WCODE_RUN__
        stx WMADDL
        stz WMADDH
        ldx #__WCODE_LOAD__
        stx A1T7L
        stz A1B7
        ldx #__WCODE_SIZE__
        stx DAS7L
        lda #$80
        sta MDMAEN

        ; The sound driver, by the SPC700's boot code.
        sep #$10
        .i8
:       lda APUIO0
        cmp #$AA
        bne :-
:       lda APUIO1
        cmp #$BB
        bne :-
        rep #$10
        .i16
        ldx SpcAddr
        stx APUIO2
        lda #1
        sta APUIO1
        lda #$CC
        sta APUIO0
:       cmp APUIO0
        bne :-
        ldx SpcSize
        stx spc_size
        ldx #0
@spc:   lda f:SPC_BLOB,x
        sta APUIO1
        txa
        sta APUIO0
:       cmp APUIO0
        bne :-
        inx
        cpx spc_size
        bne @spc
        ldx SpcEntry
        stx APUIO2
        stz APUIO1
        lda spc_size
        ina
        ina
        bne :+
        ina
:       sta APUIO0

        ; The notices for the title screen: tiles and map, for BG2 and BG4.
        lda #$80
        sta VMAINC
        ldx #$6800
        stx VMADDL
        lda #1
        sta DMAP7
        lda #<VMDATAL
        sta BBAD7
        ldx #0
        stx A1T7L
        lda #^OVERLAY
        sta A1B7
        ldx #$1000
        stx DAS7L
        lda #$80
        sta MDMAEN
        ; The clouds' two maps, for parallax
        ldx #$7800
        stx VMADDL
        ldx #$1000
        stx A1T7L
        stx DAS7L
        lda #$80
        sta MDMAEN
        ; and the options menu's
        ldx #$3C00
        stx VMADDL
        ldx #$2000
        stx A1T7L
        ldx #$0800
        stx DAS7L
        lda #$80
        sta MDMAEN
        lda #$6C
        sta BG2SC
        ; Black, grey and white, for the notices: BG2's palette 2.
        lda #41
        sta CGADD
        stz CGDATA
        stz CGDATA
        lda #$73
        sta CGDATA
        lda #$4E
        sta CGDATA
        lda #$FF
        sta CGDATA
        lda #$7F
        sta CGDATA

        ; The picture: Mode 0. BG1 is the NES's background, with nothing in front of it but
        ; sprites and BG2, the notices. With parallax, BG3 has what is black in BG1, on the same
        ; map, with sprites that go behind the background between them, and BG4 is the sky.
        stz BGMODE
        lda #$70 | 1        ; maps at $7000, side by side to start with
        sta BG1SC
        sta BG3SC
        lda #$62            ; BG1's tiles at $2000, BG2's at $6000 (they start at tile 256)
        sta BG12NBA
        lda #$66            ; BG3's at $6000, BG4's as BG2's
        sta BG34NBA
        lda #$00            ; sprite tables at 0, 8x8 and 16x16
        sta OBSEL
        ; One window, over the leftmost 8 pixels, for when the game hides them.
        lda #$02
        sta W12SEL
        sta W34SEL
        lda #$02
        sta WOBJSEL
        stz WH0
        lda #7
        sta WH1
        ; Line-by-line vertical scroll
        lda #$02
        sta DMAP7 - $10
        lda #<BG1VOFS
        sta BBAD6
        ldx #hdma_tab
        stx A1T6L
        stz A1B6
        ; BG3 scrolls as BG1 does
        lda #$02
        sta DMAP7 - $40
        lda #<BG3VOFS
        sta BBAD6 - $30
        ldx #hdma_tab
        stx A1T6L - $30
        stz A1B6 - $30
        ; TM by line, for the portal: see band_now
        stz DMAP7 - $30
        lda #<TM
        sta BBAD6 - $20
        ldx #band_tab
        stx A1T6L - $20
        stz A1B6 - $20

        ; Unset tile-set pages can't match any page.
        ldx #0
        lda #$FF
:       sta set_have,x
        inx
        cpx #12
        bne :-

        sep #$10
        .i8
        jsr runtime_init
        rep #$10
        .i16

        ; Start the game: the NES's reset code, in the bank for its first mapping.
        lda f:FirstBank
        sta cur_pbr
        sta irq_ptr + 2
        sta tmp_ptr + 2
        pha
        plb
        rep #$20
        .a16
        lda f:NesNmi
        sta nmi_ptr
        lda f:NesIrq
        sta irq_ptr
        lda f:NesReset
        sta tmp_ptr
        lda #0
        sep #$20
        .a8
        sep #$10
        .i8
        sec
        xce
        ldx #$FF
        txs
        ; The NES starts with the APU quiet and interrupts masked.
        jml [tmp_ptr]

tmp_ptr = $1FF0
spc_size = $1FF4

; The vertical scroll's HDMA and the background's tile set restart with each frame.
nmi_emu:
        ; The fast mirror of this bank: no interrupt can land in this, which would lose the bank.
        jml $800000 | nmi_fast
nmi_fast:
        pha
        phx
        phy
        bit RDNMI
        jsr nmi_work
        ply
        plx
        pla
        jml [nmi_ptr]

irq_emu:
        pha
        bit TIMEUP
        stz irq_flag
        lda #1
        sta in_split
        lda irq_next
        sta irq_line
        stz split_open
        lda nmi_flags
        sta NMITIMEN
        pla
        jml [irq_ptr]

native_unused:
        rti

zero:   .byte 0

.segment "HEADER"
        ;       123456789012345678901
        .byte "GIMMICK SNES PORT    "
        .byte $31           ; HiROM, fast
        .byte $01           ; ROM and RAM
        .byte $0C           ; 4 MB
        .byte $03           ; 8 KB of RAM
        .byte $00           ; Japan
        .byte $33
        .byte $00
        .word $FFFF, $0000  ; checksum: tools/build.py fills it in

.segment "VECTORS"
        ; native
        .word 0, 0
        .word native_unused, native_unused, native_unused, native_unused, 0, native_unused
        ; emulation
        .word 0, 0
        .word native_unused, 0, native_unused, nmi_emu, reset, irq_emu
