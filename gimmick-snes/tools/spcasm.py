#!/usr/bin/env python3
"""A small SPC700 assembler, for src/sound.spc: what the driver uses and little else.

    code = assemble(text, origin, symbols)
"""
import re

D = r"(?P<d>[\w$+*\- ]+)"
# (pattern, opcode, operands). Operands: b = byte, w = word, r = relative, dd = two bytes
# in the order the machine wants them (destination last).
FORMS = [
    (r"mov a,#(.+)", 0xE8, "b"), (r"mov x,#(.+)", 0xCD, "b"), (r"mov y,#(.+)", 0x8D, "b"),
    (r"mov sp,x", 0xBD, ""), (r"mov a,x", 0x7D, ""), (r"mov x,a", 0x5D, ""), (r"mov a,y", 0xDD, ""), (r"mov y,a", 0xFD, ""),
    (r"mov a,\[(.+)\]\+y", 0xF7, "b"), (r"mov \[(.+)\]\+y,a", 0xD7, "b"),
    (r"mov a,!(.+)\+x", 0xF5, "w"), (r"mov a,!(.+)\+y", 0xF6, "w"), (r"mov a,!(.+)", 0xE5, "w"),
    (r"mov !(.+)\+x,a", 0xD5, "w"), (r"mov !(.+)\+y,a", 0xD6, "w"), (r"mov !(.+),a", 0xC5, "w"),
    (r"mov a,(.+)\+x", 0xF4, "b"), (r"mov (.+)\+x,a", 0xD4, "b"),
    (r"mov a,(.+)", 0xE4, "b"), (r"mov x,(.+)", 0xF8, "b"), (r"mov y,(.+)", 0xEB, "b"),
    (r"mov (.+),a", 0xC4, "b"), (r"mov (.+),x", 0xD8, "b"), (r"mov (.+),y", 0xCB, "b"),
    (r"mov (.+),#(.+)", 0x8F, "imm_d"), (r"mov (.+),(.+)", 0xFA, "dd"),
    (r"clc", 0x60, ""), (r"setc", 0x80, ""), (r"nop", 0x00, ""), (r"ret", 0x6F, ""),
    (r"adc a,#(.+)", 0x88, "b"), (r"adc a,(.+)", 0x84, "b"), (r"sbc a,#(.+)", 0xA8, "b"), (r"sbc a,(.+)", 0xA4, "b"),
    (r"and a,#(.+)", 0x28, "b"), (r"and a,(.+)", 0x24, "b"), (r"or a,#(.+)", 0x08, "b"), (r"or a,(.+)", 0x04, "b"),
    (r"eor a,#(.+)", 0x48, "b"), (r"cmp a,#(.+)", 0x68, "b"), (r"cmp a,(.+)", 0x64, "b"),
    (r"cmp x,#(.+)", 0xC8, "b"), (r"cmp y,#(.+)", 0xAD, "b"),
    (r"asl a", 0x1C, ""), (r"lsr a", 0x5C, ""), (r"rol a", 0x3C, ""), (r"ror a", 0x7C, ""),
    (r"asl (.+)", 0x0B, "b"), (r"lsr (.+)", 0x4B, "b"), (r"rol (.+)", 0x2B, "b"), (r"ror (.+)", 0x6B, "b"),
    (r"inc a", 0xBC, ""), (r"dec a", 0x9C, ""), (r"inc x", 0x3D, ""), (r"dec x", 0x1D, ""), (r"inc y", 0xFC, ""), (r"dec y", 0xDC, ""),
    (r"inc (.+)", 0xAB, "b"), (r"dec (.+)", 0x8B, "b"),
    (r"mul ya", 0xCF, ""),
    (r"bra (.+)", 0x2F, "r"), (r"beq (.+)", 0xF0, "r"), (r"bne (.+)", 0xD0, "r"), (r"bcc (.+)", 0x90, "r"),
    (r"bcs (.+)", 0xB0, "r"), (r"bmi (.+)", 0x30, "r"), (r"bpl (.+)", 0x10, "r"),
    (r"call (.+)", 0x3F, "w"), (r"jmp (.+)", 0x5F, "w"),
    (r"movw ya,(.+)", 0xBA, "b"), (r"movw (.+),ya", 0xDA, "b"), (r"addw ya,(.+)", 0x7A, "b"), (r"subw ya,(.+)", 0x9A, "b"),
    (r"push a", 0x2D, ""), (r"pop a", 0xAE, ""), (r"push x", 0x4D, ""), (r"pop x", 0xCE, ""), (r"push y", 0x6D, ""), (r"pop y", 0xEE, ""),
]
FORMS = [(re.compile("^" + p + "$"), o, k) for p, o, k in FORMS]
SIZE = {"": 1, "b": 2, "w": 3, "r": 2, "dd": 3, "imm_d": 3}


def assemble(text, origin, symbols=None):
    sym = dict(symbols or {})
    lines = []
    for raw in text.splitlines():
        line = raw.split(";")[0].strip()
        if not line:
            continue
        m = re.match(r"^(\w+)\s*=\s*(.+)$", line)
        if m:
            lines.append(("equ", m.group(1), m.group(2)))
            continue
        m = re.match(r"^(\w+):\s*(.*)$", line)
        if m:
            lines.append(("label", m.group(1), None))
            line = m.group(2)
            if not line:
                continue
        lines.append(("ins", re.sub(r"\s*,\s*", ",", line.lower() if not line.startswith(".") else line), None))

    def val(e):
        e = e.replace("$", "0x")
        return eval(e, {"__builtins__": {}}, sym)

    def match(ins):
        # A word starting with "!" is absolute, so the operand keeps its case from the source.
        for rx, op, kind in FORMS:
            m = rx.match(ins)
            if m:
                return op, kind, m.groups()
        raise SyntaxError("no form for: " + ins)

    for pas in (0, 1):
        pc = origin
        out = bytearray()
        for kind, a, b in lines:
            if kind == "equ":
                try:
                    sym[a.lower()] = val(b.lower())
                except NameError:
                    if pas:
                        raise
                continue
            if kind == "label":
                sym[a.lower()] = pc
                continue
            if a.startswith(".byte"):
                vs = [x for x in a[5:].split(",")]
                if pas:
                    out += bytes(val(x.strip().lower()) & 0xFF for x in vs)
                pc += len(vs)
                continue
            if a.startswith(".word"):
                vs = [x for x in a[5:].split(",")]
                if pas:
                    for x in vs:
                        v = val(x.strip().lower())
                        out += bytes([v & 0xFF, v >> 8 & 0xFF])
                pc += 2 * len(vs)
                continue
            op, k, g = match(a)
            n = SIZE[k]
            if pas:
                out.append(op)
                if k == "b":
                    out.append(val(g[0]) & 0xFF)
                elif k == "w":
                    v = val(g[0])
                    out += bytes([v & 0xFF, v >> 8 & 0xFF])
                elif k == "r":
                    d = val(g[0]) - (pc + 2)
                    if not -128 <= d < 128:
                        raise SyntaxError("branch out of range: " + a)
                    out.append(d & 0xFF)
                elif k == "dd":      # mov dest,src: source byte first
                    out += bytes([val(g[1]) & 0xFF, val(g[0]) & 0xFF])
                elif k == "imm_d":   # mov dest,#imm: immediate first
                    out += bytes([val(g[1]) & 0xFF, val(g[0]) & 0xFF])
            pc += n
    return bytes(out), sym
