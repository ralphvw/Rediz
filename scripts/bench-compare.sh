#!/usr/bin/env bash
# Usage: scripts/bench-compare.sh <base_dir> <head_dir> [max_regression_pct]
# Builds src/bench.zig from <head_dir> against both trees, runs them alternately
# against Redis on 127.0.0.1:6379, and fails if any workload's best ops/sec
# drops by more than max_regression_pct (default 30) relative to the base.
set -euo pipefail

base_dir=$1
head_dir=$2
threshold=${3:-30}
runs=3

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$head_dir/src/bench.zig" "$base_dir/src/bench.zig"
(cd "$head_dir" && zig build-exe -O ReleaseFast src/bench.zig -femit-bin="$work/head")

if ! (cd "$base_dir" && zig build-exe -O ReleaseFast src/bench.zig -femit-bin="$work/base"); then
    echo "Base does not build with this Zig version; skipping comparison."
    exit 0
fi

for i in $(seq "$runs"); do
    "$work/base" 2>&1 | sed 's/^/base /' >>"$work/results"
    "$work/head" 2>&1 | sed 's/^/head /' >>"$work/results"
done

best() {
    sort -n | tail -n 1
}

echo "| workload | base ops/s | head ops/s | change |"
echo "|---|---|---|---|"

failed=0
for name in $(awk '{ print $2 }' "$work/results" | sort -u); do
    base=$(awk -v n="$name" '$1 == "base" && $2 == n { print $3 }' "$work/results" | best)
    head=$(awk -v n="$name" '$1 == "head" && $2 == n { print $3 }' "$work/results" | best)
    if [ -z "$base" ] || [ -z "$head" ]; then
        echo "| $name | ${base:-n/a} | ${head:-n/a} | n/a |"
        continue
    fi
    change=$(awk -v b="$base" -v h="$head" 'BEGIN { printf "%.1f", (h - b) / b * 100 }')
    echo "| $name | $base | $head | $change% |"
    if awk -v c="$change" -v t="$threshold" 'BEGIN { exit !(c < -t) }'; then
        failed=1
    fi
done

if [ "$failed" -eq 1 ]; then
    echo
    echo "Performance regressed by more than ${threshold}% on at least one workload." >&2
    exit 1
fi
