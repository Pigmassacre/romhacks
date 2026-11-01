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
import spcasm

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
SPC_BANK = 24               # all of it: src/boot.s has the same number, as $D8
PRG_HALF = 16               # and the NES banks, 4 in each; src/runtime.s has the same number
FRAME_DONE = (0xF296, 0xF29F)   # lda #$AC, sta $F0: the frame is done, wait for vblank
SOUND_HOOK = 0xEAA1         # sta $8000, in the NMI just after the sound code
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
        if a == 0x4015:
            return stubs.gen(("dmc", reg), ["php", "st%s apu_regs + $15" % reg, "inc apu_kick + 4", "plp"])
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
            # Which register it is only shows now: apu_indexed sees to a new note.
            return stubs.gen(("apux", i, a), ["php", "sta apu_regs + %d,%s" % (a - 0x4000, i), "pha", "phx",
                                              "t%sa" % i, "clc", "adc #%d" % (a - 0x4000), "jsr apu_indexed",
                                              "plx", "pla", "plp"])
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


# ---- Sound ---------------------------------------------------------------------------

SPC_ORIGIN = 0x0200
SPC_CODE = 0x0600
SPC_PITCH = 0x2000
SPC_BRR = 0x4000
DPCM_STEP = 3               # samples kept: 1 in this many, for them all to fit
DMC_HZ = [4181.71, 4709.93, 5264.04, 5593.04, 6257.95, 7046.35, 7918.63, 8363.42,
          9419.86, 11186.1, 12604.0, 13982.6, 16884.6, 21306.8, 24858.0, 33143.9]
NOISE_PERIODS = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
NOISE_HZ = [0, 16, 21, 25, 31, 42, 50, 63, 83, 100, 125, 167, 200, 250, 333, 400, 500, 667, 800, 1000,
            1300, 1600, 2000, 2700, 3200, 4000, 5300, 6400, 8000, 10700, 16000, 32000]


def brr_encode(samples, loop=False):
    """Samples to 9-byte BRR blocks, trying each shift and filter."""
    if len(samples) % 16:
        samples = samples + [0] * (16 - len(samples) % 16)
    out = bytearray()
    p1 = p2 = 0

    def clamp(v):
        return max(-32768, min(32767, v))

    for at in range(0, len(samples), 16):
        block = samples[at:at + 16]
        best = None
        for flt in range(4):
            for rng in range(13):
                a, b = p1, p2
                err = 0
                nibs = []
                for s in block:
                    if flt == 0:
                        pred = 0
                    elif flt == 1:
                        pred = a + (-a >> 4)
                    elif flt == 2:
                        pred = a * 2 + ((-a * 3) >> 5) - b + (b >> 4)
                    else:
                        pred = a * 2 + ((-a * 13) >> 6) - b + ((b * 3) >> 4)
                    n = ((s - pred) * 2 >> rng) if rng else (s - pred) * 2
                    n = max(-8, min(7, n))
                    v = ((n << rng) >> 1)
                    v = clamp(v + pred)
                    v = clamp(v * 2) // 2  # the DSP wraps at 15 bits, nearly
                    err += (v - s) ** 2
                    nibs.append(n & 15)
                    a, b = v, a
                if best is None or err < best[0]:
                    best = (err, flt, rng, nibs, a, b)
                if err == 0:
                    break
        _, flt, rng, nibs, p1, p2 = best
        out.append(rng << 4 | flt << 2)
        for i in range(0, 16, 2):
            out.append(nibs[i] << 4 | nibs[i + 1])
    out[-9] |= 1 | (2 if loop else 0)
    return bytes(out)


def duty_sample(duty):
    """16 samples of a pulse wave, one BRR block that loops."""
    pattern = {0: "0100000000000000", 1: "0110000000000000", 2: "0111100000000000", 3: "1001111111111111"}[duty]
    pattern = {0: "1100000000000000", 1: "1111000000000000", 2: "1111111100000000", 3: "1111111111110000"}[duty]
    out = bytearray([0xC3])
    nibs = [7 if c == "1" else 8 for c in pattern]     # +7, -8 in 4 bits
    for i in range(0, 16, 2):
        out.append(nibs[i] << 4 | nibs[i + 1])
    return bytes(out)


