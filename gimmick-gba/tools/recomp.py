#!/usr/bin/env python3
"""Translate the game's 6502 code to C, from your own copy of the ROM.

    python3 tools/recomp.py          # writes out/gen/

The code that runs is found two ways: data/coverage.txt and data/entries.txt say
where Mesen saw code run and how often, and from there the translator follows
branches and jumps. (Those files are lists of addresses, kept in git so a build needs
no recording. tools/record.py and tools/freeze_coverage.py remake them.) Each basic
block becomes a C function that returns the next PC. Code that was never translated
runs in an interpreter, also written here, so it is slower but still right.

The output holds the original game's code, so it stays in out/, out of git.
"""
import os
import re
import subprocess
import sys

import parallax

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROM = os.path.join(REPO, "Gimmick! (Japan).nes")
DATA = os.path.join(REPO, "data")
GEN = os.path.join(REPO, "out", "gen")
BANK_SIZE = 0x2000
FIXED_BANK = 0x1F
WAIT_LOOP = (0xF29A, 0xF2A5)
# How much fast RAM the blocks may take. The exact-timing test build's code is bigger,
# and speed does not matter there, so tools/build_gba.py gives it less.
HOT_BYTES = int(os.environ.get("HOT_BYTES", 48200))
ARM_BYTES_PER_INSTR = 36     # rough size of a translated instruction as ARM code
# $F319 reads an inline jump table after its JSR, so nothing returns there.
NO_RETURN = {0xF319}

# Gimmick! 1.5's features, as options (src/gimmick-1.5/). Its code goes in a new bank,
# its far calls in the fixed bank's dead block, and each of its hooks, a JSR to a far
# call, becomes a switch at the start of the block there: the bits of `options` it
# answers to, and what runtime/core.c's opt_prep does first.
HACK_BANK = 0x20
OPT = {"recall": 1, "skip": 2, "tap": 4, "coyote": 8, "buffer": 16}
HOOKS = {(0x1E, 0x8199): (OPT["tap"] | OPT["coyote"] | OPT["buffer"], 0),
         (0x1E, 0x81C3): (OPT["recall"], 1),
         (0x1E, 0x81DA): (OPT["tap"], 2),
         (0x1D, 0x8469): (OPT["recall"] | OPT["skip"], 3),
         (0x1D, 0x8151): (OPT["skip"], 4)}
SRC_15 = os.path.join(REPO, "src", "gimmick-1.5")
SEG_RE = re.compile(r"^\s*;@\s*seg\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s*(.*)$")

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
BRANCH = {"bpl": "!(N & 0x80)", "bmi": "(N & 0x80)", "bvc": "!V", "bvs": "V",
          "bcc": "!C", "bcs": "C", "bne": "Z", "beq": "!Z"}
PAGE_READS = {"ora", "and", "eor", "adc", "sbc", "lda", "ldx", "ldy", "cmp"}


class Bank:
    def __init__(self, num, window, data):
        self.num, self.window, self.data = num, window, data
        self.seeds, self.instrs, self.leaders = set(), {}, set()

    def has(self, pc):
        return self.window <= pc < self.window + BANK_SIZE

    def byte(self, pc):
        return self.data[pc - self.window]


def decode(bank, banks_by_window):
    """Follow code from the seeds. Everything reached is an instruction; every
    jump target and return address starts a block."""
    todo = list(bank.seeds)
    while todo:
        pc = todo.pop()
        if pc in bank.instrs or not bank.has(pc):
            continue
        op = bank.byte(pc)
        info = OPS.get(op)
        size = SIZE[info[1]] if info else 1
        if not info or pc + size > bank.window + BANK_SIZE:
            bank.instrs[pc] = None
            continue
        arg = 0
        if size == 2:
            arg = bank.byte(pc + 1)
        elif size == 3:
            arg = bank.byte(pc + 1) | bank.byte(pc + 2) << 8
        bank.instrs[pc] = (info[0], info[1], info[2], arg, size)
        m = info[0]
        nxt = pc + size
        target = None
        if info[1] == "rel":
            target = (nxt + (arg - 256 if arg >= 128 else arg)) & 0xFFFF
            bank.leaders |= {target, nxt}
            todo += [target, nxt]
        elif m == "jmp" and info[1] == "abs":
            target = arg
        elif m == "jsr":
            target = arg
            if arg not in NO_RETURN:
                bank.leaders.add(nxt)
                todo.append(nxt)
        elif m not in ("jmp", "rts", "rti", "brk"):
            todo.append(nxt)
        if m == "jsr" and arg in NO_RETURN:
            # The words after the JSR are a jump table. Its end is not marked, so
            # stop at the first word that does not look like an address here.
            at = nxt
            while at + 1 < bank.window + BANK_SIZE:
                word = bank.byte(at) | bank.byte(at + 1) << 8
                if bank.has(word):
                    bank.leaders.add(word)
                    todo.append(word)
                elif word >= 0xE000 and banks_by_window[0xE000] is not bank:
                    banks_by_window[0xE000].seeds.add(word)
                else:
                    break
                at += 2
        if target is not None and info[1] != "rel":
            if bank.has(target):
                bank.leaders.add(target)
                todo.append(target)
            else:
                other = banks_by_window.get(target & 0xE000)
                if other is not None and other is not bank and target not in other.instrs:
                    other.seeds.add(target)


