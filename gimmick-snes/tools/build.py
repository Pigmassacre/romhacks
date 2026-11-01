#!/usr/bin/env python3
"""Build the game for the SNES, from your own copy of the ROM.

    python3 tools/survey.py    # once: out/survey*/, what the game does when it plays
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
CLOUD_PAGE = 0x01           # src/runtime.s has the same number
NO_RETURN = {0xF319}        # reads a jump table inline, after its JSR
ROM_SIZE = 0x400000
FIRST_CODE_BANK = 32        # $A0: the first with the cartridge RAM at $6000
LAST_CODE_BANK = 63
ALIAS_HALF, OBJ_HALF = 1, 8 # which banks' lower halves hold the converted tiles
SPC_BANK = 24               # all of it: src/boot.s has the same number, as $D8
PRG_HALF = 16               # and the NES banks, 4 in each; src/runtime.s has the same number
FRAME_DONE = (0xF296, 0xF29F)   # lda #$AC, sta $F0: the frame is done, wait for vblank
SOUND_HOOK = 0xEAA1         # sta $8000, in the NMI just after the sound code
# Routines of the game's that do many PPU writes in vblank, done directly instead.
REPLACED = {0xF06B: "chr_all", 0xF3D3: "vram_flush"}

# 2C02 colours.
NES_RGB = [tuple(bytes.fromhex(c)) for c in """
666666 002A88 1412A7 3B00A4 5C007E 6E0040 6C0600 561D00 333500 0B4800 005200 004F08 00404D 000000 000000 000000
ADADAD 155FD9 4240FF 7527FE A01ACC B71E7B B53120 994E00 6B6D00 388700 0C9300 008F32 007C8D 000000 000000 000000
FFFEFF 64B0FF 9290FF C676FF F36AFF FE6ECC FE8170 EA9E22 BCBE00 88D800 5CE430 45E082 48CDDE 4F4F4F 000000 000000
FFFEFF C0DFFF D3D2FF E8C8FF FBC2FF FEC4EA FECCC5 F7D8A5 E4E594 CFEF96 BDF4AB B3F3CC B5EBF2 B8B8B8 000000 000000
""".split()]


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
        col = [0] * 64
        for j, v in enumerate(vals[i]):
            col[v & 63] = j * stride
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
    obj = bytearray()
    for t in range(len(chr_rom) // 16):
        obj += tile_2bpp(chr_rom[t * 16:t * 16 + 16]) + bytes(16)
    return bytes(obj)


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
        # The DSP does not clear what came before when a sample starts: no filter at first.
        for flt in range(4 if at else 1):
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


def short_noise_sample():
    """The noise channel's short mode: 93 steps that repeat. 16 times over, to fill whole blocks."""
    lfsr, steps = 1, []
    for _ in range(93):
        steps.append(lfsr & 1)
        lfsr = lfsr >> 1 | ((lfsr ^ lfsr >> 6) & 1) << 14
    bits = steps * 16
    out = bytearray()
    for b in range(0, len(bits), 16):
        out.append(0xC0 | (3 if b + 16 >= len(bits) else 0))
        nibs = [8 if v else 7 for v in bits[b:b + 16]]
        for i in range(0, 16, 2):
            out.append(nibs[i] << 4 | nibs[i + 1])
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
    # The NES's output stays where it ends; this one stops at 0, which would click.
    fade = min(64, len(out))
    for i in range(fade):
        out[-1 - i] = out[-1 - i] * i // fade
    return out


