#!/usr/bin/env python3
"""Build the game for the SNES, from your own copy of the ROM.

    python3 tools/survey.py    # once: out/survey/, what the game does when it plays
    python3 tools/build.py     # out/gimmick.sfc

The game's code keeps its place: each ROM bank the machine runs from holds, at $8000,
$A000, $C000 and $E000, the NES banks one mapping of the FME-7 shows there. Instructions
that touch NES hardware become JSRs to src/runtime.s, in RAM every bank can see.
"""
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ops import OPS, SIZE

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, "out")
GEN = os.path.join(OUT, "gen")
SURVEY = os.path.join(OUT, "survey")
ROM = os.path.join(REPO, "Gimmick! (Japan).nes")
BANK = 0x2000
FIXED = 0x1F
NO_RETURN = {0xF319}        # reads a jump table inline, after its JSR
ROM_SIZE = 0x400000
FIRST_CODE_BANK = 32        # $A0: the first with the cartridge RAM at $6000
LAST_CODE_BANK = 63
BG_HALF, OBJ_HALF = 1, 8    # which banks' lower halves hold the converted tiles
PRG_HALF = 16               # and the NES banks, 4 in each; src/runtime.s has the same number
FRAME_DONE = (0xF296, 0xF29F)   # lda #$AC, sta $F0: the frame is done, wait for vblank
# Routines of the game's that do many PPU writes in vblank, done directly instead.
REPLACED = {0xF06B: "chr_all", 0xF3D3: "vram_flush"}

# 2C02 colours.
NES_RGB = [
    (84,84,84),(0,30,116),(8,16,144),(48,0,136),(68,0,100),(92,0,48),(84,4,0),(60,24,0),
    (32,42,0),(8,58,0),(0,64,0),(0,60,0),(0,50,60),(0,0,0),(0,0,0),(0,0,0),
    (152,150,152),(8,76,196),(48,50,236),(92,30,228),(136,20,176),(160,20,100),(152,34,32),(120,60,0),
    (84,90,0),(40,114,0),(8,124,0),(0,118,40),(0,102,120),(0,0,0),(0,0,0),(0,0,0),
    (236,238,236),(76,154,236),(120,124,236),(176,98,236),(228,84,236),(236,88,180),(236,106,100),(212,136,32),
    (160,170,0),(116,196,0),(76,208,32),(56,204,108),(56,180,204),(60,60,60),(0,0,0),(0,0,0),
    (236,238,236),(168,204,236),(188,188,236),(212,178,236),(236,174,236),(236,174,212),(236,180,176),(228,196,144),
    (204,210,120),(180,222,120),(168,226,144),(152,226,180),(160,214,228),(160,162,160),(0,0,0),(0,0,0),
]


