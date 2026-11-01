; Power-on, the interrupt vectors and the cartridge header, in ROM bank 0.

.p816
.a8
.i8
.smart off

.include "hw.inc"

.import __WCODE_LOAD__, __WCODE_RUN__, __WCODE_SIZE__
.import nmi_ptr, irq_ptr, cur_pbr, nmi_flags, split_n, split_open, hdma_tab, set_have
.import load_split_sets, runtime_init, commit_palette
.import FirstBank, NesNmi, NesIrq, NesReset, TitleTune

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

        ; The picture: mode 0, BG1 only with sprites over it, as the NES's layers.
        stz BGMODE
        lda #$60 | 1        ; maps at $6000, side by side to start with
        sta BG1SC
        lda #2              ; tiles at $2000
        sta BG12NBA
        lda #$00            ; sprite tables at 0, 8x8 and 16x16
        sta OBSEL
        ; One window, over the leftmost 8 pixels, for when the game hides them.
        lda #$02
        sta W12SEL
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

        ; Unset tile-set pages can't match any page.
        ldx #0
        lda #$FF
:       sta set_have,x
        inx
        cpx #12
        bne :-

        jsr runtime_init

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

; The vertical scroll's HDMA and the background's tile set restart with each frame.
nmi_emu:
        pha
        phx
        phy
        bit RDNMI
        stz split_n
        stz split_open
        lda #2
        sta BG12NBA
        lda #$40
        sta HDMAEN
        jsr commit_palette
        jsr load_split_sets
        ply
        plx
        pla
        jml [nmi_ptr]

irq_emu:
        pha
        bit TIMEUP
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
