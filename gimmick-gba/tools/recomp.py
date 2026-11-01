#!/usr/bin/env python3
"""Translate the game's 6502 code to C, from your own copy of the ROM.

    python3 tools/recomp.py          # writes out/gen/

The code that runs is found two ways: out/trace/coverage.txt says what Mesen saw
execute (this also finds targets of jump tables), and from there the translator
follows branches and jumps. Each basic block becomes a C function that returns
the next PC. Code that was never translated runs in an interpreter, also written
here, so it is slower but still right.

The output holds the original game's code, so it stays in out/, out of git.
"""
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROM = os.path.join(REPO, "Gimmick! (Japan).nes")
TRACES = sorted(glob.glob(os.path.join(REPO, "out", "trace*")))
GEN = os.path.join(REPO, "out", "gen")
BANK_SIZE = 0x2000
FIXED_BANK = 0x1F
WAIT_LOOP = (0xF29A, 0xF2A5)
HOT_BYTES = 30000            # how much fast RAM the blocks may take
ARM_BYTES_PER_INSTR = 36     # rough size of a translated instruction as ARM code
# $F319 reads an inline jump table after its JSR, so nothing returns there.
NO_RETURN = {0xF319}

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
        return "rd(IND(0x%02X + X))" % a
    if mode == "iny":
        return "rd((u16)(IND(0x%02X) + Y))" % a
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
        return "wr(IND(0x%02X + X), %s);" % (a, val)
    if mode == "iny":
        return "wr((u16)(IND(0x%02X) + Y), %s);" % (a, val)
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
        if ins and ins[0] in ("sta", "stx", "sty") and (ins[1] != "abs" or ins[3] >= 0x8000):
            if ins[1] not in ("zp", "zpx", "zpy"):
                return True
    return False


def emit_block(bank, start, out, hot):
    """One basic block. In fast RAM, blocks are labels in one function and jump
    straight to each other; in ROM, each is a function that returns the next PC."""
    is_hot = hot is not None
    moved = is_hot and has_mapper_write(bank, start)

    def jump(t):
        if not is_hot:
            return "return 0x%04X;" % t
        target = None
        if bank.has(t) and not moved and (bank.num, t) in hot:
            target = bank.num
        elif t >= 0xE000 and (FIXED_BANK, t) in hot:
            target = FIXED_BANK
        if target is None:
            return "pc = 0x%04X; goto dyn;" % t
        if t > cur:
            # A loop has to jump backwards or return, so going forwards can wait.
            return "FORWARD(L%02X_%04X, 0x%04X);" % (target, t, t)
        return "if (cyc < block_limit) goto L%02X_%04X; return 0x%04X;" % (target, t, t)

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
        if touches_io(arg, mode) and m not in ("jmp", "jsr"):
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
            out.append("  if (%s) { CYC(%d); %s }" % (BRANCH[m], extra, jump(t)))
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
            out.append("  CYC(%d); %s" % (cyc, jump(cur)))
            return


def emit_bank(bank, out, hot):
    names = {}
    pcs = [pc for pc in sorted(bank.leaders & set(bank.instrs)) if (bank.num, pc) not in hot]
    out.append('#include "cpu.h"\n')
    for pc in pcs:
        names[pc] = "b%02X_%04X" % (bank.num, pc)
        out.append("static u32 %s(void);" % names[pc])
    out.append("")
    for pc in pcs:
        out.append("static u32 %s(void) {" % names[pc])
        emit_block(bank, pc, out, None)
        out.append("}\n")
    out.append("const block_t tbl_%02X[0x2000] = {" % bank.num)
    for pc in pcs:
        out.append("  [0x%04X] = %s," % (pc - bank.window, names[pc]))
    out.append("};")


def emit_hot(banks, hot, out):
    """Every block in fast RAM, as one function."""
    order = sorted(hot)
    index = {key: i + 1 for i, key in enumerate(order)}
    out.append('#include "cpu.h"\n#include "platform.h"\n')
    for num in sorted({k[0] for k in hot}):
        out.append("static const u16 hot_map_%02X[0x2000] = {" % num)
        for (n, pc) in order:
            if n == num:
                out.append("  [0x%04X] = %d," % (pc - banks[n].window, index[n, pc]))
        out.append("};")
    out.append("const u16 *hot_maps[32] = {")
    for num in sorted({k[0] for k in hot}):
        out.append("  [0x%02X] = hot_map_%02X," % (num, num))
    out.append("};\n")
    out.append("HOT u32 hot_run(u32 pc) {")
    out.append("  static void *const labels[] = {0,")
    for (n, pc) in order:
        out.append("    &&L%02X_%04X," % (n, pc))
    out.append("  };")
    out.append("  u32 e;")
    out.append("  goto *labels[pc];")
    out.append("dyn:")
    out.append("  if (cyc >= block_limit || pc < 0x8000) return pc;")
    out.append("  e = hot_lookup(pc);")
    out.append("  if (!e) return pc;")
    out.append("  goto *labels[e];")
    for (n, pc) in order:
        out.append("L%02X_%04X:" % (n, pc))
        emit_block(banks[n], pc, out, hot)
    out.append("}")


