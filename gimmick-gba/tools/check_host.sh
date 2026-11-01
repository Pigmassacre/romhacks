#!/bin/sh
# Build the translated game for the PC, replay a recording, compare RAM.
#     tools/check_host.sh [trace-dir]
set -e
cd "$(dirname "$0")/.."
TRACE="${1:-out/trace}"
python3 tools/recomp.py | tail -2
gcc -O1 -w -DHOST $HOST_FLAGS -Iruntime -o out/host runtime/host.c runtime/core.c runtime/apu.c out/gen/*.c
FRAMES=$(wc -l < "$TRACE/cpu.txt")
./out/host "Gimmick! (Japan).nes" "$TRACE" "$FRAMES" out/host_ram.bin
python3 tools/compare.py "$TRACE" out/host_ram.bin