def add_entry_points(bank, entries):
    """Blocks also start where the recording saw code entered from elsewhere (jump
    tables, an RTS to a pushed address, interrupts), and at the vectors."""
    for pc in entries:
        if bank.has(pc) and pc in bank.instrs:
            bank.leaders.add(pc)
    for at in (0xFFFA, 0xFFFC, 0xFFFE):
        if bank.has(at):
            bank.leaders.add(bank.byte(at) | bank.byte(at + 1) << 8)


def rd(a, mode):
    """A C expression that reads the operand of the given address mode."""
    if mode == "imm":
        return "0x%02X" % a
    if mode == "zp":
        return "ram[0x%02X]" % a
    if mode == "zpx":
        return "ram[(u8)(0x%02X + X)]" % a
    if mode == "zpy":
        return "ram[(u8)(0x%02X + Y)]" % a
    if mode == "abs":
        return rd_abs(a)
    if mode in ("abx", "aby"):
        i = "X" if mode == "abx" else "Y"
        last = a + 255
        if last < 0x800:
            return "ram[0x%04X + %s]" % (a, i)
        if 0x6000 <= a and last < 0x8000:
            return "w6000[0x%04X + %s]" % (a - 0x6000, i)
        if a >= 0xE000 and last <= 0xFFFF:
            return "fixed[0x%04X + %s]" % (a - 0xE000, i)
        if a >= 0x8000 and (a >> 13) == (last >> 13):
            return "window[%d][0x%04X + %s]" % ((a - 0x8000) >> 13, a & 0x1FFF, i)
        return "rd((u16)(0x%04X + %s))" % (a, i)
    if mode == "inx":
        return "RD_ANY(IND(0x%02X + X))" % a
    if mode == "iny":
        return "RD_ANY((u16)(IND(0x%02X) + Y))" % a
    raise ValueError(mode)


def rd_abs(a):
    if a < 0x2000:
        return "ram[0x%04X]" % (a & 0x7FF)
    if 0x6000 <= a < 0x8000:
        return "w6000[0x%04X]" % (a - 0x6000)
    if a >= 0xE000:
        return "fixed[0x%04X]" % (a - 0xE000)
    if a >= 0x8000:
        return "window[%d][0x%04X]" % ((a - 0x8000) >> 13, a & 0x1FFF)
    return "rd(0x%04X)" % a


def wr(a, mode, val):
    """A C statement that writes val to the operand."""
    if mode == "zp":
        return "ram[0x%02X] = %s;" % (a, val)
    if mode == "zpx":
        return "ram[(u8)(0x%02X + X)] = %s;" % (a, val)
    if mode == "zpy":
        return "ram[(u8)(0x%02X + Y)] = %s;" % (a, val)
    if mode == "abs":
        if a < 0x2000:
            return "ram[0x%04X] = %s;" % (a & 0x7FF, val)
        if 0x6000 <= a < 0x8000:
            return "w6000w[0x%04X] = %s;" % (a - 0x6000, val)
        if a == 0x2007:
            return "ppu_data_write(%s);" % val
        return "wr(0x%04X, %s);" % (a, val)
    if mode in ("abx", "aby"):
        i = "X" if mode == "abx" else "Y"
        last = a + 255
        if last < 0x800:
            return "ram[0x%04X + %s] = %s;" % (a, i, val)
        if 0x6000 <= a and last < 0x8000:
            return "w6000w[0x%04X + %s] = %s;" % (a - 0x6000, i, val)
        return "wr((u16)(0x%04X + %s), %s);" % (a, i, val)
    if mode == "inx":
        return "WR_ANY(IND(0x%02X + X), %s);" % (a, val)
    if mode == "iny":
        return "WR_ANY((u16)(IND(0x%02X) + Y), %s);" % (a, val)
    raise ValueError(mode)


def touches_io(a, mode):
    """Could this access reach hardware? The cycle count has to be right first."""
    if mode in ("imm", "zp", "zpx", "zpy", "acc", "imp", "rel"):
        return False
    if mode == "abs":
        return 0x2000 <= a < 0x6000
    if mode in ("abx", "aby"):
        last = a + 255
        return not (last < 0x800 or (0x6000 <= a and last < 0x8000) or (a >= 0x8000 and a >> 13 == last >> 13))
    return True


def page_extra(a, mode):
    """Extra cycle when an indexed read crosses a page."""
    if mode == "abx":
        return "PAGE(0x%04X, X);" % a
    if mode == "aby":
        return "PAGE(0x%04X, Y);" % a
    if mode == "iny":
        return "PAGE(IND(0x%02X), Y);" % a
    return ""


