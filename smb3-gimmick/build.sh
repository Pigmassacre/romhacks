#!/bin/bash
set -e
cd "$(dirname "$0")"
mkdir -p out
python3 tools/build_chr.py
python3 tools/build_title.py
cd src
../ref/nesasm/nesasm -s smb3.asm > ../out/build.log 2>&1 || { cat ../out/build.log; exit 1; }
mv smb3.nes ../out/smb3-gimmick.nes
[ -f smb3.fns ] && mv smb3.fns ../out/
echo "built out/smb3-gimmick.nes"
cd ..
python3 tools/patch.py
