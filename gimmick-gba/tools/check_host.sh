#!/bin/sh
# Build the translated game for the PC, replay the recording, compare RAM.
set -e
cd "$(dirname "$0")/.."
python3 tools/recomp.py | tail -1
gcc -O1 -w -DHOST $HOST_FLAGS -Iruntime -o out/host runtime/host.c runtime/core.c out/gen/*.c
./out/host "Gimmick! (Japan).nes" out/trace/padreads.bin "${1:-6000}" out/host_ram.bin
python3 tools/compare.py