def emit_instr(m, mode, arg, nxt):
    """C statements for an instruction that does not end a block."""
    if m in ("lda", "ldx", "ldy"):
        reg = m[2].upper()
        return "%s = %s; N = Z = %s;" % (reg, rd(arg, mode), reg)
    if m in ("sta", "stx", "sty"):
        return wr(arg, mode, m[2].upper())
    if m in ("ora", "and", "eor"):
        o = {"ora": "|", "and": "&", "eor": "^"}[m]
        return "A %s= %s; N = Z = A;" % (o, rd(arg, mode))
    if m == "adc":
        return "ADC(%s);" % rd(arg, mode)
    if m == "sbc":
        return "ADC((u8)~%s);" % rd(arg, mode)
    if m in ("cmp", "cpx", "cpy"):
        reg = {"cmp": "A", "cpx": "X", "cpy": "Y"}[m]
        return "CMP(%s, %s);" % (reg, rd(arg, mode))
    if m == "bit":
        return "{ u8 t = %s; N = t; V = t & 0x40; Z = t & A; }" % rd(arg, mode)
    if m in ("asl", "lsr", "rol", "ror"):
        f = m.upper()
        if mode == "acc":
            return "A = %s(A);" % f
        return "{ u8 t = %s; %s }" % (rd(arg, mode), wr(arg, mode, "%s(t)" % f))
    if m in ("inc", "dec"):
        d = "+ 1" if m == "inc" else "- 1"
        return "{ u8 t = %s %s; N = Z = t; %s }" % (rd(arg, mode), d, wr(arg, mode, "t"))
    simple = {
        "inx": "X++; N = Z = X;", "dex": "X--; N = Z = X;", "iny": "Y++; N = Z = Y;", "dey": "Y--; N = Z = Y;",
        "tax": "X = A; N = Z = X;", "tay": "Y = A; N = Z = Y;", "txa": "A = X; N = Z = A;", "tya": "A = Y; N = Z = A;",
        "tsx": "X = S; N = Z = X;", "txs": "S = X;",
        "clc": "C = 0;", "sec": "C = 1;", "cli": "I = 0;", "sei": "I = 1;", "clv": "V = 0;", "cld": "D = 0;", "sed": "D = 1;",
        "pha": "PUSH(A);", "pla": "A = POP(); N = Z = A;", "php": "PUSH(get_p() | 0x10);", "plp": "set_p(POP());", "nop": "",
    }
    return simple[m]


def block_pcs(bank, start):
    """The instructions of the block that starts at start."""
    pc = start
    while True:
        ins = bank.instrs.get(pc)
        yield pc, ins
        if ins is None or ins[0] in BRANCH or ins[0] in ("jmp", "jsr", "rts", "rti", "brk"):
            return
        pc += ins[4]
        if pc in bank.leaders:
            return


def pick_hot(banks, counts):
    """The blocks that run most, up to what fits in fast RAM. The wait loops do not
    count: on the GBA they are skipped."""
    blocks = []
    for b in banks.values():
        for start in b.leaders & set(b.instrs):
            pcs = [p for p, ins in block_pcs(b, start) if ins]
            heat = sum(counts.get((b.num, p), 0) for p in pcs)
            if heat and not (b.num == FIXED_BANK and WAIT_LOOP[0] <= start <= WAIT_LOOP[1]):
                blocks.append((heat / len(pcs), len(pcs), b.num, start, heat))
    blocks.sort(reverse=True)
    hot, used, covered = set(), 0, 0
    for _, n, num, start, heat in blocks:
        size = n * ARM_BYTES_PER_INSTR + 24
        if used + size > HOT_BYTES:
            break
        used += size
        covered += heat
        hot.add((num, start))
    total = sum(x[4] for x in blocks) or 1
    print("fast RAM: %d blocks, about %d bytes, %.0f%% of what ran" % (len(hot), used, 100 * covered / total))
    return hot


NZ_SETTERS = {"lda", "ldx", "ldy", "ora", "and", "eor", "adc", "sbc", "cmp", "cpx", "cpy", "asl", "lsr", "rol",
              "ror", "inc", "dec", "inx", "dex", "iny", "dey", "tax", "tay", "txa", "tya", "tsx", "pla", "bit", "plp"}


def dead_flags(bank, start):
    """Instructions in this block whose N and Z nothing can read: the next instruction
    to set them comes first. Flags are only stored for the block's end to see."""
    ins = [(pc, i) for pc, i in block_pcs(bank, start) if i]
    dead, live = set(), True
    for pc, i in reversed(ins):
        m = i[0]
        if m == "php" or m in BRANCH:
            live = True
        elif m in NZ_SETTERS:
            if not live:
                dead.add(pc)
            live = False
    return dead


def strip_flags(code):
    """The same statement without storing N and Z."""
    code = re.sub(r" ?N = Z = \w+;", "", code)
    for name in ("ADC", "CMP", "ASL", "LSR", "ROL", "ROR"):
        code = code.replace(name + "(", name + "_NF(")
    return code


def has_mapper_write(bank, start):
    """Does this block write the mapper? Then its bank may no longer be mapped when
    the block ends, and a jump inside the bank has to look again."""
    for _, ins in block_pcs(bank, start):
        if ins and ins[0] in ("sta", "stx", "sty") and ins[1] in ("abs", "abx", "aby") and ins[3] >= 0x8000:
            return True
    return False


COUNTS = {}  # how often each instruction ran in the recordings, by (bank, pc)


def expect(cond, bank, taken, not_taken):
    """A branch's condition, with which way it mostly went in the recordings, so the
    compiler lays out and keeps in registers what the common way needs."""
    num = FIXED_BANK if taken >= 0xE000 else bank.num
    t = COUNTS.get((num, taken), 0)
    f = COUNTS.get((FIXED_BANK if not_taken >= 0xE000 else bank.num, not_taken), 0)
    if t > 2 * f:
        return "__builtin_expect(!!(%s), 1)" % cond
    if f > 2 * t:
        return "__builtin_expect(!!(%s), 0)" % cond
    return cond


FIXED_CHAIN = set()  # the fixed bank's blocks any bank's ROM blocks may go on to


