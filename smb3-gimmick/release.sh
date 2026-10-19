#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Usage: ./release.sh v1.2.3"
	echo "Checks the repository, tags smb3-gimmick-v1.2.3, and lets GitHub build and publish the release."
	exit 1
fi
# The romhacks repository holds more than one project, so tags name theirs.
tag="smb3-gimmick-${version}"

if ! command -v go >/dev/null 2>&1; then
	echo "Go is not installed. Install it from https://go.dev/dl/ and run this again."
	exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
	echo "The GitHub CLI is not installed. Install it from https://cli.github.com/ and run this again."
	exit 1
fi

if [[ ! -f "Super Mario Bros III.nes" ]]; then
	echo "Put the US Super Mario Bros. 3 ROM here as 'Super Mario Bros III.nes'. It is needed to check the graphics in src/CHR."
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

go vet ./...
go test ./...

remote="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
local="$(git rev-parse HEAD)"
if [[ -n "$remote" && "$remote" != "$local" ]]; then
	echo "GitHub's main branch does not match this one."
	echo "If GitHub still has older commits, replacing main removes them:"
	echo "  git push --force-with-lease=refs/heads/main:${remote} origin main"
	echo "Run ./release.sh again after that."
	exit 1
fi

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null || [[ -n "$(git ls-remote origin "refs/tags/${tag}")" ]]; then
	echo "${tag} is already tagged. Pick a new version."
	exit 1
fi

git tag "$tag"
git push origin "$tag"

echo "GitHub is building ${tag} for Windows, Mac, and Linux."
sleep 10
run="$(gh run list --workflow smb3-gimmick-release.yml --branch "$tag" --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run" --exit-status
echo "Published ${tag}"
