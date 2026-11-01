#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Usage: ./release.sh v1.2.3"
	echo "Checks the repository, builds the patch, and publishes it as the release smb3-gimmick-v1.2.3."
	exit 1
fi
# The romhacks repository holds more than one project, so tags name theirs.
tag="smb3-gimmick-${version}"

if ! command -v gh >/dev/null 2>&1; then
	echo "The GitHub CLI is not installed. Install it from https://cli.github.com/ and run this again."
	exit 1
fi
for rom in "Super Mario Bros III.nes" "Gimmick! (Japan).nes"; do
	if [[ ! -f "$rom" ]]; then
		echo "Put your copy of the game here as '$rom'. The build needs it."
		exit 1
	fi
done
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
	echo "Commit your changes first: the patch has to match the tagged commit."
	exit 1
fi

python3 - << 'PY'
import re, subprocess, sys
smb = open("Super Mario Bros III.nes", "rb").read()
stock = smb[16 + 0x40000:16 + 0x40000 + 0x20000]
# Paths are checked across the whole romhacks repository, from its top.
top = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
chr_page = re.compile(r"^smb3-gimmick/src/CHR/chr(\d{3})\.bin$")

def allowed(path):
    if path.endswith(".nes") or path.rsplit("/", 1)[-1] == "Mesen":
        return False
    if path.endswith(".bin"):
        # patch.bin was the old builder program's data; it is in the history only
        return path == "smb3-gimmick/internal/build/patch.bin" or chr_page.match(path) is not None
    return True

def stock_page(path, blob):
    i = int(chr_page.match(path).group(1))
    data = subprocess.check_output(["git", "cat-file", "blob", blob], cwd=top)
    return data == stock[i * 1024:(i + 1) * 1024]

bad = [n for n in subprocess.check_output(["git", "ls-files"], text=True, cwd=top).splitlines() if not allowed(n)]
if bad:
    print("These tracked files can't be published:")
    print("\n".join(bad))
    sys.exit(1)
for line in subprocess.check_output(["git", "rev-list", "--all", "--objects"], text=True, cwd=top).splitlines():
    parts = line.split(" ", 1)
    if len(parts) < 2:
        continue
    blob, path = parts
    if not allowed(path):
        print("Git history still contains", path)
        sys.exit(1)
    if chr_page.match(path) and not stock_page(path, blob):
        print("Git history contains modified graphics in", path, "(only stock SMB3 pages may be tracked)")
        sys.exit(1)
PY

./build.sh

remote="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
local="$(git rev-parse HEAD)"
if [[ -n "$remote" && "$remote" != "$local" ]]; then
	echo "GitHub's main branch does not match this one. Push (or pull) first, then run this again."
	exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null || [[ -n "$(git ls-remote origin "refs/tags/${tag}")" ]]; then
	echo "${tag} is already tagged. Pick a new version."
	exit 1
fi

notes="$(mktemp)"
{
	../release-notes.sh smb3-gimmick
	cat << 'EOF'
Yumetaro, from Sunsoft's *Gimmick!*, in the worlds of *Super Mario Bros. 3*.

You need your own copy of Super Mario Bros. 3, the original US release (not Revision A). Apply `smb3-gimmick.bps` to it with [Flips](https://github.com/Alcaro/Flips) or [Rom Patcher JS](https://www.marcrobledo.com/RomPatcher.js/).

| Your ROM's CRC32 | Patch |
|---|---|
| `85A79D9C` (`A0B0B742` without its 16-byte header) | `smb3-gimmick.bps` |

The result is a 640 KB ROM on the MMC3 mapper (mapper 4). It has been tested in Mesen.
EOF
} > "$notes"

git tag "$tag"
git push origin "$tag"
gh release create "$tag" out/smb3-gimmick.bps --title "SMB3 Gimmick ${version}" --notes-file "$notes"
rm -f "$notes"
echo "Published ${tag}"