def emit_block(bank, start, out, hot, chain=()):
    """One basic block, as a label in a function that holds many: in fast RAM, every
    block there (hot is the set of them); in ROM, a bank's own (chain is the set of
    them). Blocks in the same function jump straight to each other. Anything else
    returns the next PC for the dispatcher, or, from another bank to the fixed bank's,
    also names its block for the dispatcher to call straight away. With neither, the
    block is a function of its own."""
    is_hot = hot is not None
    moved = has_mapper_write(bank, start)

    def jump(t, fall=False):
        target = None
        if is_hot:
            if bank.has(t) and not moved and (bank.num, t) in hot:
                target = bank.num
            elif t >= 0xE000 and (FIXED_BANK, t) in hot:
                target = FIXED_BANK
            if target is None:
                return "pc = 0x%04X; goto dyn;" % t
        else:
            if t in chain and not moved:
                target = bank.num
            elif bank.num != FIXED_BANK and t >= 0xE000 and t in FIXED_CHAIN:
                return "chain_next = b%02X_%04X; return 0x%04X;" % (FIXED_BANK, t, t)
            else:
                return "return 0x%04X;" % t
        if t > cur or fall:
            # A loop has to jump backwards or return, so going forwards can wait. Falling
            # through into the next block goes forwards too (cur is already that block).
            return "FORWARD(L%02X_%04X, 0x%04X);" % (target, t, t)
        return "if (__builtin_expect(cyc < block_limit, 1)) goto L%02X_%04X; return 0x%04X;" % (target, t, t)

    def dynamic(expr):
        return ("pc = %s; goto dyn;" % expr) if is_hot else ("return %s;" % expr)

    dead = dead_flags(bank, start)
    cur, cyc = start, 0

    def code(m, mode, arg, nxt):
        c = emit_instr(m, mode, arg, nxt)
        return strip_flags(c) if cur in dead and m not in ("bit", "plp") else c

    while True:
        ins = bank.instrs.get(cur)
        if ins is None:
            out.append("  CYC(%d); return trap(0x%04X);" % (cyc, cur))
            return
        m, mode, c, arg, size = ins
        nxt = cur + size
        mapper = mode == "abs" and arg >= 0x8000 and m in ("sta", "stx", "sty")  # IRQ timing
        if (touches_io(arg, mode) or mapper) and m not in ("jmp", "jsr"):
            out.append("  CYC(%d);" % (cyc + c - 1))
            cyc = 1
            out.append("  " + code(m, mode, arg, nxt))
            if m in PAGE_READS:
                extra = page_extra(arg, mode)
                if extra:
                    out.append("  " + extra)
        elif m in BRANCH:
            off = arg - 256 if arg >= 128 else arg
            t = (nxt + off) & 0xFFFF
            extra = 2 if (t ^ nxt) & 0xFF00 else 1
            out.append("  CYC(%d);" % (cyc + c))
            out.append("  if (%s) { CYC(%d); %s }" % (expect(BRANCH[m], bank, t, nxt), extra, jump(t)))
            out.append("  " + jump(nxt))
            return
        elif m == "jmp":
            out.append("  CYC(%d);" % (cyc + c))
            if mode == "abs":
                out.append("  " + jump(arg))
            else:
                hi = (arg & 0xFF00) | ((arg + 1) & 0xFF)
                out.append("  " + dynamic("%s | %s << 8" % (rd_abs(arg), rd_abs(hi))))
            return
        elif m == "jsr":
            ret = (cur + 2) & 0xFFFF
            out.append("  CYC(%d);" % (cyc + c))
            out.append("  PUSH(0x%02X); PUSH(0x%02X);" % (ret >> 8, ret & 0xFF))
            out.append("  " + jump(arg))
            return
        elif m == "rts":
            out.append("  CYC(%d);" % (cyc + c))
            out.append("  { u32 l = POP(); u32 h = POP(); %s }" % dynamic("((h << 8 | l) + 1) & 0xFFFF"))
            return
        elif m == "rti":
            out.append("  CYC(%d);" % (cyc + c))
            out.append("  set_p(POP()); { u32 l = POP(); u32 h = POP(); return h << 8 | l; }")
            return
        elif m == "brk":
            out.append("  CYC(%d); return trap(0x%04X);" % (cyc + c, cur))
            return
        else:
            cyc += c
            out.append("  " + code(m, mode, arg, nxt))
            if m in ("cli", "plp"):
                out.append("  next_event = block_limit = 0;")  # an IRQ may be waiting for this
            if m in PAGE_READS:
                extra = page_extra(arg, mode)
                if extra:
                    out.append("  " + extra)
        cur = nxt
        if cur in bank.leaders:
            out.append("  CYC(%d); %s" % (cyc, jump(cur, fall=True)))
            return


def rom_blocks(bank, hot):
    return [pc for pc in sorted(bank.leaders & set(bank.instrs)) if (bank.num, pc) not in hot]


def chain_set(bank, hot, after_hook):
    """The blocks a ROM block may go on to straight away: its bank's own in ROM, but
    not a hook's, nor one that 1.5's code can stand in for, nor the wait loops, which
    the dispatcher skips."""
    swapped = {p for (num, start), patched in after_hook.items() if num == bank.num
               for p in patched.leaders if start + 3 <= p < patched.end}
    return {pc for pc in rom_blocks(bank, hot) if (bank.num, pc) not in HOOKS and pc not in swapped
            and not (bank.num == FIXED_BANK and WAIT_LOOP[0] <= pc <= WAIT_LOOP[1])}


