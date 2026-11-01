#!/bin/bash
# Runs the search of tests/s_solve.lua on the given levels (default: every map level), in parallel.
#   SOLVE_FRAMES=n JOBS=n tests/solve_all.sh [levels...]
cd "$(dirname "$0")/.."
levels=("$@")
[ ${#levels[@]} -eq 0 ] && levels=($(awk '$6=="-"{print $1}' out/levels.txt))
JOBS=${JOBS:-11}
printf '%s\n' "${levels[@]}" | RUN_TIMEOUT=${RUN_TIMEOUT:-1500} xargs -P "$JOBS" -I{} sh -c 'SOLVE_LEVELS={} RUN_TAG=_{} python3 tests/run.py solve > /dev/null'
for l in "${levels[@]}"; do head -1 "out/test/solve_$l.txt" 2>/dev/null || echo "$l none"; done