def build_spc(prg):
    survey = os.path.join(OUT, "survey", "snd.txt")
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

    # 0-3 duty, 4 triangle, 5 the noise's short mode, then samples
    for d in range(4):
        place(duty_sample(d))
    place(triangle_sample())
    place(short_noise_sample())
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
    tables += "noise_pitch:\n"
    for per in NOISE_PERIODS:
        tables += "  .word %d\n" % min(int(1789773 / per * 4096 / 32000), 0x3FFF)
    text = open(os.path.join(REPO, "src", "sound.spc")).read() + tables
    code, sym = spcasm.assemble(text, SPC_CODE, {"src_duty": 0, "src_tri": 4, "src_short": 5, "dir_page": SPC_ORIGIN >> 8,
                                                 "pitch_hi": SPC_PITCH >> 8, "tri_vol": 70, "dpcm_vol": 100})
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


# ---- Gimmick! 1.5, as options --------------------------------------------------------

HACK_BANK = 0x20
HOOKS = {(0x1E, 0x8199): "opt_jump", (0x1E, 0x81C3): "opt_star", (0x1E, 0x81DA): "opt_bheld",
         (0x1D, 0x8469): "opt_fx", (0x1D, 0x8151): "opt_water"}
FAR_NAMES = {"opt_jump": "Far_Jump", "opt_star": "Far_StarButton", "opt_bheld": "Far_BHeld",
             "opt_fx": "Far_FxDraw", "opt_water": "Far_Water"}
PAD_READ = 0xF2D7           # lda $4016: the first pad, in the game's read loop


SEG_RE = re.compile(r"^\s*;@\s*seg\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s+\$?([0-9A-Fa-f]+)\s*(.*)$")


def assemble_15():
    """Its source is split by `;@ seg <bank> <start> <end>` lines into pieces for each place in
    the ROM. They are assembled in one run of asm6, so that labels resolve across them, with
    a table of their lengths after them that says where each one ends."""
    src = os.path.join(REPO, "src", "gimmick-1.5")
    work = os.path.join(GEN, "gimmick-1.5")
    os.makedirs(work, exist_ok=True)
    prologue, segs, cur = [], [], None
    for line in open(os.path.join(src, "main.asm")):
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
    # asm6 reads arguments that start with "/" as options, so the paths are relative.
    r = subprocess.run([os.path.join(REPO, "tools", "asm6"), "-q", os.path.relpath(gen, src), os.path.relpath(binary, src)],
                       cwd=src, capture_output=True, text=True)
    if r.returncode:
        sys.exit("asm6 failed: " + r.stdout + r.stderr)
    blob = open(binary, "rb").read()
    table = len(blob) - 2 * len(segs)
    out, pos = [], 0
    for i, (bank, start, end, name, lines) in enumerate(segs):
        n = blob[table + 2 * i] | blob[table + 2 * i + 1] << 8
        out.append((bank, start, end, name, blob[pos:pos + n]))
        pos += n
    return out


def apply_15(prg):
    """(prg with bank $20 and the far calls in, {hook site: label}, {far name: address},
    seeds for the decoder, the fixed bank's range that is no longer the game's.)"""
    out = bytearray(prg) + bytes(BANK)
    hooks, far, seeds = {}, {}, {FIXED: set(), HACK_BANK: set()}
    fixed_range = None
    for bank, start, end, name, code in assemble_15():
        num = FIXED if bank == 0x3F else bank
        if (num, start) in HOOKS:
            # The hook's first instruction is the JSR to the far call: it goes through a switch.
            if code[0] != 0x20:
                sys.exit("1.5's hook at %02X:%04X is not a JSR" % (num, start))
            label = HOOKS[(num, start)]
            hooks[(num, start)] = (label, code)
            far[FAR_NAMES[label]] = code[1] | code[2] << 8
            continue
        if num not in (FIXED, HACK_BANK):
            sys.exit("a part of Gimmick! 1.5 at %02X:%04X that this build does not know" % (num, start))
        at = num * BANK + (start & 0x1FFF)
        out[at:at + len(code)] = code
        if num == FIXED:
            fixed_range = (start, end)
        elif num == HACK_BANK:
            # HackEntry, then its table of routines (each less 1, for an RTS).
            seeds[HACK_BANK].add(start)
            at = code.find(bytes([0x60])) + 1
            for i in range(5):
                seeds[HACK_BANK].add((code[at + i * 2] | code[at + i * 2 + 1] << 8) + 1)
    seeds[FIXED] = set(far.values())
    return bytes(out), hooks, far, seeds, fixed_range