def emit_bank(bank, out, hot, after_hook):
    names = {}
    pcs = rom_blocks(bank, hot)
    chain = chain_set(bank, hot, after_hook)
    index = {pc: i + 1 for i, pc in enumerate(pcs)}
    run = "run_%02X" % bank.num
    out.append('#include "cpu.h"\n')
    # The fixed bank's that others go on to are not private to its file.
    shared = FIXED_CHAIN if bank.num == FIXED_BANK else set()
    if bank.num != FIXED_BANK:
        for pc in sorted(FIXED_CHAIN):
            out.append("u32 b%02X_%04X(void);" % (FIXED_BANK, pc))
    out.append("static u32 %s(u32 e);" % run)
    # Where the dispatcher comes in: the bank's one function, at that block.
    for pc in pcs:
        names[pc] = "b%02X_%04X" % (bank.num, pc)
        out.append("%su32 %s(void) { return %s(%d); }" % ("" if pc in shared else "static ", names[pc], run, index[pc]))
    out.append("")
    # 1.5's code after each hook's far call. Where the game has an instruction at the
    # same place, the hook's options choose between them: the game can be there too,
    # stepping through the interpreter or back from an interrupt.
    for (num, start), patched in sorted(after_hook.items()):
        if num != bank.num:
            continue
        mask = HOOKS[(num, start)][0]
        for pc in sorted(p for p in patched.leaders if start + 3 <= p < patched.end):
            name = "b%02X_%04X_15" % (num, pc)
            out.append("static u32 %s(void) {" % name)
            emit_block(patched, pc, out, None)
            out.append("}\n")
            if pc in bank.instrs:
                if pc not in names:
                    names[pc] = "b%02X_%04X" % (num, pc)
                    out.append("static u32 %s(void) {" % names[pc])
                    emit_block(bank, pc, out, None)
                    out.append("}\n")
                out.append("static u32 %s_sw(void) { return (options & %d) ? %s() : %s(); }\n" % (name, mask, name, names[pc]))
                name += "_sw"
            names[pc] = name
    out.append("const block_t tbl_%02X[0x2000] = {" % bank.num)
    for pc in sorted(names):
        out.append("  [0x%04X] = %s," % (pc - bank.window, names[pc]))
    out.append("};\n")
    out.append("static u32 %s(u32 e) {" % run)
    out.append("  static void *const labels[] = {0,")
    for pc in pcs:
        out.append("    &&L%02X_%04X," % (bank.num, pc))
    out.append("  };")
    out.append("  goto *labels[e];")
    for pc in pcs:
        out.append("L%02X_%04X:" % (bank.num, pc))
        hook = HOOKS.get((bank.num, pc))
        if hook:
            # 1.5's JSR to its far call, when an option it answers to is on.
            target = after_hook[(bank.num, pc)].far
            ret = pc + 2
            out.append("  if (options & %d) { opt_prep(%d); CYC(6); PUSH(0x%02X); PUSH(0x%02X); return 0x%04X; }"
                       % (hook[0], hook[1], ret >> 8, ret & 0xFF, target))
        emit_block(bank, pc, out, None, chain)
    out.append("}")


def emit_hot(banks, hot, out):
    """Every block in fast RAM, as one function."""
    order = sorted(hot)
    index = {key: i + 1 for i, key in enumerate(order)}
    out.append('#pragma GCC optimize ("no-reorder-blocks")\n#include "cpu.h"\n#include "platform.h"\n')
    for num in sorted({k[0] for k in hot}):
        out.append("static const u16 hot_map_%02X[0x2000] = {" % num)
        for (n, pc) in order:
            if n == num:
                out.append("  [0x%04X] = %d," % (pc - banks[n].window, index[n, pc]))
        out.append("};")
    out.append("const u16 *const hot_maps[64] = {")
    for num in sorted({k[0] for k in hot}):
        out.append("  [0x%02X] = hot_map_%02X," % (num, num))
    out.append("};\n")
    out.append(HOT_LOCALS)
    out.append("HOT_THUMB u32 hot_run(u32 pc) {")
    out.append("  static void *const labels[] = {0,")
    for (n, pc) in order:
        out.append("    &&L%02X_%04X," % (n, pc))
    out.append("  };")
    out.append("  u32 e;")
    out.append(LOAD_REGS)
    out.append("  goto *labels[pc];")
    out.append("dyn:")
    out.append("  if (__builtin_expect(cyc >= block_limit || pc < 0x8000, 0)) goto leave;")
    out.append("  e = hot_lookup(pc);")
    out.append("  if (!e) goto leave;")
    out.append("  goto *labels[e];")
    body = []
    for (n, pc) in order:
        body.append("L%02X_%04X:" % (n, pc))
        emit_block(banks[n], pc, body, hot)
    leave(body, out)
    out.append("}")


def leave(body, out):
    """A function of blocks leaves through one place, which puts the registers back
    where the rest of the game looks for them."""
    for line in body:
        line = re.sub(r"return trap\(([^;]*)\);", r"{ STORE_REGS; return trap(\1); }", line)
        out.append(re.sub(r"return ([^;]*);", r"{ pc = \1; goto leave; }", line))
    out.append("leave:")
    out.append("  STORE_REGS;")
    out.append("  return pc;")


