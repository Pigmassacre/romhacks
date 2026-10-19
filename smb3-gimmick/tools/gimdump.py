import sys

ROM = "/home/olof/dev/romhacks/smb3-gimmick/Gimmick! (Japan).nes"
data = open(ROM, "rb").read()


def off(bank, addr):
    return 0x10 + bank * 0x2000 + (addr & 0x1FFF)


def rd(bank, addr, n):
    o = off(bank, addr)
    return data[o:o + n]


if __name__ == "__main__":
    bank = int(sys.argv[1], 16)
    addr = int(sys.argv[2], 16)
    n = int(sys.argv[3], 16) if len(sys.argv) > 3 else 16
    b = rd(bank, addr, n)
    for i in range(0, n, 16):
        print("%02X:%04X  %s" % (bank, addr + i, " ".join("%02X" % x for x in b[i:i + 16])))