# ---- The world map in Mode 7 ---------------------------------------------------------

MODE7_HALF = 26             # src/runtime.s has the same number, as $DA
MAP_PAGES = (0x54, 0x55, 0x02, 0x2C)    # what the game maps at PPU $1000 there
MAP_AT = 48                 # the map's cell where the NES's top left goes
M7_FRAMES = 72


def build_mode7(chr_rom):
    """Mode 7 has one map byte for each cell and one palette for all its tiles, so each tile
    and palette the world map uses becomes a tile: 32 KB, the map and then its tiles."""
    d = open(os.path.join(OUT, "survey", "map_0.bin"), "rb").read()
    ids = {}
    tiles = bytearray(16384)     # tile 0 stays clear
    grid = bytearray(16384)
    for r in range(30):
        for c in range(32):
            t = d[r * 32 + c]
            a = d[0x3C0 + (r >> 2) * 8 + (c >> 2)]
            pal = a >> (((r & 2) << 1) | (c & 2)) & 3
            key = (t, pal)
            if key not in ids:
                ids[key] = len(ids) + 1
                page = MAP_PAGES[t >> 6]
                off = page * 0x400 + (t & 63) * 16
                for y in range(8):
                    for x in range(8):
                        v = (chr_rom[off + y] >> (7 - x) & 1) | (chr_rom[off + 8 + y] >> (7 - x) & 1) << 1
                        tiles[ids[key] * 64 + y * 8 + x] = pal * 16 + v if v else 0
            # The game has a vertical scroll of $E8 here, 8 lines short of a whole screen.
            sr = (r + 1) % 30
            grid[(MAP_AT + sr) * 128 + MAP_AT + c] = ids[key]
    if len(ids) > 255:
        sys.exit("too many tiles for Mode 7: %d" % len(ids))
    print("world map: %d Mode 7 tiles" % len(ids))
    return bytes(grid) + bytes(tiles)


def mode7_frames():
    """The island's arrival: a turn and a half, from a long way off, slowing to rest."""
    import math
    out = []
    for i in range(M7_FRAMES):
        t = 1 - i / M7_FRAMES
        t = t * t
        ang = t * math.pi * 3
        scale = 1 + t * 5
        a = int(math.cos(ang) * scale * 256) & 0xFFFF
        b = int(math.sin(ang) * scale * 256) & 0xFFFF
        c = int(-math.sin(ang) * scale * 256) & 0xFFFF
        out += [a & 0xFF, a >> 8, b & 0xFF, b >> 8, c & 0xFF, c >> 8, a & 0xFF, a >> 8]
    return out


# ---- The notices on the title screen ------------------------------------------------

NOTICES = ["PORT BY PIGMASSACRE", "AI SLOP - DO NOT PLAY", "SELECT - OPTIONS"]
MENU_ITEMS = ["STAR RECALL", "SKIPPING STONES", "TAP TO SUMMON", "COYOTE TIME", "JUMP BUFFERING"]
MENU_MAP, MENU_LEFT = 0x7800, 5     # src/runtime.s has the first; the cursor's column
MENU_ROWS = [11, 13, 15, 17, 19]
TILE_ARROW = 94             # src/runtime.s has the same number
FONT_PAGE = 0x40            # the intro's letters: tile 1 is A
OVERLAY_HALF = 30           # where they go: src/boot.s has the same number, as $DE
TILE_BLANK, TILE_DASH, TILE_NONE = 0, 27, 127

