package build

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

const hackSHA256 = "dafffb2e78b26d7dcb316e3223aaa6d631af0b6b78caf1de2a31a4a9724980bf"

func TestPatchHeader(t *testing.T) {
	if string(patchBin[:4]) != "S3GP" || patchBin[4] != 1 {
		t.Fatal("patch.bin is missing or damaged")
	}
}

func TestBuild(t *testing.T) {
	root := repoRoot(t)
	smb, err := os.ReadFile(filepath.Join(root, "Super Mario Bros III.nes"))
	if err != nil {
		t.Skip("SMB3 ROM is not on this machine")
	}
	gim, err := os.ReadFile(filepath.Join(root, "Gimmick! (Japan).nes"))
	if err != nil {
		t.Skip("Gimmick ROM is not on this machine")
	}
	got, err := Build(smb, gim)
	if err != nil {
		t.Fatal(err)
	}
	sum := sha256.Sum256(got)
	if hex.EncodeToString(sum[:]) != hackSHA256 {
		t.Fatalf("built game hash %x", sum)
	}
	want, err := os.ReadFile(filepath.Join(root, "out", "smb3-gimmick.nes"))
	if err == nil && !bytes.Equal(got, want) {
		t.Fatal("built game does not match out/smb3-gimmick.nes")
	}

	padded := append(bytes.Repeat([]byte{0}, 512), smb...)
	if Recognize(padded).Role != "smb3" {
		t.Fatal("a file with a leading header was not recognized")
	}
	if _, err := Build(padded, gim); err != nil {
		t.Fatal(err)
	}

	// The same games with NES 2.0 headers must be recognized and build the same hack.
	smb2 := append([]byte(nil), smb...)
	gim2 := append([]byte(nil), gim...)
	for _, b := range [][]byte{smb2, gim2} {
		b[7] |= 0x08
		b[15] = 0x01
	}
	if Recognize(smb2).Role != "smb3" || Recognize(gim2).Role != "gimmick" {
		t.Fatal("a game with an NES 2.0 header was not recognized")
	}
	got2, err := Build(smb2, gim2)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, got2) {
		t.Fatal("the header of the input games changed the built game")
	}
}

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("no caller")
	}
	return filepath.Dir(filepath.Dir(filepath.Dir(file)))
}
