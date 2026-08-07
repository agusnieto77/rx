#!/bin/sh
# Run xtweetsR benchmarks.
# Usage: ./run.sh [--warmup N] [--iterations N]
#
# Outputs JSON to stdout, progress to stderr.
# Results are saved to benchmarks/results/ with a timestamp.

set -e

BENCHMARKS_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="$BENCHMARKS_DIR/results"
mkdir -p "$RESULTS_DIR"

# Parse arguments.
ARGS=""
for arg in "$@"; do
  case "$arg" in
    --warmup|--iterations)
      ARGS="$ARGS $arg"
      ;;
    *)
      ARGS="$ARGS $arg"
      ;;
  esac
done

# Run benchmark and capture output.
TIMESTAMP=$(date -u +"%Y%m%dT%H%M%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
OUTPUT="$RESULTS_DIR/benchmark-${TIMESTAMP}.json"

echo "Running xtweetsR benchmark harness..." >&2
echo "Results will be saved to: $OUTPUT" >&2

cd "$BENCHMARKS_DIR/.."
npx ts-node benchmarks/benchmark.ts $ARGS > "$OUTPUT" 2>"$RESULTS_DIR/benchmark-${TIMESTAMP}.log"

echo "" >&2
echo "Done. Results saved to $OUTPUT" >&2
echo "Log saved to $RESULTS_DIR/benchmark-${TIMESTAMP}.log" >&2