# Clouds for parallax, on BG2: the game's own page of them, arranged as it does in stage 1
# and in stages 2 and 4. An entry is a tile of that page; S is sky, L and W its fill tiles.
TILE_CLOUDS, FILL_PAGE = 28, 0x00
PUFFS = {
    3: {5: (0x09, 0x06, 0x16, 0x07, 0x17, 0x08, 0x18)},
    6: {0: (0x02, 0x12, 0x04, 0x14), 30: (0x00, 0x10)},
    7: {0: (0x03, 0x13, 0x05, 0x15, 0x08, 0x18), 13: (0x09, 0x08, 0x18), 29: (0x09, 0x01, 0x11)},
    9: {9: (0x09, 0x06, 0x16, 0x07)},
    11: {21: (0x09, 0x06, 0x16, 0x07, 0x17)},
}
# The bank of cloud under them: the rows the title screen has, which meet at their ends, so it
# loops. Tiles from $40 are the clouds' page; L and W are its fill.
CLOUD_BANK = {
    15: {0: (0x0A, 0x1A, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B, 0x0A, 0x1A, 0x2B, 0x3B,
             0x0A, 0x1A, 0x0B, 0x1B, 0x0C, 0x1C, 0x0D, 0x1D, 0x0E, 0x1E, 0x0B, 0x1B, 0x0A, 0x1A, 0x0B, 0x1B)},
    16: {0: ("L",) * 11 + (0x38, 0x2A, 0x3A, "W", "W", 0x2C) + ("L",) * 15},
    17: {0: (0x24, 0x34, 0x25, 0x35) + ("L",) * 6 + (0x29,) + ("W",) * 6 + (0x3D,) + ("L",) * 14},
    18: {0: (0x20, 0x23, 0x23, 0x33, 0x20, 0x23, 0x22, 0x32, 0x20, 0x23) + ("W",) * 8 + (0x20, 0x23) * 7},
}
for _row in CLOUD_BANK.values():
    assert len(_row[0]) == 32


# The pages of stages with parallax, with their black solid and their sky see-through.
# Their sky and cloud fill tiles, where the page has them. Of the clouds' page, what BG3 draws
# instead: the rest of it is foreground, such as the shadows under platforms.
CLOUD_TILES = {v for table in (PUFFS, CLOUD_BANK) for parts in table.values() for seq in parts.values()
               for v in seq if not isinstance(v, str)}
PARALLAX_PAGES = {0x00: (0x10, 0x11, 0x01), 0x23: (0x10, 0x11, 0x01), 0x36: (0x01,), 0x34: (0x01,),
                  CLOUD_PAGE: CLOUD_TILES}
for _p in (0x02, 0x03, 0x10, 0x2C, 0x2D, 0x2E, 0x2F, 0x22, 0x1C, 0x1D, 0x1E, 0x1F, 0x37, 0x35, 0x38, 0x07):
    PARALLAX_PAGES[_p] = ()


def build_parallax_pages(chr_rom):
    alias = list(range(128))
    out = bytearray()
    for n, (page, sky) in enumerate(sorted(PARALLAX_PAGES.items())):
        alias[page] = 0x80 + n
        for t in range(64):
            c = chr_rom[page * 0x400 + t * 16:page * 0x400 + t * 16 + 16]
            if t in sky:
                out += bytes(32)
                continue
            rows, solid = bytearray(), bytearray()
            for y in range(8):
                rows += bytes([c[y], c[8 + y]])
                # Plane 3: colour 4, the black, where the NES has colour 0.
                solid += bytes([(~(c[y] | c[8 + y])) & 0xFF, 0])
            # Colour 0 becomes 4, which has only that plane set; 1-3 stay as they are.
            out += rows + solid
    return alias, bytes(out)


