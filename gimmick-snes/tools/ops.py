"""The 6502 instruction set."""
# opcode: (mnemonic, mode, cycles). Page-cross and taken-branch cycles are added
# in the generated code.
_T = """
00 brk imp 7|01 ora inx 6|05 ora zp 3|06 asl zp 5|08 php imp 3|09 ora imm 2|0A asl acc 2|0D ora abs 4|0E asl abs 6
10 bpl rel 2|11 ora iny 5|15 ora zpx 4|16 asl zpx 6|18 clc imp 2|19 ora aby 4|1D ora abx 4|1E asl abx 7
20 jsr abs 6|21 and inx 6|24 bit zp 3|25 and zp 3|26 rol zp 5|28 plp imp 4|29 and imm 2|2A rol acc 2|2C bit abs 4|2D and abs 4|2E rol abs 6
30 bmi rel 2|31 and iny 5|35 and zpx 4|36 rol zpx 6|38 sec imp 2|39 and aby 4|3D and abx 4|3E rol abx 7
40 rti imp 6|41 eor inx 6|45 eor zp 3|46 lsr zp 5|48 pha imp 3|49 eor imm 2|4A lsr acc 2|4C jmp abs 3|4D eor abs 4|4E lsr abs 6
50 bvc rel 2|51 eor iny 5|55 eor zpx 4|56 lsr zpx 6|58 cli imp 2|59 eor aby 4|5D eor abx 4|5E lsr abx 7
60 rts imp 6|61 adc inx 6|65 adc zp 3|66 ror zp 5|68 pla imp 4|69 adc imm 2|6A ror acc 2|6C jmp ind 5|6D adc abs 4|6E ror abs 6
70 bvs rel 2|71 adc iny 5|75 adc zpx 4|76 ror zpx 6|78 sei imp 2|79 adc aby 4|7D adc abx 4|7E ror abx 7
81 sta inx 6|84 sty zp 3|85 sta zp 3|86 stx zp 3|88 dey imp 2|8A txa imp 2|8C sty abs 4|8D sta abs 4|8E stx abs 4
90 bcc rel 2|91 sta iny 6|94 sty zpx 4|95 sta zpx 4|96 stx zpy 4|98 tya imp 2|99 sta aby 5|9A txs imp 2|9D sta abx 5
A0 ldy imm 2|A1 lda inx 6|A2 ldx imm 2|A4 ldy zp 3|A5 lda zp 3|A6 ldx zp 3|A8 tay imp 2|A9 lda imm 2|AA tax imp 2|AC ldy abs 4|AD lda abs 4|AE ldx abs 4
B0 bcs rel 2|B1 lda iny 5|B4 ldy zpx 4|B5 lda zpx 4|B6 ldx zpy 4|B8 clv imp 2|B9 lda aby 4|BA tsx imp 2|BC ldy abx 4|BD lda abx 4|BE ldx aby 4
C0 cpy imm 2|C1 cmp inx 6|C4 cpy zp 3|C5 cmp zp 3|C6 dec zp 5|C8 iny imp 2|C9 cmp imm 2|CA dex imp 2|CC cpy abs 4|CD cmp abs 4|CE dec abs 6
D0 bne rel 2|D1 cmp iny 5|D5 cmp zpx 4|D6 dec zpx 6|D8 cld imp 2|D9 cmp aby 4|DD cmp abx 4|DE dec abx 7
E0 cpx imm 2|E1 sbc inx 6|E4 cpx zp 3|E5 sbc zp 3|E6 inc zp 5|E8 inx imp 2|E9 sbc imm 2|EA nop imp 2|EC cpx abs 4|ED sbc abs 4|EE inc abs 6
F0 beq rel 2|F1 sbc iny 5|F5 sbc zpx 4|F6 inc zpx 6|F8 sed imp 2|F9 sbc aby 4|FD sbc abx 4|FE inc abx 7
"""
OPS = {}
for chunk in _T.replace("\n", "|").split("|"):
    if chunk.strip():
        c, m, mode, cyc = chunk.split()
        OPS[int(c, 16)] = (m, mode, int(cyc))
SIZE = {"imp": 1, "acc": 1, "imm": 2, "zp": 2, "zpx": 2, "zpy": 2, "inx": 2, "iny": 2, "rel": 2,
        "abs": 3, "abx": 3, "aby": 3, "ind": 3}
