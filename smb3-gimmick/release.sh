#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

version="${1:-}"
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "Usage: ./release.sh v1.2.3"
	echo "Builds SMB3 Gimmick for Windows, Mac, and Linux, then publishes a GitHub release."
	exit 1
fi

if ! command -v go >/dev/null 2>&1; then
	echo "Go is not installed. Install it from https://go.dev/dl/ and run this again."
	exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
	echo "The GitHub CLI is not installed. Install it from https://cli.github.com/ and run this again."
	exit 1
fi

python3 - << 'PY'
import subprocess, sys
names = subprocess.check_output(["git", "ls-files"], text=True).splitlines()
bad = []
for n in names:
    if n.startswith("src/") or n.endswith(".nes") or n == "Mesen":
        bad.append(n)
    if n.endswith(".bin") and n != "internal/build/patch.bin":
        bad.append(n)
if bad:
    print("These tracked files can't be published:")
    print("\n".join(bad))
    sys.exit(1)
log = subprocess.check_output(["git", "rev-list", "--all", "--objects"], text=True)
for line in log.splitlines():
    parts = line.split(" ", 1)
    if len(parts) < 2:
        continue
    path = parts[1]
    if path.startswith("src/") or path.endswith(".nes") or path == "Mesen" or (path.endswith(".bin") and not path.endswith("patch.bin")):
        print("Git history still contains", path)
        sys.exit(1)
PY

remote="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
local="$(git rev-parse HEAD)"
if [[ -n "$remote" && "$remote" != "$local" ]]; then
	echo "GitHub's main branch does not match this one."
	echo "If GitHub still has older commits, replacing main removes them:"
	echo "  git push --force-with-lease=refs/heads/main:${remote} origin main"
	echo "Run ./release.sh again after that."
	exit 1
fi

rm -rf dist
mkdir -p dist

build_one() {
	local goos="$1" goarch="$2" out="$3"
	mkdir -p "$(dirname "$out")"
	CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
		go build -trimpath -ldflags "-s -w -X main.version=${version}" \
		-o "$out" ./cmd/smb3-gimmick
}

build_one windows amd64 "dist/windows/SMB3 Gimmick.exe"
build_one windows arm64 "dist/windows-arm64/SMB3 Gimmick.exe"
build_one linux amd64 "dist/linux/SMB3 Gimmick"
build_one linux arm64 "dist/linux-arm64/SMB3 Gimmick"
build_one darwin amd64 "dist/mac-intel-bin/SMB3 Gimmick"
build_one darwin arm64 "dist/mac-bin/SMB3 Gimmick"

mac_app() {
	local bin="$1" dest="$2"
	local app="$dest/SMB3 Gimmick.app"
	mkdir -p "$app/Contents/MacOS"
	cp "$bin" "$app/Contents/MacOS/SMB3 Gimmick"
	chmod +x "$app/Contents/MacOS/SMB3 Gimmick"
	cat > "$app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>SMB3 Gimmick</string>
	<key>CFBundleDisplayName</key><string>SMB3 Gimmick</string>
	<key>CFBundleExecutable</key><string>SMB3 Gimmick</string>
	<key>CFBundleIdentifier</key><string>com.pigmassacre.smb3-gimmick</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>${version#v}</string>
	<key>CFBundleVersion</key><string>${version#v}</string>
	<key>LSMinimumSystemVersion</key><string>11.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
}

mac_app "dist/mac-bin/SMB3 Gimmick" dist/mac
mac_app "dist/mac-intel-bin/SMB3 Gimmick" dist/mac-intel

python3 - << 'PY'
import os, zipfile
jobs = [
    ("dist/SMB3-Gimmick-windows.zip", "dist/windows"),
    ("dist/SMB3-Gimmick-windows-arm64.zip", "dist/windows-arm64"),
    ("dist/SMB3-Gimmick-linux.zip", "dist/linux"),
    ("dist/SMB3-Gimmick-linux-arm64.zip", "dist/linux-arm64"),
    ("dist/SMB3-Gimmick-mac.zip", "dist/mac"),
    ("dist/SMB3-Gimmick-mac-intel.zip", "dist/mac-intel"),
]
for dest, folder in jobs:
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for dirpath, _, names in os.walk(folder):
            for name in names:
                full = os.path.join(dirpath, name)
                arc = os.path.relpath(full, folder)
                z.write(full, arc)
    print("packed", dest)
PY

notes="$(mktemp)"
cat > "$notes" << EOF
SMB3 Gimmick builds the game on your computer from your own copies of Super Mario Bros. 3 and Gimmick!.

Unzip the download and open **SMB3 Gimmick**. A page opens in your browser. Add the original US Super Mario Bros. 3 and the Japanese Gimmick!, then choose **Make the game**.

| Computer | File |
|---|---|
| Windows | SMB3-Gimmick-windows.zip |
| Windows on ARM | SMB3-Gimmick-windows-arm64.zip |
| Mac (2020 or newer) | SMB3-Gimmick-mac.zip |
| Mac (older Intel Mac) | SMB3-Gimmick-mac-intel.zip |
| Linux | SMB3-Gimmick-linux.zip |
| Linux on ARM | SMB3-Gimmick-linux-arm64.zip |

The first time you open it, Windows or macOS may ask you to confirm. On Windows, choose More info, then Run anyway. On a Mac, right-click the app and choose Open.
EOF

gh release create "$version" \
	--title "SMB3 Gimmick ${version}" \
	--notes-file "$notes" \
	dist/SMB3-Gimmick-windows.zip \
	dist/SMB3-Gimmick-windows-arm64.zip \
	dist/SMB3-Gimmick-mac.zip \
	dist/SMB3-Gimmick-mac-intel.zip \
	dist/SMB3-Gimmick-linux.zip \
	dist/SMB3-Gimmick-linux-arm64.zip

rm -f "$notes"
echo "Published ${version}"