# In a function of blocks the 6502's registers and flags are locals, not the struct's: the compiler
# keeps them in machine registers where it can, and drops flags nothing reads.
LOCAL_REGS = ("a", "x", "y", "s", "c", "v", "n", "z")
LOAD_REGS = "  u8 " + ", ".join("r%s = cs->%s" % (r, r) for r in LOCAL_REGS) + ";"
HOT_LOCALS = "\n".join(
    ["#undef %s\n#define %s r%s" % (r.upper(), r.upper(), r) for r in LOCAL_REGS] +
    ["#define STORE_REGS (" + ", ".join("cs->%s = r%s" % (r, r) for r in LOCAL_REGS) + ")",
     "#undef FORWARD",
     "#ifdef EXACT_TIMING",
     "#define FORWARD(label, pc_) do { if (cyc < block_limit) goto label; pc = pc_; goto leave; } while (0)",
     "#else",
     "#define FORWARD(label, pc_) goto label",
     "#endif",
     # cpu.h's inline helpers name the struct's, so these take their place here.
     "#define ASL(v_) ({ u8 v = (v_); C = v >> 7; v <<= 1; N = Z = v; v; })",
     "#define LSR(v_) ({ u8 v = (v_); C = v & 1; v >>= 1; N = Z = v; v; })",
     "#define ROL(v_) ({ u8 v = (v_); u8 c_ = C; C = v >> 7; v = v << 1 | c_; N = Z = v; v; })",
     "#define ROR(v_) ({ u8 v = (v_); u8 c_ = C; C = v & 1; v = v >> 1 | c_ << 7; N = Z = v; v; })",
     "#define get_p() ((u8)((N & 0x80) | (V ? 0x40 : 0) | 0x20 | (D ? 8 : 0) | (I ? 4 : 0) | (Z ? 0 : 2) | (C ? 1 : 0)))",
     "#define set_p(p_) do { u8 p = (p_); N = p; V = p & 0x40; D = (p >> 3) & 1; I = (p >> 2) & 1; Z = (p & 2) ? 0 : 1; C = p & 1; } while (0)",
     ""])


def emit_interpreter(out, hooks):
    """One 6502 instruction at a time, for code the recordings never reached. It reads
    the code itself through op(), which shows 1.5's hooks where their options are on."""
    ea = {"zp": "op(pc + 1)", "zpx": "(u8)(op(pc + 1) + X)", "zpy": "(u8)(op(pc + 1) + Y)",
          "abs": "W", "abx": "(u16)(W + X)", "aby": "(u16)(W + Y)",
          "inx": "IND(op(pc + 1) + X)", "iny": "(u16)(IND(op(pc + 1)) + Y)"}
    out.append('#include "cpu.h"\n')
    out.append("static const struct { u8 bank, mask, prep, len; u16 start; u8 code[16]; } hooks[] = {")
    for (num, start), code in sorted(hooks.items()):
        mask, prep = HOOKS[(num, start)]
        out.append("  {0x%02X, %d, %d, %d, 0x%04X, {%s}}," % (num, mask, prep, len(code), start, ", ".join("0x%02X" % b for b in code)))
    out.append("};")
    out.append("static u8 op(u32 a) {")
    out.append("  for (u32 i = 0; i < sizeof hooks / sizeof hooks[0]; i++)")
    out.append("    if ((options & hooks[i].mask) && a - hooks[i].start < hooks[i].len && prg_map[(a - 0x8000) >> 13] == hooks[i].bank)")
    out.append("      return hooks[i].code[a - hooks[i].start];")
    out.append("  return rd(a);")
    out.append("}")
    out.append("#define W (op(pc + 1) | op(pc + 2) << 8)")
    out.append("u32 interp_step(u32 pc) {")
    out.append("  for (u32 i = 0; i < sizeof hooks / sizeof hooks[0]; i++)")
    out.append("    if ((options & hooks[i].mask) && pc == hooks[i].start && prg_map[0] == hooks[i].bank) opt_prep(hooks[i].prep);")
    out.append("  u32 next, ea = 0;\n  switch (op(pc)) {")
    for code, (m, mode, c) in sorted(OPS.items()):
        size = SIZE[mode]
        line = "  case 0x%02X: next = pc + %d; CYC(%d); " % (code, size, c)
        if mode in ea:
            line += "ea = %s; " % ea[mode]
            if m in PAGE_READS:
                base = {"abx": ("W", "X"), "aby": ("W", "Y"), "iny": ("IND(op(pc + 1))", "Y")}.get(mode)
                if base:
                    line += "PAGE(%s, %s); " % base
        val = "op(pc + 1)" if mode == "imm" else "rd(ea)"
        if m in ("lda", "ldx", "ldy"):
            line += "%s = %s; N = Z = %s;" % (m[2].upper(), val, m[2].upper())
        elif m in ("sta", "stx", "sty"):
            line += "wr(ea, %s);" % m[2].upper()
        elif m in ("ora", "and", "eor"):
            line += "A %s= %s; N = Z = A;" % ({"ora": "|", "and": "&", "eor": "^"}[m], val)
        elif m == "adc":
            line += "ADC(%s);" % val
        elif m == "sbc":
            line += "ADC((u8)~%s);" % val
        elif m in ("cmp", "cpx", "cpy"):
            line += "CMP(%s, %s);" % ({"cmp": "A", "cpx": "X", "cpy": "Y"}[m], val)
        elif m == "bit":
            line += "{ u8 t = rd(ea); N = t; V = t & 0x40; Z = t & A; }"
        elif m in ("asl", "lsr", "rol", "ror"):
            line += ("A = %s(A);" % m.upper()) if mode == "acc" else ("{ u8 t = rd(ea); wr(ea, %s(t)); }" % m.upper())
        elif m in ("inc", "dec"):
            line += "{ u8 t = rd(ea) %s 1; N = Z = t; wr(ea, t); }" % ("+" if m == "inc" else "-")
        elif m in BRANCH:
            line += ("{ int o = (signed char)op(pc + 1); if (%s) { u32 t = (next + o) & 0xFFFF; "
                     "CYC(((t ^ next) & 0xFF00) ? 2 : 1); next = t; } }" % BRANCH[m])
        elif m == "jmp":
            line += ("next = W;" if mode == "abs" else
                     "{ u32 a = W; next = rd(a) | rd((a & 0xFF00) | ((a + 1) & 0xFF)) << 8; }")
        elif m == "jsr":
            line += "{ u32 r = pc + 2; next = W; PUSH(r >> 8); PUSH(r & 0xFF); }"
        elif m == "rts":
            line += "{ u32 l = POP(); u32 h = POP(); next = ((h << 8 | l) + 1) & 0xFFFF; }"
        elif m == "rti":
            line += "set_p(POP()); { u32 l = POP(); u32 h = POP(); next = h << 8 | l; }"
        elif m == "brk":
            line += "return trap(pc);"
        elif m in ("cli", "plp"):
            line += emit_instr(m, mode, 0, 0) + " next_event = block_limit = 0;"
        else:
            line += emit_instr(m, mode, 0, 0)
        out.append(line + " break;")
    out.append("  default: return trap(pc);")
    out.append("  }\n  return next & 0xFFFF;\n}")


