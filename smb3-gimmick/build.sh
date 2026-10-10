#!/bin/bash
set -e
cd "$(dirname "$0")"
if [ ! -f src/smb3.asm ]; then
	echo "Open SMB3 Gimmick and choose your copies of the two games."
	echo "This script is only for working on the game, and that source is not in this repository."
	exit 1
fi
cd src
../ref/nesasm/nesasm -s smb3.asm > ../out/build.log 2>&1 || { cat ../out/build.log; exit 1; }
mv smb3.nes ../out/smb3-gimmick.nes
[ -f smb3.fns ] && mv smb3.fns ../out/
echo "built out/smb3-gimmick.nes"
