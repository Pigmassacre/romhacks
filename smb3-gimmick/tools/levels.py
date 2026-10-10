import os
import re

ROOT = os.path.join(os.path.dirname(__file__), '..')
MAPS = os.path.join(ROOT, 'src', 'PRG', 'maps')


def parse_list(text, name):
    out = []
    for sfx in ('', '_S2', '_S3', '_S4'):
        m = re.search(r'^%s%s:\s*(?:\.(?:byte|word)\s+(.*))?$' % (name, sfx), text, re.M)
        if m and m.group(1):
            out += [s.strip() for s in m.group(1).split(',')]
    return out


def main():
    fns = {}
    for line in open(os.path.join(ROOT, 'out', 'smb3.fns')):
        m = re.match(r'^(\S+)\s+=\s+\$(\w+)', line)
        if m:
            fns[m.group(1)] = int(m.group(2), 16)

    def val(s):
        return int(s[1:], 16) if s.startswith('$') else fns[s]

    lines = []
    for w in range(1, 9):
        text = open(os.path.join(MAPS, 'World%dS.asm' % w)).read()
        rows = parse_list(text, 'W%d_ByRowType' % w)
        objs = parse_list(text, 'W%d_ObjSets' % w)
        lays = parse_list(text, 'W%d_LevelLayout' % w)
        seen = set()
        for r, o, l in zip(rows, objs, lays):
            if l in seen or l.startswith('$'):
                continue
            seen.add(l)
            lines.append('%s %d %d %d %d' % (l, w - 1, int(r[1:], 16) & 0x0F, val(l), val(o)))
    with open(os.path.join(ROOT, 'out', 'levels.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')


main()