def assemble_15():
    """1.5's source is split by `;@ seg <bank> <start> <end>` lines into pieces for each
    place in the ROM. They are assembled in one run of asm6, so that labels resolve
    across them, with a table of their lengths after them that says where each ends."""
    work = os.path.join(GEN, "gimmick-1.5")
    os.makedirs(work, exist_ok=True)
    prologue, segs, cur = [], [], None
    for line in open(os.path.join(SRC_15, "main.asm")):
        m = SEG_RE.match(line)
        if m:
            cur = (int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16), m.group(4).strip(), [])
            segs.append(cur)
        else:
            (cur[4] if cur else prologue).append(line)
    gen = os.path.join(work, "build.asm")
    with open(gen, "w") as f:
        f.writelines(prologue)
        for i, (bank, start, end, name, lines) in enumerate(segs):
            f.write("\n.base $%04X\n" % start)
            f.writelines(lines)
            f.write("\n__seg%d_end:\n.if __seg%d_end > $%04X\n.error \"%s is too long\"\n.endif\n" % (i, i, end, name))
        for i, (bank, start, end, name, lines) in enumerate(segs):
            f.write(".dw __seg%d_end - $%04X\n" % (i, start))
    binary = os.path.join(work, "build.bin")
    asm6 = os.path.join(REPO, "tools", "asm6")
    if not os.path.exists(asm6):
        sys.exit("asm6 is missing: put it at tools/asm6 (https://www.romhacking.net/utilities/674/)")
    # asm6 reads arguments that start with "/" as options, so the paths are relative.
    r = subprocess.run([asm6, "-q", os.path.relpath(gen, SRC_15), os.path.relpath(binary, SRC_15)],
                       cwd=SRC_15, capture_output=True, text=True)
    if r.returncode:
        sys.exit("asm6 failed: " + r.stdout + r.stderr)
    blob = open(binary, "rb").read()
    table = len(blob) - 2 * len(segs)
    out, pos = [], 0
    for i, (bank, start, end, name, lines) in enumerate(segs):
        n = blob[table + 2 * i] | blob[table + 2 * i + 1] << 8
        out.append((bank, start, blob[pos:pos + n]))
        pos += n
    return out


def apply_15(prg):
    """The PRG with bank $20 and the far calls in, the hooks' code, and where the
    decoder starts in the fixed bank and in bank $20."""
    out = bytearray(prg) + bytes(BANK_SIZE)
    hooks, fixed_seeds, hack_seeds = {}, set(), set()
    for bank, start, code in assemble_15():
        num = FIXED_BANK if bank == 0x3F else bank
        if (num, start) in HOOKS:
            if code[0] != 0x20:
                sys.exit("1.5's hook at %02X:%04X is not a JSR" % (num, start))
            hooks[(num, start)] = code
            fixed_seeds.add(code[1] | code[2] << 8)
            continue
        if num not in (FIXED_BANK, HACK_BANK):
            sys.exit("a part of Gimmick! 1.5 at %02X:%04X that this build does not know" % (num, start))
        at = num * BANK_SIZE + (start & 0x1FFF)
        out[at:at + len(code)] = code
        if num == HACK_BANK:
            # HackEntry, then its table of routines (each less 1, for an RTS).
            hack_seeds.add(start)
            at = code.find(bytes([0x60])) + 1
            for i in range(5):
                hack_seeds.add((code[at + i * 2] | code[at + i * 2 + 1] << 8) + 1)
    if set(hooks) != set(HOOKS):
        sys.exit("1.5's hooks are not the ones this build knows")
    return bytes(out), hooks, fixed_seeds, hack_seeds