def emit_interpreter(out):
    """One 6502 instruction at a time, for code the recordings never reached."""
    ea = {"zp": "rd(pc + 1)", "zpx": "(u8)(rd(pc + 1) + X)", "zpy": "(u8)(rd(pc + 1) + Y)",
          "abs": "W", "abx": "(u16)(W + X)", "aby": "(u16)(W + Y)",
          "inx": "IND(rd(pc + 1) + X)", "iny": "(u16)(IND(rd(pc + 1)) + Y)"}
    out.append('#include "cpu.h"\n')
    out.append("#define W (rd(pc + 1) | rd(pc + 2) << 8)")
    out.append("u32 interp_step(u32 pc) {")
    out.append("  u32 next, ea = 0;\n  switch (rd(pc)) {")
    for code, (m, mode, c) in sorted(OPS.items()):
        size = SIZE[mode]
        line = "  case 0x%02X: next = pc + %d; CYC(%d); " % (code, size, c)
        if mode in ea:
            line += "ea = %s; " % ea[mode]
            if m in PAGE_READS:
                base = {"abx": ("W", "X"), "aby": ("W", "Y"), "iny": ("IND(rd(pc + 1))", "Y")}.get(mode)
                if base:
                    line += "PAGE(%s, %s); " % base
        val = "rd(pc + 1)" if mode == "imm" else "rd(ea)"
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
            line += ("{ int o = (signed char)rd(pc + 1); if (%s) { u32 t = (next + o) & 0xFFFF; "
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


def main():
    rom = open(ROM, "rb").read()[16:]
    prg = rom[:0x40000]
    seen = {}
    counts = {}
    for trace in TRACES:
        for line in open(os.path.join(trace, "coverage.txt")):
            off, pc, n = map(int, line.split())
            if pc >= 0x8000 and 0 <= off < len(prg):
                seen.setdefault(off // BANK_SIZE, set()).add(pc)
                counts[off // BANK_SIZE, pc] = counts.get((off // BANK_SIZE, pc), 0) + n
    entries = {int(line) for trace in TRACES for line in open(os.path.join(trace, "entries.txt"))}
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
    # Vectors
    for at in (0xFFFA, 0xFFFC, 0xFFFE):
        fixed.seeds.add(fixed.byte(at) | fixed.byte(at + 1) << 8)
    for b in banks.values():
        decode(b, by_window)
    decode(fixed, by_window)
    for b in banks.values():
        decode(b, by_window)
        add_entry_points(b, entries)

    os.makedirs(GEN, exist_ok=True)
    hot = pick_hot(banks, counts)
    total = 0
    for b in banks.values():
        out = []
        emit_bank(b, out, hot)
        with open(os.path.join(GEN, "bank_%02X.c" % b.num), "w") as f:
            f.write("\n".join(out) + "\n")
        total += len(b.instrs)
        print("bank %02X at $%04X: %5d instructions, %5d blocks" % (b.num, b.window, len(b.instrs), len(b.leaders)))
    out = []
    emit_hot(banks, hot, out)
    with open(os.path.join(GEN, "hot.c"), "w") as f:
        f.write("\n".join(out) + "\n")
    out = []
    emit_interpreter(out)
    with open(os.path.join(GEN, "interp.c"), "w") as f:
        f.write("\n".join(out) + "\n")
    with open(os.path.join(GEN, "tables.c"), "w") as f:
        f.write('#include "cpu.h"\n')
        for n in banks:
            f.write("extern const block_t tbl_%02X[0x2000];\n" % n)
        f.write("const block_t *const code_banks[32] = {\n")
        for n in banks:
            f.write("  [0x%02X] = tbl_%02X,\n" % (n, n))
        f.write("};\n")
    print("total %d instructions" % total)


if __name__ == "__main__":
    main()
