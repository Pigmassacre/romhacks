package build

import (
	"bytes"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"

	_ "embed"
)

const (
	headerLen = 16
	bank      = 0x2000
	smbPRGLen = 0x40000
	hackPRG   = 0x80000
	chrLen    = 0x20000
	outLen    = headerLen + hackPRG + chrLen
)

//go:embed patch.bin
var patchBin []byte

const (
	smb3SHA256    = "6ea0777ca520ba7ad7b0ea0f6452140d59aa0b1dffe5045cb1e8020dde10c267"
	gimmickSHA256 = "1b1e40c9b0096a5bcbeea178fa0904fa7debb3c11ece41cdcb417173d38c368d"
	mrGimmickSHA  = "7371801fd9dd3888cfea99faa0920aa9863998df"
	smb3RevASHA   = "6bd518e85eb46a4252af07910f61036e84b020d1"
)

const (
	msgNotNES       = "This doesn't look like an NES game. Choose the .nes file for the game."
	msgMrGimmick    = "This is Mr. Gimmick, the version released outside Japan. Please choose the Japanese game, Gimmick!."
	msgSMB3Rev      = "This is a later edition of Super Mario Bros. 3. Please choose the original US release."
	msgWrongSMB3    = "Please choose the original US release of Super Mario Bros. 3."
	msgWrongGim     = "Please choose the Japanese game Gimmick!."
	msgUnrecognized = "This isn't Super Mario Bros. 3 or Gimmick!. Add the original US Super Mario Bros. 3, or the Japanese Gimmick!."
)

type Game struct {
	OK      bool   `json:"ok"`
	Role    string `json:"role,omitempty"`
	Title   string `json:"title,omitempty"`
	Message string `json:"message,omitempty"`
}

func Normalize(b []byte) []byte {
	if len(b) >= 4 && bytes.Equal(b[:4], []byte("NES\x1a")) {
		return b
	}
	if len(b) >= 512+4 && bytes.Equal(b[512:516], []byte("NES\x1a")) {
		return b[512:]
	}
	return b
}

func Recognize(b []byte) Game {
	b = Normalize(b)
	if len(b) < headerLen || !bytes.Equal(b[:4], []byte("NES\x1a")) {
		return Game{Message: msgNotNES}
	}
	sum := sha256.Sum256(b)
	switch hex.EncodeToString(sum[:]) {
	case smb3SHA256:
		return Game{OK: true, Role: "smb3", Title: "Super Mario Bros. 3"}
	case gimmickSHA256:
		return Game{OK: true, Role: "gimmick", Title: "Gimmick!"}
	}
	sha := sha1.Sum(b)
	id := hex.EncodeToString(sha[:])
	switch id {
	case mrGimmickSHA:
		return Game{Message: msgMrGimmick}
	case smb3RevASHA:
		return Game{Message: msgSMB3Rev}
	}
	return Game{Message: msgUnrecognized}
}

func expect(b []byte, role, fallback string) error {
	g := Recognize(b)
	if g.Role == role {
		return nil
	}
	if g.Message != "" && g.Message != msgUnrecognized {
		return errors.New(g.Message)
	}
	return errors.New(fallback)
}

func Build(smb, gim []byte) ([]byte, error) {
	smb = Normalize(smb)
	gim = Normalize(gim)
	if err := expect(smb, "smb3", msgWrongSMB3); err != nil {
		return nil, err
	}
	if err := expect(gim, "gimmick", msgWrongGim); err != nil {
		return nil, err
	}

	out := make([]byte, outLen)
	copy(out, smb[:headerLen])
	out[4] = 0x20

	smbPRG := smb[headerLen : headerLen+smbPRGLen]
	prg := out[headerLen : headerLen+hackPRG]
	for i := 0; i < 30; i++ {
		copy(prg[i*bank:(i+1)*bank], smbPRG[i*bank:(i+1)*bank])
	}
	for i := 30 * bank; i < 62*bank; i++ {
		prg[i] = 0xFF
	}
	copy(prg[62*bank:], smbPRG[30*bank:32*bank])

	chr := out[headerLen+hackPRG:]
	copy(chr, smb[headerLen+smbPRGLen:headerLen+smbPRGLen+chrLen])
	gchr := gim[headerLen+smbPRGLen : headerLen+smbPRGLen+chrLen]
	applyGraphics(chr, gchr)

	if err := applyPatch(prg, smbPRG, gim); err != nil {
		return nil, err
	}
	return out, nil
}

func applyPatch(prg, smbPRG, gim []byte) error {
	if len(patchBin) < 9 || string(patchBin[:4]) != "S3GP" || patchBin[4] != 1 {
		return fmt.Errorf("the builder's data is damaged")
	}
	n := binary.LittleEndian.Uint32(patchBin[5:9])
	p := 9
	for i := uint32(0); i < n; i++ {
		if p >= len(patchBin) {
			return fmt.Errorf("the builder's data is damaged")
		}
		kind := patchBin[p]
		p++
		switch kind {
		case 1, 3:
			if p+12 > len(patchBin) {
				return fmt.Errorf("the builder's data is damaged")
			}
			dest := int(binary.LittleEndian.Uint32(patchBin[p:]))
			src := int(binary.LittleEndian.Uint32(patchBin[p+4:]))
			ln := int(binary.LittleEndian.Uint32(patchBin[p+8:]))
			p += 12
			from := smbPRG
			if kind == 3 {
				from = gim
			}
			if dest < 0 || src < 0 || ln < 0 || dest+ln > len(prg) || src+ln > len(from) {
				return fmt.Errorf("the builder's data is damaged")
			}
			copy(prg[dest:dest+ln], from[src:src+ln])
		case 2:
			if p+8 > len(patchBin) {
				return fmt.Errorf("the builder's data is damaged")
			}
			dest := int(binary.LittleEndian.Uint32(patchBin[p:]))
			ln := int(binary.LittleEndian.Uint32(patchBin[p+4:]))
			p += 8
			if p+ln > len(patchBin) || dest+ln > len(prg) {
				return fmt.Errorf("the builder's data is damaged")
			}
			copy(prg[dest:dest+ln], patchBin[p:p+ln])
			p += ln
		default:
			return fmt.Errorf("the builder's data is damaged")
		}
	}
	return nil
}
