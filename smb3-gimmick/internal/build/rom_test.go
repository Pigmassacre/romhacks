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

const hackSHA256 = "897527e0caf8b26e43f293c2c62af0ec0cf660d1c5baeb84131eaae0a44efe8b"

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
}

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("no caller")
	}
	return filepath.Dir(filepath.Dir(filepath.Dir(file)))
}