def build_overlay(chr_rom):
    """Tiles and maps for BG3: the notices, which show only on the title, then the clouds.
    8 KB, the first half for VRAM word $6800 and the rest for $7000."""
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
            return bytes([t, 0x01 | 0x04])      # palette 1

        for table in rows:
            for r, parts in table.items():
                for c, seq in parts.items():
                    for i, v in enumerate(seq):
                        out[r][(c + i) % 32] = cell(v)
        if fill_from is not None:
            for r in range(fill_from, 22):
                for c in range(32):
                    out[r][c] = cell("W")
        return b"".join(w for row in out for w in row)

    maps = cloud_map([PUFFS, CLOUD_BANK], 19) + cloud_map([PUFFS], None)
    arrow = bytearray(16)
    for y, v in enumerate((0x60, 0x70, 0x78, 0x7C, 0x78, 0x70, 0x60, 0x00)):
        arrow[y], arrow[8 + y] = v, v
    tiles[TILE_ARROW * 16:(TILE_ARROW + 1) * 16] = recolour(bytes(arrow))

    word = lambda t, front=True: bytes([t, 0x01 | 0x08 | (0x20 if front else 0)])  # tile 256 + t, palette 2
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
    menu = [[word(TILE_NONE, False)] * 32 for _ in range(32)]
    for r in range(7, 24):
        for c in range(3, 29):
            menu[r][c] = word(TILE_BLANK)

    def text(r, c, s):
        for i, ch in enumerate(s):
            t = TILE_BLANK if ch == " " else TILE_DASH if ch == "-" else ord(ch) - 64
            menu[r][c + i] = word(t)

    text(8, 12, "OPTIONS")
    for row, item in zip(MENU_ROWS, MENU_ITEMS):
        text(row, MENU_LEFT + 2, item)
        text(row, MENU_LEFT + 18, "OFF")
    text(22, 9, "SELECT - BACK")
    return bytes(tiles) + b"".join(w for row in screen for w in row) + maps + b"".join(w for row in menu for w in row)


def attr_table():
    out = []
    for a in range(256):
        v = a & 0xC0
        v |= 0 if a & 0x20 else 0x20    # in front of the background: priority 2
        v |= (a & 3) << 1
        out.append(v)
    return out


