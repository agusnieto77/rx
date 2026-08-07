# Benchmarks

Reproducible benchmarks for the xtweetsR sidecar and collection pipeline.

## What is measured

| Benchmark | What it measures | Requires Lightpanda |
|-----------|-----------------|---------------------|
| `sidecar_startup` | Time to spawn Node.js, load modules, emit startup banner | No |
| `sidecar_ping` | JSONL round-trip latency for the `ping` method | No |
| `lpd_connection` | Time to establish a CDP WebSocket connection to Lightpanda | Yes |
| `local_fixture_navigation` | Time to navigate to a local HTML page and wait for load event | Yes |
| `local_structured_extraction` | Enable network capture → navigate → wait for XHR → capture events → clear | Yes |

## Usage

```sh
# Run with defaults (1 warmup, 3 measured iterations)
npx ts-node benchmark.ts

# Custom warmup and iterations
npx ts-node benchmark.ts --warmup 3 --iterations 10

# Custom sidecar path
npx ts-node benchmark.ts --sidecar ./path/to/sidecar.js

# Using the runner script
./run.sh --warmup 3 --iterations 5
```

## Output

- **stdout**: JSON object with per-iteration timings, statistics (avg, min, max, p50, p95), and metadata.
- **stderr**: Progress log with timestamps.
- **results/**: Timestamped JSON files saved by the runner script.

## Results format

```json
{
  "timestamp": "2025-01-15T10:30:00.000Z",
  "nodeVersion": "v20.11.0",
  "sidecarPath": "./inst/node/dist/index.js",
  "sidecarVersion": "0.1.0",
  "results": [
    {
      "name": "sidecar_startup",
      "iterations": [145.2, 132.8, 151.3],
      "warmup": 1,
      "avg": 143.1,
      "min": 132.8,
      "max": 151.3,
      "p50": 145.2,
      "p95": 150.1,
      "status": "ok"
    }
  ]
}
```

## Status values

- `ok` — benchmark completed successfully
- `skip` — prerequisite not available (e.g., Lightpanda not running for connection tests)
- `fail` — benchmark ran but encountered errors in all iterations

## Running without Lightpanda

The `sidecar_startup` and `sidecar_ping` benchmarks work without Lightpanda. Connection, navigation, and extraction benchmarks will report `skip` if no CDP endpoint is reachable.

## Adding a new benchmark

1. Add a new `bench<Name>()` async function returning `BenchmarkResult`.
2. Call it in `main()` with the appropriate log messages.
3. Add it to `suite.results`.
