#!/usr/bin/env python3
"""Make the BPS patch: Super Mario Bros. 3 -> out/smb3-gimmick.nes.

    python3 tools/patch.py      # run by build.sh; writes out/smb3-gimmick.bps

The patch copies everything it can from the player's own ROM: any run of 8 or
more bytes that is somewhere in Super Mario Bros. 3 is copied from there, so
the patch holds only what is new: Yumetaro's code, and the graphics and title
logo that the build takes from Gimmick!.
"""
import os
import sys
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SMB = os.path.join(ROOT, "Super Mario Bros III.nes")
HACK = os.path.join(ROOT, "out", "smb3-gimmick.nes")
OUT = os.path.join(ROOT, "out", "smb3-gimmick.bps")

K = 8          # shortest copy worth looking up
MAX_CANDIDATES = 64


def num(n):
    out = bytearray()
    while True:
        x = n & 0x7F
        n >>= 7
        if n == 0:
            out.append(0x80 | x)
            return out
        out.append(x)
        n -= 1


def same(a, ai, b, bi, limit):
    """How many bytes a[ai:] and b[bi:] have in common, up to limit."""
    n = 0
    step = 4096
    while n < limit:
        s = min(step, limit - n)
        if a[ai + n:ai + n + s] == b[bi + n:bi + n + s]:
            n += s
            continue
        if step == 1:
            break
        step = max(1, step // 16)
    return n


def encode(src, tgt):
    idx = {}
    for i in range(len(src) - K + 1):
        lst = idx.setdefault(src[i:i + K], [])
        if len(lst) < MAX_CANDIDATES:
            lst.append(i)

    body = bytearray(b"BPS1") + num(len(src)) + num(len(tgt)) + num(0)
    lit = bytearray()
    src_rel = tgt_rel = 0

    def flush():
        nonlocal lit
        if lit:
            body.extend(num(((len(lit) - 1) << 2) | 1))
            body.extend(lit)
            lit = bytearray()

    t = 0
    while t < len(tgt):
        left = len(tgt) - t
        # same place in the source
        best, kind, at = 0, None, 0
        if t < len(src):
            n = same(tgt, t, src, t, min(left, len(src) - t))
            if n >= 4:
                best, kind = n, "read"
        # anywhere else in the source
        if left >= K:
            for s in idx.get(tgt[t:t + K], ()):
                n = same(tgt, t, src, s, min(left, len(src) - s))
                if n > best + 2 or (n > best and s == src_rel):
                    best, kind, at = n, "copy", s
        # a run of one byte
        r = same(tgt, t + 1, tgt, t, left - 1) + 1
        if r >= 8 and r > best:
            best, kind = r, "run"
        if kind is None or (kind == "copy" and best < K):
            lit.append(tgt[t])
            t += 1
            continue
        flush()
        if kind == "read":
            body.extend(num(((best - 1) << 2) | 0))
        elif kind == "copy":
            body.extend(num(((best - 1) << 2) | 2))
            d = at - src_rel
            body.extend(num((abs(d) << 1) | (d < 0)))
            src_rel = at + best
        else:
            lit.append(tgt[t])
            flush()
            body.extend(num(((best - 2) << 2) | 3))
            d = t - tgt_rel
            body.extend(num((abs(d) << 1) | (d < 0)))
            tgt_rel = t + best - 1
        t += best
    flush()
    body += zlib.crc32(src).to_bytes(4, "little") + zlib.crc32(tgt).to_bytes(4, "little")
    body += zlib.crc32(body).to_bytes(4, "little")
    return bytes(body)


def apply(src, patch):
    """Apply a BPS patch, checking all three checksums."""
    pos = 4

    def rd():
        nonlocal pos
        data, shift = 0, 1
        while True:
            x = patch[pos]
            pos += 1
            data += (x & 0x7F) * shift
            if x & 0x80:
                return data
            shift <<= 7
            data += shift

    if patch[:4] != b"BPS1" or zlib.crc32(patch[:-4]) != int.from_bytes(patch[-4:], "little"):
        raise ValueError("not a valid BPS patch")
    if zlib.crc32(src) != int.from_bytes(patch[-12:-8], "little"):
        raise ValueError("wrong source ROM")
    rd()
    size = rd()
    meta = rd()             # not `pos += rd()`: that adds to pos as it was before rd() moved it
    pos += meta
    out = bytearray()
    src_rel = tgt_rel = 0
    while pos < len(patch) - 12:
        d = rd()
        cmd, n = d & 3, (d >> 2) + 1
        if cmd == 0:
            out += src[len(out):len(out) + n]
        elif cmd == 1:
            out += patch[pos:pos + n]
            pos += n
        else:
            o = rd()
            o = -(o >> 1) if o & 1 else o >> 1
            if cmd == 2:
                src_rel += o
                out += src[src_rel:src_rel + n]
                src_rel += n
            else:
                tgt_rel += o
                for _ in range(n):
                    out.append(out[tgt_rel])
                    tgt_rel += 1
    if len(out) != size or zlib.crc32(out) != int.from_bytes(patch[-8:-4], "little"):
        raise ValueError("the patch does not produce the right ROM")
    return bytes(out)


def literal_bytes(patch):
    """Bytes the patch stores itself rather than copying."""
    pos, total = 4, 0

    def rd():
        nonlocal pos
        data, shift = 0, 1
        while True:
            x = patch[pos]
            pos += 1
            data += (x & 0x7F) * shift
            if x & 0x80:
                return data
            shift <<= 7
            data += shift

    rd(), rd()
    meta = rd()
    pos += meta
    while pos < len(patch) - 12:
        d = rd()
        cmd, n = d & 3, (d >> 2) + 1
        if cmd == 1:
            total += n
            pos += n
        elif cmd >= 2:
            rd()
    return total


def main():
    for path in (SMB, HACK):
        if not os.path.exists(path):
            sys.exit("missing %s" % os.path.relpath(path, ROOT))
    src = open(SMB, "rb").read()
    tgt = open(HACK, "rb").read()
    patch = encode(src, tgt)
    if apply(src, patch) != tgt:
        sys.exit("the patch does not reproduce the ROM")
    open(OUT, "wb").write(patch)
    print("wrote out/smb3-gimmick.bps (%d bytes, %d of them new data; for a ROM with CRC32 %08X)"
          % (len(patch), literal_bytes(patch), zlib.crc32(src)))


if __name__ == "__main__":
    main()