def load_survey():
    seen, entries = {}, set()
    for line in open(os.path.join(SURVEY, "coverage.txt")):
        off, pc, n = map(int, line.split())
        if pc >= 0x8000 and 0 <= off < 0x40000:
            seen.setdefault(off // BANK, set()).add(pc)
        elif pc < 0x8000:
            sys.exit("code ran from $%04X" % pc)
    for line in open(os.path.join(SURVEY, "entries.txt")):
        entries.add(int(line))
    combos = []
    for line in open(os.path.join(SURVEY, "combos.txt")):
        c, t, n = line.split()
        c = int(c, 16)
        # $C000 holds DPCM samples and the CPU does not read it: the sound driver has the
        # samples, so ROM banks do not differ by what is there.
        combos.append(((c >> 16) & 63, (c >> 8) & 63, int(t) & 3, int(n)))
    merged = {}
    for b8, bA, used, n in combos:
        u, m = merged.get((b8, bA), (0, 0))
        merged[b8, bA] = (u | used, m + n)
    return seen, entries, [(k[0], k[1], v[0], v[1]) for k, v in merged.items()]


def decode(prg, seen):
    """Everything reached from what ran is an instruction. Returns {bank: {pc: (op, mode, arg, size)}}."""
    windows = {}
    for num, pcs in seen.items():
        w = {pc & 0xE000 for pc in pcs}
        if len(w) != 1:
            sys.exit("bank %02X runs in more than one window" % num)
        windows[num] = w.pop()
    windows[FIXED] = 0xE000
    fixed = prg[FIXED * BANK:]
    instrs = {num: {} for num in windows}
    todo = {num: list(pcs) for num, pcs in seen.items()}
    todo.setdefault(FIXED, [])
    for at in (0x1FFA, 0x1FFC, 0x1FFE):
        todo[FIXED].append(fixed[at] | fixed[at + 1] << 8)
    by_window = {}
    changed = True
    while changed:
        changed = False
        for num, stack in todo.items():
            w = windows[num]
            base = num * BANK
            while stack:
                pc = stack.pop()
                if pc in instrs[num] or not w <= pc < w + BANK:
                    continue
                changed = True
                op = prg[base + pc - w]
                info = OPS.get(op)
                if info is None:
                    instrs[num][pc] = None
                    continue
                m, mode, _ = info
                n = SIZE[mode]
                if pc + n > w + BANK:
                    instrs[num][pc] = None
                    continue
                arg = prg[base + pc - w + 1] if n == 2 else prg[base + pc - w + 1] | prg[base + pc - w + 2] << 8 if n == 3 else 0
                instrs[num][pc] = (m, mode, arg, n)
                nxt = pc + n
                if mode == "rel":
                    stack += [(nxt + (arg - 256 if arg >= 128 else arg)) & 0xFFFF, nxt]
                elif m == "jmp" and mode == "abs":
                    if w <= arg < w + BANK:
                        stack.append(arg)
                    elif arg >= 0xE000:
                        todo[FIXED].append(arg)
                elif m == "jsr":
                    if w <= arg < w + BANK:
                        stack.append(arg)
                    elif arg >= 0xE000:
                        todo[FIXED].append(arg)
                    if arg not in NO_RETURN:
                        stack.append(nxt)
                elif m not in ("jmp", "rts", "rti", "brk"):
                    stack.append(nxt)
    return windows, instrs


# ---- The stubs ---------------------------------------------------------------------

NAMED = {0x2000: "ppu_ctrl", 0x2001: "ppu_mask", 0x2005: "ppu_scroll", 0x2006: "ppu_addr", 0x2007: "ppu_data"}


class Stubs:
    def __init__(self):
        self.lines = []
        self.made = {}

    def gen(self, key, body):
        if key not in self.made:
            name = "gs_%d" % len(self.made)
            self.made[key] = name
            self.lines.append(".export %s\n%s:\n%s\n        rts" % (name, name, "\n".join("        " + b for b in body)))
        return self.made[key]

    def apu_store(self, reg, addr, index=None):
        i = ",%s" % index if index else ""
        return ["php", "st%s apu_regs + %d%s" % (reg, addr - 0x4000, i)] + (["plp"])

    def apu_kick(self, reg, addr):
        ch = (addr - 0x4003) // 4
        return ["php", "st%s apu_regs + %d" % (reg, addr - 0x4000), "inc apu_kick + %d" % ch, "plp"]


def stub_for(stubs, m, mode, a):
    """The label to JSR to in place of this instruction, or None to leave it alone."""
    reg = m[2] if m[:2] in ("st", "ld") else None
    if mode == "abs" and m in ("sta", "stx", "sty"):
        if a in NAMED:
            return "%s_%s" % (NAMED[a], reg)
        if a == 0x2003:
            return stubs.gen("nop", [])
        if a == 0x2004:
            return stubs.gen("nop", [])
        if a == 0x4014:
            if reg != "a":
                sys.exit("OAM DMA from %s" % reg)
            return "oam_dma_a"
        if a in (0x4016, 0x4017):
            return None  # the SNES's pad ports are at the same place
        if 0x4000 <= a < 0x4016:
            if a in (0x4003, 0x4007, 0x400B, 0x400F):
                return stubs.gen(("kick", reg, a), stubs.apu_kick(reg, a))
            return stubs.gen(("apu", reg, a), stubs.apu_store(reg, a))
        if 0x8000 <= a < 0xA000:
            return "fme_cmd_%s" % reg
        if 0xA000 <= a < 0xC000:
            return "fme_val_%s" % reg
        if 0xC000 <= a < 0xE000:
            return "sb_cmd_%s" % reg
        if a >= 0xE000:
            return "sb_data_%s" % reg
        if 0x2000 <= a < 0x6000:
            sys.exit("store to $%04X" % a)
    if mode == "abs" and m in ("lda", "ldx", "ldy"):
        if a == 0x2002:
            return "ppu_status_%s" % reg
        if a == 0x4015:
            return stubs.gen(("r4015", reg), ["ld%s #0" % reg])
        if a == 0x2007:
            return "ppu_data_read_%s" % reg
    if mode in ("abx", "aby") and m in ("sta",):
        i = "x" if mode == "abx" else "y"
        if 0x4000 <= a < 0x4016:
            return stubs.gen(("apux", i, a), stubs.apu_store("a", a, i))
    return None


def hardware(a):
    return 0x2000 <= a < 0x6000 and a not in (0x4016, 0x4017)


def find_patches(instrs, stubs):
    """{bank: {pc: label}}. Stops on any touch of hardware it has no way to translate."""
    patches = {}
    bad = []
    for num, code in instrs.items():
        p = patches.setdefault(num, {})
        for pc, ins in code.items():
            if ins is None:
                bad.append("%02X:%04X not an instruction" % (num, pc))
                continue
            m, mode, a, n = ins
            if mode not in ("abs", "abx", "aby") or m in ("jmp", "jsr"):
                continue
            writes = m[:2] == "st" or m in ("inc", "dec", "asl", "lsr", "rol", "ror")
            if hardware(a) or (a >= 0x8000 and writes):
                label = stub_for(stubs, m, mode, a)
                if label is None:
                    if a not in (0x4016, 0x4017):
                        bad.append("%02X:%04X %s %s $%04X" % (num, pc, m, mode, a))
                else:
                    p[pc] = label
    return patches, bad


# ---- Which ROM banks to make --------------------------------------------------------

def plan_banks(combos, usable):
    """Cover what each mapping used with as few banks as possible."""
    needs = {}
    for b8, bA, used, n in combos:
        need = (b8 if used & 1 else None, bA if used & 2 else None)
        needs[need] = needs.get(need, 0) + n
    banks = []
    # Most specific first, each into the first bank it agrees with.
    for need in sorted(needs, key=lambda k: (-sum(x is not None for x in k), -needs[k])):
        for b in banks:
            if all(x is None or y is None or x == y for x, y in zip(need, b)):
                for i in range(2):
                    if b[i] is None:
                        b[i] = need[i]
                break
        else:
            banks.append(list(need))
    print("%d mappings, %d distinct uses, %d ROM banks (%d usable)" % (len(combos), len(needs), len(banks), usable))
    return banks


def build_tables(combos, banks):
    """Two small tables turn the FME-7's banks into an index, and that into a ROM bank."""
    vals = [sorted({c[i] for c in combos} | {b[i] for b in banks if b[i] is not None}) for i in range(2)]
    sizes = [len(v) for v in vals]
    print("values per window: %s; table %d" % (sizes, sizes[0] * sizes[1]))
    exact = {c[:2]: c[2] for c in combos}
    table = [pick_bank((a, b), banks, exact.get((a, b))) for a in vals[0] for b in vals[1]]
    idx = []
    for i, stride in enumerate((sizes[1], 1)):
        col = [0] * 32
        for j, v in enumerate(vals[i]):
            col[v & 31] = j * stride
        idx.append(col)
    return idx, table


def pick_bank(want, banks, used):
    """The bank that shows what this mapping uses, then as much of the rest as it can."""
    best, score = 0, -1
    for n, b in enumerate(banks):
        s = 0
        for i, weight in enumerate((16, 4)):
            if b[i] == want[i]:
                s += weight * 2
            elif b[i] is None:
                s += weight
            elif used is not None and used >> i & 1:
                s -= 1000
        if s > score:
            best, score = n, s
    return best


# ---- Tiles --------------------------------------------------------------------------

def tile_2bpp(t):
    """NES tiles keep their two planes apart; the SNES interleaves them by row."""
    return bytes(x for y in range(8) for x in (t[y], t[8 + y]))


def convert_chr(chr_rom):
    bg, obj = bytearray(), bytearray()
    for t in range(len(chr_rom) // 16):
        s = tile_2bpp(chr_rom[t * 16:t * 16 + 16])
        bg += s
        obj += s + bytes(16)
    return bytes(bg), bytes(obj)


def attr_table():
    out = []
    for a in range(256):
        v = a & 0xC0
        v |= 0 if a & 0x20 else 0x20    # in front of the background: priority 2
        v |= (a & 3) << 1
        out.append(v)
    return out


# ---- The build ----------------------------------------------------------------------

def bytes_asm(name, vals):
    lines = [".export %s\n%s:" % (name, name)]
    for i in range(0, len(vals), 16):
        lines.append("        .byte " + ",".join("$%02X" % v for v in vals[i:i + 16]))
    return "\n".join(lines) + "\n"


def run(*cmd):
    subprocess.run(cmd, check=True, cwd=REPO)


def main():
    rom = open(ROM, "rb").read()[16:]
    prg, chr_rom = rom[:0x40000], rom[0x40000:0x60000]
    os.makedirs(GEN, exist_ok=True)
    seen, entries, combos = load_survey()
    windows, instrs = decode(prg, seen)
    stubs = Stubs()
    patches, bad = find_patches(instrs, stubs)
    for line in bad[:40]:
        print("  cannot translate:", line)
    print("%d instructions; %d stubs; %d patched" % (sum(len(c) for c in instrs.values()), len(stubs.made),
                                                    sum(len(p) for p in patches.values())))
    usable = LAST_CODE_BANK - FIRST_CODE_BANK + 1
    banks = plan_banks(combos, usable)
    if len(banks) > usable:
        sys.exit("too many ROM banks")
    idx, table = build_tables(combos, banks)

    # Tables and stubs for the assembler
    s = '.segment "TABLES"\n'
    colors = [min(r * 31 // 236, 31) | min(g * 31 // 236, 31) << 5 | min(b * 31 // 236, 31) << 10 for r, g, b in NES_RGB]
    s += bytes_asm("ColorLo", [c & 0xFF for c in colors])
    s += bytes_asm("ColorHi", [c >> 8 for c in colors])
    s += bytes_asm("AttrTable", attr_table())
    s += bytes_asm("ChrBgBanks", [0xC0 + BG_HALF + p // 32 for p in range(128)])
    s += bytes_asm("ChrObjBanks", [0xC0 + OBJ_HALF + p // 16 for p in range(128)])
    s += bytes_asm("ComboIdx8", idx[0])
    s += bytes_asm("ComboIdxA", idx[1])
    s += bytes_asm("ComboTable", [0x80 + FIRST_CODE_BANK + b for b in table])
    fixed = prg[FIXED * BANK:]
    first = pick_bank((0, 0), banks, None)
    s += bytes_asm("FirstBank", [0x80 + FIRST_CODE_BANK + first])
    for name, at in (("NesNmi", 0x1FFA), ("NesReset", 0x1FFC), ("NesIrq", 0x1FFE)):
        s += bytes_asm(name, [fixed[at], fixed[at + 1]])
    s += '.segment "WCODE"\n.import apu_regs, apu_kick\n.p816\n.a8\n.i8\n.smart off\n'
    s += "\n".join(stubs.lines) + "\n"
    gen_s = os.path.join(GEN, "gen.s")
    open(gen_s, "w").write(".p816\n" + s)

    objs = []
    for src in (os.path.join(REPO, "src", "boot.s"), os.path.join(REPO, "src", "runtime.s"), gen_s):
        o = os.path.join(GEN, os.path.basename(src) + ".o")
        run("ca65", "-g", "-I", os.path.join(REPO, "src"), src, "-o", o)
        objs.append(o)
    boot = os.path.join(GEN, "bank0.bin")
    labels = os.path.join(GEN, "labels.txt")
    run("ld65", "-C", os.path.join(REPO, "src", "snes.cfg"), "-o", boot, "-Ln", labels, *objs)
    addr = {}
    for line in open(labels):
        m = re.match(r"al ([0-9A-F]+) \.(\S+)", line)
        if m:
            addr[m.group(2)] = int(m.group(1), 16)

    # The NES banks with their hardware accesses changed
    patched = {}
    for num in range(32):
        data = bytearray(prg[num * BANK:(num + 1) * BANK])
        for pc, label in patches.get(num, {}).items():
            w = windows[num]
            t = addr[label]
            if not 0x0800 <= t < 0x2000:
                sys.exit("stub %s at $%04X" % (label, t))
            data[pc - w:pc - w + 3] = bytes([0x20, t & 0xFF, t >> 8])
        if num == FIXED:
            t = addr["frame_done"]
            for pc in FRAME_DONE:
                data[pc - 0xE000:pc - 0xE000 + 4] = bytes([0x20, t & 0xFF, t >> 8, 0xEA])
            for pc, label in REPLACED.items():
                t = addr[label]
                data[pc - 0xE000:pc - 0xE000 + 4] = bytes([0x4C, t & 0xFF, t >> 8, 0xEA])
        patched[num] = bytes(data)

    image = bytearray(b"\xFF" * ROM_SIZE)
    image[0x8000:0x10000] = open(boot, "rb").read()
    for n, b in enumerate(banks):
        at = (FIRST_CODE_BANK + n) * 0x10000 + 0x8000
        for i in range(2):
            page = b[i] if b[i] is not None else 0
            image[at + i * BANK:at + (i + 1) * BANK] = patched[page]
        image[at + 2 * BANK:at + 3 * BANK] = patched[0x0F]
        image[at + 3 * BANK:at + 4 * BANK] = patched[FIXED]
    for num in range(32):
        at = (PRG_HALF + num // 4) * 0x10000 + (num % 4) * BANK
        image[at:at + BANK] = prg[num * BANK:(num + 1) * BANK]
    bg, obj = convert_chr(chr_rom)
    for p in range(128):
        at = (BG_HALF + p // 32) * 0x10000 + (p % 32) * 0x400
        image[at:at + 0x400] = bg[p * 0x400:(p + 1) * 0x400]
        at = (OBJ_HALF + p // 16) * 0x10000 + (p % 16) * 0x800
        image[at:at + 0x800] = obj[p * 0x800:(p + 1) * 0x800]

    # Checksum
    image[0xFFDC:0xFFE0] = b"\xFF\xFF\x00\x00"
    total = sum(image) & 0xFFFF
    image[0xFFDC:0xFFE0] = bytes([(total & 0xFF) ^ 0xFF, (total >> 8) ^ 0xFF, total & 0xFF, total >> 8])
    path = os.path.join(OUT, "gimmick.sfc")
    open(path, "wb").write(image)
    print("%s: %d KB" % (path, len(image) // 1024))


if __name__ == "__main__":
    main()
