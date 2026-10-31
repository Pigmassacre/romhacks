#!/bin/bash
# Builds the game and remakes the savestates, which hold addresses in the code.
cd "$(dirname "$0")/.."
./build.sh > /dev/null || exit 1
python3 tests/levels.py > /dev/null
python3 tests/run.py states | head -1
