#!/usr/bin/env python3
"""Disassemble part of the NES ROM: python3 tools/dis.py <bank hex> <pc hex> [count]"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ops import OPS, SIZE

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
prg = open(os.path.join(REPO, "Gimmick! (Japan).nes"), "rb").read()[16:0x40010]


def line(bank, pc):
    off = bank * 0x2000 + (pc & 0x1FFF)
    op = prg[off]
    if op not in OPS:
        return ".byte $%02X" % op, 1
    m, mode, _ = OPS[op]
    n = SIZE[mode]
    arg = prg[off + 1] if n == 2 else prg[off + 1] | prg[off + 2] << 8 if n == 3 else 0
    fmt = {"imp": "", "acc": "a", "imm": "#$%02X", "zp": "$%02X", "zpx": "$%02X,x", "zpy": "$%02X,y",
           "inx": "($%02X,x)", "iny": "($%02X),y", "abs": "$%04X", "abx": "$%04X,x", "aby": "$%04X,y",
           "ind": "($%04X)"}.get(mode)
    if mode == "rel":
        return "%s $%04X" % (m, (pc + 2 + (arg - 256 if arg >= 128 else arg)) & 0xFFFF), n
    return (m + " " + (fmt % arg if "%" in fmt else fmt)).strip(), n


if __name__ == "__main__":
    bank, pc = int(sys.argv[1], 16), int(sys.argv[2], 16)
    for _ in range(int(sys.argv[3]) if len(sys.argv) > 3 else 40):
        s, n = line(bank, pc)
        print("%04X  %s" % (pc, s))
        pc += n
