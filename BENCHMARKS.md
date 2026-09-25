# Benchmarks

Throughput of Rediz against a local Redis-compatible server, in operations per second (higher is better). Each workload is a sequence of blocking request/response round trips on a single connection, run for several rounds; the table shows the median.

| Workload | What it does |
|---|---|
| `set_get_small` | `SET` then `GET` of a 32-byte value |
| `hset_hget_small` | `HSET` then `HGET` of a 32-byte value |
| `set_get_64k` | `SET` then `GET` of a 64 KiB value |

## Results

Measured on Linux against Valkey 9.1 on `127.0.0.1`, built with `ReleaseFast`.

| Version | Zig | `set_get_small` | `hset_hget_small` | `set_get_64k` |
|---|---|---|---|---|
| `zig-0.13` branch | 0.13.0 | 24 | 24 | 25 |
| `main` | 0.16.0 | 7,468 | 8,780 | 4,036 |

The 0.13 client wrote every fragment of a command as a separate unbuffered `write` and read replies one byte at a time. On this machine that pattern triggered a fixed ~40 ms stall per command (Nagle's algorithm interacting with delayed ACKs), which is why all three workloads sit at ~24 ops/s regardless of value size. The 0.16 client buffers reads and sends each command with a single flush. The size of the gap depends on kernel TCP behavior and will vary between machines; compare numbers only within one machine.

## Running

Start a Redis-compatible server on `127.0.0.1:6379`, then:

```sh
zig build bench
```

Results are printed to stderr as `<workload> <ops/sec>`.

## Regression check

Pull requests run `.github/workflows/zig-bench.yml`, which builds the benchmark from the PR against both the base branch and the PR head on the same runner, runs them alternately, and fails if any workload's best-of-three throughput drops by more than 30%. Run-to-run noise on a single machine is around ±20%, so smaller changes won't be flagged. The same check can be run locally:

```sh
bash scripts/bench-compare.sh <base_checkout> <head_checkout> [max_regression_pct]
```

Shared CI runners are noisy, so treat a failure as a prompt to re-run and investigate rather than proof of a regression.

## Adding a row

When cutting a release or making a performance-relevant change, run `zig build bench` and add a row to the table above with the version and the Zig version used.
