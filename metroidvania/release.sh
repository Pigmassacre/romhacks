#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Usage: ./release.sh v1.2.3"
	echo "Checks the repository, builds the patch, and publishes it as the release metroidvania-v1.2.3."
	exit 1
fi
# The romhacks repository holds more than one project, so tags name theirs.
tag="metroidvania-${version}"

if ! command -v gh >/dev/null 2>&1; then
	echo "The GitHub CLI is not installed. Install it from https://cli.github.com/ and run this again."
	exit 1
fi
for rom in "Castlevania I.nes" "Metroid.nes"; do
	if [[ ! -f "$rom" ]]; then
		echo "Put your copy of the game here as '$rom'. The build needs it."
		exit 1
	fi
done
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
	echo "Commit your changes first: the patch has to match the tagged commit."
	exit 1
fi

# No ROMs, emulators or converted graphics anywhere in the repository's history.
python3 - << 'PY'
import subprocess, sys
top = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()

def allowed(path):
    name = path.rsplit("/", 1)[-1]
    if path.endswith(".nes") or name == "Mesen":
        return False
    if path.startswith("metroidvania/") and (path.endswith(".bin") or path.endswith(".chr") or path.endswith(".mss")):
        return False
    return True

bad = [n for n in subprocess.check_output(["git", "ls-files"], text=True, cwd=top).splitlines() if not allowed(n)]
if bad:
    print("These tracked files can't be published:")
    print("\n".join(bad))
    sys.exit(1)
for line in subprocess.check_output(["git", "rev-list", "--all", "--objects"], text=True, cwd=top).splitlines():
    parts = line.split(" ", 1)
    if len(parts) == 2 and not allowed(parts[1]):
        print("Git history still contains", parts[1])
        sys.exit(1)
PY

python3 tools/build.py

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
cat > "$notes" << 'NOTES'
Samus, from Nintendo's *Metroid*, in Konami's *Castlevania*: Metroid's movement, beams, missiles, morph ball, HUD and sounds, in Castlevania's stages.

You need your own copy of Castlevania, the original US release. Apply `metroidvania.bps` to it with [Flips](https://github.com/Alcaro/Flips) or [Rom Patcher JS](https://www.marcrobledo.com/RomPatcher.js/).

| Your ROM's CRC32 | Patch |
|---|---|
| `856114C8` (`B668C7FC` without its 16-byte header) | `metroidvania.bps` |

The result is a 256 KB ROM on mapper 2 (UOROM) with CHR RAM. It has been tested in Mesen.
NOTES

git tag "$tag"
git push origin "$tag"
gh release create "$tag" out/metroidvania.bps --title "Metroidvania ${version}" --notes-file "$notes"
rm -f "$notes"
echo "Published ${tag}"
