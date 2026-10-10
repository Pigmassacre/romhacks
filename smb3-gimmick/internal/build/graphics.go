package build

func applyGraphics(chr, gchr []byte) {
	copy(chr[0x50*1024:], spritePage(gchr, 0x0C))
	copy(chr[0x51*1024:], spritePage(gchr, 0x0D))

	type stamp struct {
		page, tile int
		data       []byte
	}
	for _, s := range []stamp{
		{0x20, 0x2C, pair(gchr, 0x0C, 0x04)},
		{0x20, 0x2E, pair(gchr, 0x0C, 0x14)},
		{0x20, 0x0C, pair(gchr, 0x0C, 0x0A)},
		{0x20, 0x0E, pair(gchr, 0x0C, 0x1A)},
		{0x20, 0x3C, mirrorBytes(pair(gchr, 0x0C, 0x14))},
		{0x20, 0x3E, mirrorBytes(pair(gchr, 0x0C, 0x04))},
		{0x21, 0x08, color3to2(pair(gchr, 0x0C, 0x02))},
	} {
		copy(chr[s.page*1024+s.tile*16:], s.data)
	}

	applyLogo(chr, gchr)
}

func spritePage(gchr []byte, srcPage int) []byte {
	data := append([]byte(nil), gchr[srcPage*1024:(srcPage+1)*1024]...)
	extra := [][3]int{{0x28, 0x08, 0x00}, {0x2A, 0x08, 0x10}, {0x2C, 0x0C, 0x2E}, {0x38, 0x0C, 0x3E}}
	for _, e := range extra {
		copy(data[e[0]*16:], pair(gchr, e[1], e[2]))
	}
	return data
}

func pair(gchr []byte, page, tile int) []byte {
	o := page*1024 + tile*16
	return append([]byte(nil), gchr[o:o+32]...)
}

func mirrorBytes(data []byte) []byte {
	out := make([]byte, len(data))
	for i, b := range data {
		var r byte
		for bit := 0; bit < 8; bit++ {
			if b&(1<<uint(bit)) != 0 {
				r |= 1 << uint(7-bit)
			}
		}
		out[i] = r
	}
	return out
}

func color3to2(data []byte) []byte {
	out := append([]byte(nil), data...)
	for t := 0; t < len(out); t += 16 {
		for y := 0; y < 8; y++ {
			out[t+y] &^= out[t+8+y]
		}
	}
	return out
}

func tilePixels(chr []byte, offset int) [8][8]byte {
	var rows [8][8]byte
	for y := 0; y < 8; y++ {
		lo := chr[offset+y]
		hi := chr[offset+y+8]
		for x := 0; x < 8; x++ {
			rows[y][x] = ((lo >> uint(7-x)) & 1) | (((hi >> uint(7-x)) & 1) << 1)
		}
	}
	return rows
}

func encodeTile(pix [8][8]byte) [16]byte {
	var out [16]byte
	for y := 0; y < 8; y++ {
		var lo, hi byte
		for x := 0; x < 8; x++ {
			v := pix[y][x]
			lo |= (v & 1) << uint(7-x)
			hi |= ((v >> 1) & 1) << uint(7-x)
		}
		out[y] = lo
		out[y+8] = hi
	}
	return out
}

var gimPages = []int{0, 101, 102, 103}

var mapBody = [4]byte{1, 2, 2, 3}
var mapBottom = [4]byte{1, 1, 1, 3}

var logoRows = []string{
	"01 01 92 a2 b2 01 40 50 60 70 43 53 63 73 46 56 66 c0 d0 e0 eb c8 d8 01",
	"01 01 93 a3 b3 01 41 51 61 71 44 54 64 74 47 57 67 c1 d1 e1 f1 c9 d9 01",
	"01 84 94 a4 b3 88 42 52 62 72 45 55 65 75 6e 01 01 01 d2 01 f2 ca da 01",
	"01 85 95 a5 b5 89 82 9a 01 ad bd ba a0 b0 aa c2 e2 c3 d3 fa 01 cb db 01",
	"01 86 96 a6 b6 8a a1 9b ab ae be bb a1 b1 b4 80 e3 c4 d4 e4 f4 cc dc 01",
	"01 87 97 a7 b7 8b a1 9c ac af bf bc a1 81 91 90 01 c5 d5 e5 01 cd dd 01",
	"01 01 98 a8 b8 8c a1 9d 01 ef bf bc a1 81 8e 9e ea c6 d6 e6 f6 ce de 01",
	"01 01 99 a9 b9 8d 83 fb 01 ec fc ed fd ee fe 9f f0 c7 d7 e7 f7 cf df 01",
	"01 e8 f3 f3 48 f3 f3 f3 f3 58 f3 f3 f3 f3 68 f3 f3 f3 f3 78 f3 f3 f8 01",
	"ff f5 f5 f5 49 f5 f5 f5 f5 59 f5 f5 f5 f5 69 f5 f5 f5 f5 79 f5 f5 f5 ff",
}

func freeSlots() []int {
	var s []int
	add := func(from, to int) {
		for i := from; i < to; i++ {
			s = append(s, i)
		}
	}
	add(0x30, 0x3F)
	add(0x40, 0x4F)
	add(0x50, 0x5B)
	s = append(s, 0x5B)
	add(0x60, 0x6B)
	s = append(s, 0x6B)
	add(0x70, 0x7C)
	add(0x7D, 0xC9)
	add(0xD0, 0xD9)
	add(0xE0, 0xE6)
	s = append(s, 0xE8)
	add(0xF0, 0xF6)
	return s
}

func applyLogo(chr, gchr []byte) {
	data := append([]byte(nil), chr[120*1024:124*1024]...)
	free := freeSlots()
	fi := 0
	slots := map[string]int{}
	for r, line := range logoRows {
		cmap := mapBody
		if r == len(logoRows)-1 {
			cmap = mapBottom
		}
		for _, hexb := range splitFields(line) {
			t := parseHex(hexb)
			pix := tilePixels(gchr, gimPages[t>>6]*1024+(t&0x3F)*16)
			for y := 0; y < 8; y++ {
				for x := 0; x < 8; x++ {
					pix[y][x] = cmap[pix[y][x]]
				}
			}
			enc := encodeTile(pix)
			key := string(enc[:])
			if _, ok := slots[key]; !ok {
				slots[key] = free[fi]
				fi++
				copy(data[slots[key]*16:], enc[:])
			}
		}
	}
	copy(chr[120*1024:], data)
}

func splitFields(s string) []string {
	var out []string
	start := -1
	for i := 0; i <= len(s); i++ {
		if i == len(s) || s[i] == ' ' {
			if start >= 0 {
				out = append(out, s[start:i])
				start = -1
			}
			continue
		}
		if start < 0 {
			start = i
		}
	}
	return out
}

func parseHex(s string) int {
	n := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		n *= 16
		switch {
		case c >= '0' && c <= '9':
			n += int(c - '0')
		case c >= 'a' && c <= 'f':
			n += int(c-'a') + 10
		case c >= 'A' && c <= 'F':
			n += int(c-'A') + 10
		}
	}
	return n
}