def triangle_sample():
    levels = [15 - i for i in range(16)] + list(range(16))
    nibs = [(n - 8) & 15 for n in levels]
    out = bytearray()
    for b in range(2):
        out.append(0xC0 | (3 if b == 1 else 0))
        for i in range(0, 16, 2):
            out.append(nibs[b * 16 + i] << 4 | nibs[b * 16 + i + 1])
    return bytes(out)


def dpcm_decode(data):
    """1-bit deltas to samples, one in DPCM_STEP, with the slow drift taken out."""
    level = 64
    raw = []
    for byte in data:
        for bit in range(8):
            if byte >> bit & 1:
                level = min(level + 2, 127)
            else:
                level = max(level - 2, 0)
            raw.append(level)
    out = []
    dc = raw[0] if raw else 64
    for i in range(0, len(raw), DPCM_STEP):
        part = raw[i:i + DPCM_STEP]
        v = sum(part) / len(part)
        dc += (v - dc) / 256
        out.append(int(max(-32768, min(32767, (v - dc) * 300))))
    return out


def build_spc(prg):
    survey = os.path.join(OUT, "survey_snd", "snd.txt")
    samples = {}
    for line in open(survey):
        f = line.split()
        if f[0] == "D":
            bank, addr, length = int(f[1], 16), int(f[2], 16), int(f[3], 16)
            if bank:
                samples[(bank, addr, length)] = 1
    src = []
    data = bytearray()

    def place(brr, loop_at=0):
        at = SPC_BRR + len(data)
        data.extend(brr)
        src.append((at, at + loop_at))
        return len(src) - 1

    # 0-3 duty, 4 triangle, then samples
    for d in range(4):
        place(duty_sample(d))
    place(triangle_sample())
    lst = []
    for (bank, addr, length) in sorted(samples):
        off = bank * BANK + addr * 64
        size = length * 16 + 1
        brr = brr_encode(dpcm_decode(prg[off:off + size]))
        lst.append((bank, addr, length, place(brr)))
    if SPC_BRR + len(data) >= 0xFFC0:
        sys.exit("too many samples: %d bytes" % len(data))
    print("sound: %d DPCM samples, %d KB of BRR" % (len(lst), len(data) // 1024))

    pitch = bytearray()
    for t in range(4096):
        p = min(229090 // (t + 1), 0x3FFF)
        pitch += bytes([p & 0xFF, p >> 8])
    noise = []
    for per in NOISE_PERIODS:
        hz = 1789773 / per
        noise.append(min(range(32), key=lambda i: abs(NOISE_HZ[i] - hz)))
    tables = "dpcm_list:\n"
    for bank, addr, length, n in lst:
        tables += "  .byte $%02X,$%02X,$%02X,%d\n" % (bank, addr, length, n)
    tables += "  .byte $FF\ndpcm_pitch:\n"
    for hz in DMC_HZ:
        tables += "  .word %d\n" % min(int(hz / DPCM_STEP * 4096 / 32000), 0x3FFF)
    tables += "noise_clock:\n  .byte " + ",".join(str(v) for v in noise) + "\n"
    text = open(os.path.join(REPO, "src", "sound.spc")).read() + tables
    code, sym = spcasm.assemble(text, SPC_CODE, {"src_duty": 0, "src_tri": 4, "dir_page": SPC_ORIGIN >> 8,
                                                 "pitch_hi": SPC_PITCH >> 8, "tri_vol": 56, "dpcm_vol": 64})
    print("sound driver: %d bytes" % len(code))
    if SPC_CODE + len(code) > SPC_PITCH:
        sys.exit("the sound driver is too big")
    blob = bytearray(SPC_BRR + len(data) - SPC_ORIGIN)
    for n, (a, l) in enumerate(src):
        blob[n * 4:n * 4 + 4] = bytes([a & 0xFF, a >> 8, l & 0xFF, l >> 8])
    blob[SPC_CODE - SPC_ORIGIN:SPC_CODE - SPC_ORIGIN + len(code)] = code
    blob[SPC_PITCH - SPC_ORIGIN:SPC_PITCH - SPC_ORIGIN + len(pitch)] = pitch
    blob[SPC_BRR - SPC_ORIGIN:] = data
    return bytes(blob)


# ---- The notices on the title screen ------------------------------------------------

NOTICES = ["PORT BY PIGMASSACRE", "AI SLOP - DO NOT PLAY"]
FONT_PAGE = 0x40            # the intro's letters: tile 1 is A
BLANK_HALF = 29             # a lower half left at 0, for blank tiles
OVERLAY_HALF = 30           # where they go: src/boot.s has the same number, as $DE
TILE_BLANK, TILE_DASH, TILE_NONE = 0, 27, 127

# Clouds for parallax, on BG2: the game's own page of them, arranged as it does in stage 1
# and in stages 2 and 4. An entry is a tile of that page; S is sky, L and W its fill tiles.
CLOUD_PAGE, FILL_PAGE, TILE_CLOUDS = 0x01, 0x00, 28
PUFFS = {
    3: {5: (0x09, 0x06, 0x16, 0x07, 0x17, 0x08, 0x18)},
    6: {0: (0x02, 0x12, 0x04, 0x14), 30: (0x00, 0x10)},
    7: {0: (0x03, 0x13, 0x05, 0x15, 0x08, 0x18), 13: (0x09, 0x08, 0x18), 29: (0x09, 0x01, 0x11)},
    9: {9: (0x09, 0x06, 0x16, 0x07)},
    11: {21: (0x09, 0x06, 0x16, 0x07, 0x17)},
}
CLOUD_BANK = {
    12: {4: (0x08, 0x18)},
    13: {0: (0x0A, 0x1A, 0x0B, 0x1B, 0x2B, 0x3B, 0x0E, 0x1E, 0x0A, 0x1A, 0x07, 0x17)},
    14: {0: ("L", 0x38, 0x2A, 0x3A, "W", "W", 0x2C, "L", "L", "L"), 14: (0x08, 0x18)},
    15: {0: (0x29, "W", "W", "W", "W", "W", "W", 0x3D, "L", "L", 0x0B, 0x1B, 0x0A, 0x1A, 0x2B, 0x3B, 0x0A, 0x1A,
             0x0B, 0x1B, 0x0C, 0x1C, 0x0D, 0x1D, 0x0E, 0x1E, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B)},
}


def build_overlay(chr_rom):
    """Tiles and a map for BG2, which shows only on the title: 4 KB for VRAM word $6800."""
    def recolour(tile):
        # A box, not see-through: 0 black, shading grey, the letter white.
        out = bytearray(16)
        for y in range(8):
            lo, hi = tile[y], tile[8 + y]
            a = b = 0
            for x in range(8):
                v = (lo >> (7 - x) & 1) | (hi >> (7 - x) & 1) << 1
                c = {0: 1, 1: 2, 2: 2, 3: 3}[v]
                a |= (c & 1) << (7 - x)
                b |= (c >> 1) << (7 - x)
            out[y * 2], out[y * 2 + 1] = a, b
        return bytes(out)

    tiles = bytearray(16 * 128)
    base = FONT_PAGE * 0x400
    tiles[0:16] = recolour(bytes(16))
    for i in range(26):
        tiles[(i + 1) * 16:(i + 2) * 16] = recolour(chr_rom[base + (i + 1) * 16:base + (i + 2) * 16])
    dash = bytearray(16)
    dash[3], dash[4] = 0x7E, 0x7E
    dash[8 + 3], dash[8 + 4] = 0x7E, 0x7E
    tiles[TILE_DASH * 16:(TILE_DASH + 1) * 16] = recolour(bytes(dash))
    for i in range(64):
        at = (TILE_CLOUDS + i) * 16
        tiles[at:at + 16] = tile_2bpp(chr_rom[CLOUD_PAGE * 0x400 + i * 16:CLOUD_PAGE * 0x400 + i * 16 + 16])
    for i, t in enumerate((0x11, 0x01)):
        at = (TILE_CLOUDS + 64 + i) * 16
        tiles[at:at + 16] = tile_2bpp(chr_rom[FILL_PAGE * 0x400 + t * 16:FILL_PAGE * 0x400 + t * 16 + 16])

    def cloud_map(rows, fill_from):
        none = bytes([TILE_NONE, 0x01])
        out = [[none] * 32 for _ in range(32)]

        def cell(v):
            t = TILE_CLOUDS + (64 if v == "L" else 65 if v == "W" else v)
            return bytes([t, 0x01])

        for table in rows:
            for r, parts in table.items():
                for c, seq in parts.items():
                    for i, v in enumerate(seq):
                        out[r][(c + i) % 32] = cell(v)
        if fill_from is not None:
            for r in range(fill_from, 22):
                for c in range(32):
                    out[r][c] = cell("W" if r > 17 else "L")
        return b"".join(w for row in out for w in row)

    maps = cloud_map([PUFFS, CLOUD_BANK], 16) + cloud_map([PUFFS], None)

    word = lambda t, front=True: bytes([t, 0x01 | 0x10 | (0x20 if front else 0)])  # tile 256 + t, palette 4
    screen = [[word(TILE_NONE, False)] * 32 for _ in range(32)]
    top = 22
    width = max(len(t) for t in NOTICES) + 2
    left = (32 - width) // 2
    for r in range(top - 1, top + 2 * len(NOTICES)):
        for c in range(left, left + width):
            screen[r][c] = word(TILE_BLANK)
    for n, text in enumerate(NOTICES):
        c = (32 - len(text)) // 2
        for i, ch in enumerate(text):
            t = TILE_BLANK if ch == " " else TILE_DASH if ch == "-" else ord(ch) - 64
            screen[top + n * 2][c + i] = word(t)
    return bytes(tiles) + b"".join(w for row in screen for w in row) + maps


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
    patches[FIXED][SOUND_HOOK] = "sound_hook"
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
    # Pages from $80 are the blank ones parallax puts in place of the clouds' page.
    s += bytes_asm("ChrBgBanks", [0xC0 + BG_HALF + p // 32 for p in range(128)] + [0xC0 + BLANK_HALF] * 128)
    s += bytes_asm("ChrObjBanks", [0xC0 + OBJ_HALF + p // 16 for p in range(128)])
    s += bytes_asm("ComboIdx8", idx[0])
    s += bytes_asm("ComboIdxA", idx[1])
    s += bytes_asm("ComboTable", [0x80 + FIRST_CODE_BANK + b for b in table])
    fixed = prg[FIXED * BANK:]
    first = pick_bank((0, 0), banks, None)
    s += bytes_asm("FirstBank", [0x80 + FIRST_CODE_BANK + first])
    for name, at in (("NesNmi", 0x1FFA), ("NesReset", 0x1FFC), ("NesIrq", 0x1FFE)):
        s += bytes_asm(name, [fixed[at], fixed[at + 1]])
    spc = build_spc(prg)
    s += bytes_asm("SpcAddr", [SPC_ORIGIN & 0xFF, SPC_ORIGIN >> 8])
    s += bytes_asm("SpcEntry", [SPC_CODE & 0xFF, SPC_CODE >> 8])
    s += bytes_asm("SpcSize", [len(spc) & 0xFF, len(spc) >> 8])
    s += '.segment "WCODE"\n.import apu_regs, apu_kick, apu_indexed\n.p816\n.a8\n.i8\n.smart off\n'
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
    image[SPC_BANK * 0x10000:SPC_BANK * 0x10000 + len(spc)] = spc
    image[BLANK_HALF * 0x10000:BLANK_HALF * 0x10000 + 0x8000] = bytes(0x8000)
    overlay = build_overlay(chr_rom)
    image[OVERLAY_HALF * 0x10000:OVERLAY_HALF * 0x10000 + len(overlay)] = overlay
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