# For a look in an emulator with no way to press its buttons (TEST_AUTOPLAY=1): Start on a
# slow beat until play begins, then right. The game reads A, B, Select, Start, Up, Down,
# Left, Right. It takes the place of the read of the first pad.
AUTOPLAY_STUB = """
.export test_pad
test_bit: .byte 0
test_t: .byte 0
test_pad:
        lda test_bit
        inc test_bit
        and #7
        bne @not_first
        inc test_t
        lda #0
@not_first:
        cmp #3
        bne @other
        lda test_t
        and #$3F
        cmp #$04
        bcc @on
        bra @off
@other: cmp #7
        bne @off
        lda $90
        beq @off
@on:    lda #1
        rts
@off:   lda #0
        rts
"""


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
    prg15, hooks15, far15, seeds15, fixed15 = apply_15(prg)
    win15, ins15 = decode(prg15, seeds15)
    # What was the game's in the block 1.5 took over is gone: nothing reaches it any more.
    for pc in [pc for pc in instrs[FIXED] if fixed15[0] <= pc < fixed15[1]]:
        del instrs[FIXED][pc]
    instrs[HACK_BANK] = ins15[HACK_BANK]
    instrs[FIXED].update({pc: i for pc, i in ins15[FIXED].items() if fixed15[0] <= pc < fixed15[1]})
    windows[HACK_BANK] = 0xA000
    combos += [(0x1E, HACK_BANK, 3, 1), (0x1D, HACK_BANK, 3, 1)]
    stubs = Stubs()
    patches, bad = find_patches(instrs, stubs)
    patches[FIXED][PAD_READ] = "pad_read"
    patches[FIXED][SOUND_HOOK] = "sound_hook"
    if os.environ.get("TEST_AUTOPLAY"):
        patches[FIXED][0xF2D7] = "test_pad"
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
    colors = [(r * 31 + 127) // 255 | ((g * 31 + 127) // 255) << 5 | ((b * 31 + 127) // 255) << 10 for r, g, b in NES_RGB]
    s += bytes_asm("ColorLo", [c & 0xFF for c in colors])
    s += bytes_asm("ColorHi", [c >> 8 for c in colors])
    s += bytes_asm("AttrTable", attr_table())
    s += bytes_asm("M7Anim", mode7_frames())
    alias, alias_tiles = build_parallax_pages(chr_rom)
    s += bytes_asm("PageAlias", alias)
    s += bytes_asm("ChrObjBanks", [0xC0 + OBJ_HALF + p // 16 for p in range(128)]
                   + [0xC0 + ALIAS_HALF + p // 16 for p in range(128)])
    s += bytes_asm("ComboIdx8", idx[0])
    s += bytes_asm("ComboIdxA", idx[1])
    s += bytes_asm("ComboTable", [0x80 + FIRST_CODE_BANK + b for b in table])
    fixed = prg[FIXED * BANK:]
    first = pick_bank((0, 0), banks, None)
    s += bytes_asm("FirstBank", [0x80 + FIRST_CODE_BANK + first])
    for name, at in (("NesNmi", 0x1FFA), ("NesReset", 0x1FFC), ("NesIrq", 0x1FFE)):
        s += bytes_asm(name, [fixed[at], fixed[at + 1]])
    spc = build_spc(prg)
    for name, at in far15.items():
        s += ".export %s\n%s = $%04X\n" % (name, name, at)
    rows = [MENU_MAP + r * 32 + MENU_LEFT for r in MENU_ROWS]
    s += bytes_asm("MenuRowLo", [a & 0xFF for a in rows])
    s += bytes_asm("MenuRowHi", [a >> 8 for a in rows])
    s += bytes_asm("SpcAddr", [SPC_ORIGIN & 0xFF, SPC_ORIGIN >> 8])
    s += bytes_asm("SpcEntry", [SPC_CODE & 0xFF, SPC_CODE >> 8])
    s += bytes_asm("SpcSize", [len(spc) & 0xFF, len(spc) >> 8])
    autoplay = os.environ.get("TEST_AUTOPLAY")
    s += '.segment "WCODE"\n.import apu_regs, apu_kick, apu_indexed\n.p816\n.a8\n.i8\n.smart off\n'
    s += "\n".join(stubs.lines) + "\n"
    if autoplay:
        s += AUTOPLAY_STUB
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
    for num in range(33):
        data = bytearray(prg15[num * BANK:(num + 1) * BANK])
        for pc, label in patches.get(num, {}).items():
            w = windows[num]
            t = addr[label]
            if not 0x0800 <= t < 0x2000:
                sys.exit("stub %s at $%04X" % (label, t))
            data[pc - w:pc - w + 3] = bytes([0x20, t & 0xFF, t >> 8])
        for (bank, pc), (label, code) in hooks15.items():
            if bank == num:
                t = addr[label]
                at = pc - windows[num]
                data[at:at + len(code)] = bytes([0x20, t & 0xFF, t >> 8]) + code[3:]
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
    for n in range(len(alias_tiles) // 0x800):
        at = (ALIAS_HALF + n // 16) * 0x10000 + (n % 16) * 0x800
        image[at:at + 0x800] = alias_tiles[n * 0x800:(n + 1) * 0x800]
    m7 = build_mode7(chr_rom)
    image[MODE7_HALF * 0x10000:MODE7_HALF * 0x10000 + len(m7)] = m7
    overlay = build_overlay(chr_rom)
    image[OVERLAY_HALF * 0x10000:OVERLAY_HALF * 0x10000 + len(overlay)] = overlay
    for num in range(32):
        at = (PRG_HALF + num // 4) * 0x10000 + (num % 4) * BANK
        image[at:at + BANK] = prg[num * BANK:(num + 1) * BANK]
    obj = convert_chr(chr_rom)
    for p in range(128):
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