def write_nes_15(nes, prg, hooks):
    """The NES game with all of 1.5's features on, laid out as 1.5's own ROM is (the fixed
    bank last, at $3F), for Mesen to record what the options should do."""
    out = bytearray(0x80000)
    out[:len(prg)] = prg
    out[0x7E000:] = prg[FIXED_BANK * BANK_SIZE:(FIXED_BANK + 1) * BANK_SIZE]
    for (num, start), code in hooks.items():
        at = num * BANK_SIZE + (start & 0x1FFF)
        out[at:at + len(code)] = code
    header = bytearray(nes[:16])
    header[4] = 0x80000 // 0x4000
    with open(os.path.join(GEN, "gimmick-1.5.nes"), "wb") as f:
        f.write(bytes(header) + bytes(out) + nes[16 + 0x40000:16 + 0x60000])


def main():
    rom = open(ROM, "rb").read()[16:]
    prg, hooks_15, fixed_seeds, hack_seeds = apply_15(rom[:0x40000])
    os.makedirs(GEN, exist_ok=True)
    with open(os.path.join(GEN, "prg.bin"), "wb") as f:
        f.write(prg)
    write_nes_15(open(ROM, "rb").read(), prg, hooks_15)
    chr4, par = parallax.build(rom[0x40000:0x60000])
    open(os.path.join(GEN, "chr4.bin"), "wb").write(chr4)
    open(os.path.join(GEN, "parallax.bin"), "wb").write(par)
    seen = {}
    counts = {}
    for line in open(os.path.join(DATA, "coverage.txt")):
        num, pc, n = line.split()
        num, pc = int(num, 16), int(pc, 16)
        seen.setdefault(num, set()).add(pc)
        counts[num, pc] = int(n)
    COUNTS.update(counts)
    entries = {int(line, 16) for line in open(os.path.join(DATA, "entries.txt"))}
    banks = {}
    for num, pcs in sorted(seen.items()):
        windows = {pc & 0xE000 for pc in pcs}
        if len(windows) != 1:
            sys.exit("bank %02X runs in more than one window: %s" % (num, sorted(windows)))
        b = Bank(num, windows.pop(), prg[num * BANK_SIZE:(num + 1) * BANK_SIZE])
        b.seeds = set(pcs)
        banks[num] = b
    by_window = {}
    fixed = banks[FIXED_BANK]
    by_window[0xE000] = fixed
    fixed.seeds |= fixed_seeds
    hack = Bank(HACK_BANK, 0xA000, prg[HACK_BANK * BANK_SIZE:(HACK_BANK + 1) * BANK_SIZE])
    hack.seeds = hack_seeds
    banks[HACK_BANK] = hack
    # Vectors
    for at in (0xFFFA, 0xFFFC, 0xFFFE):
        fixed.seeds.add(fixed.byte(at) | fixed.byte(at + 1) << 8)
    for b in banks.values():
        decode(b, by_window)
    decode(fixed, by_window)
    for b in banks.values():
        decode(b, by_window)
        add_entry_points(b, entries)
    # 1.5's far calls and its routines are entered from outside their banks, by the
    # hooks and by FarCall's JSR, so no jump the decoder follows marks them: without a
    # block of their own, each of those calls ran in the interpreter.
    fixed.leaders |= fixed_seeds & set(fixed.instrs)
    hack.leaders |= hack_seeds & set(hack.instrs)
    # Each hook starts a block of its own, which stays out of fast RAM, and where its far
    # call returns to, in the middle of the original's instructions, 1.5's own code goes
    # on: those blocks are decoded from a copy of the bank with the hook in.
    after_hook = {}
    for (num, start), code in hooks_15.items():
        b = banks[num]
        b.leaders.add(start)
        patched = Bank(num, b.window, bytearray(b.data))
        patched.data[start - b.window:start - b.window + len(code)] = code
        patched.seeds = {start + 3}
        patched.leaders = {start + 3, start + len(code)}
        patched.far = code[1] | code[2] << 8
        patched.end = start + len(code)
        decode(patched, {})
        after_hook[(num, start)] = patched
    hot = pick_hot(banks, counts)
    hot -= set(hooks_15)
    total = 0
    FIXED_CHAIN.update(chain_set(banks[FIXED_BANK], hot, after_hook))
    for b in banks.values():
        out = []
        emit_bank(b, out, hot, after_hook)
        with open(os.path.join(GEN, "bank_%02X.c" % b.num), "w") as f:
            f.write("\n".join(out) + "\n")
        total += len(b.instrs)
        print("bank %02X at $%04X: %5d instructions, %5d blocks" % (b.num, b.window, len(b.instrs), len(b.leaders)))
    out = []
    emit_hot(banks, hot, out)
    with open(os.path.join(GEN, "hot.c"), "w") as f:
        f.write("\n".join(out) + "\n")
    out = []
    emit_interpreter(out, hooks_15)
    with open(os.path.join(GEN, "interp.c"), "w") as f:
        f.write("\n".join(out) + "\n")
    with open(os.path.join(GEN, "tables.c"), "w") as f:
        f.write('#include "cpu.h"\n')
        for n in banks:
            f.write("extern const block_t tbl_%02X[0x2000];\n" % n)
        f.write("const block_t *const code_banks[64] = {\n")
        for n in banks:
            f.write("  [0x%02X] = tbl_%02X,\n" % (n, n))
        f.write("};\n")
    print("total %d instructions" % total)


if __name__ == "__main__":
    main()
