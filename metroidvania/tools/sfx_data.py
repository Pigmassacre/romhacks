#!/usr/bin/env python3
"""Convert Metroid's recorded sound effects (out/lua/sfx.txt, from
tools/record_sfx.lua) into src/sfxdata.asm, for src/sfx.asm to play.

Each effect is the APU writes Metroid's sound engine made for it, frame by
frame. The last frame also holds the music taking the channel back, so it
ends where a register is written a second time.

Stream bytes:
  $00-$13  write the next byte to $4000 + this
  $80-$BF  end of this frame, then (this - $80) frames with no writes
  $FF      end of the effect (after this frame's writes)
"""
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse(path):
    sfx, cur = [], None
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("sfx "):
            cur = (line[4:], [])
            sfx.append(cur)
        elif line == "end":
            cur = None
        elif cur is not None:
            cur[1].append([(int(r, 16), int(v, 16)) for r, v in (w.split("=") for w in line.split())])
    return sfx


def encode(frames):
    last = frames[-1]
    seen, keep = set(), []
    for r, v in last:
        if r in seen:
            break
        seen.add(r)
        keep.append((r, v))
    frames = frames[:-1] + [keep]
    out = []
    i = 0
    while i < len(frames):
        for r, v in frames[i]:
            out += [r, v]
        if i == len(frames) - 1:
            out.append(0xFF)
            break
        n = 0
        while i + 1 + n < len(frames) - 1 and not frames[i + 1 + n] and n < 0x3F:
            n += 1
        out.append(0x80 + n)
        i += 1 + n
    return out


def main():
    sfx = parse(os.path.join(REPO, "out", "lua", "sfx.txt"))
    with open(os.path.join(REPO, "src", "sfxdata.asm"), "w") as f:
        f.write("; Metroid's sound effects as APU writes, recorded from Metroid's sound engine\n")
        f.write("; in Mesen (tools/record_sfx.lua) and converted by tools/sfx_data.py.\n")
        f.write("; Do not edit. See tools/sfx_data.py for the format.\n\n")
        for name, frames in sfx:
            data = encode(frames)
            f.write("Sfx%s:  ; %d frames\n" % (name, len(frames)))
            for k in range(0, len(data), 16):
                f.write("        .db " + ",".join("$%02X" % b for b in data[k:k + 16]) + "\n")
    print("%d effects" % len(sfx))


if __name__ == "__main__":
    main()
