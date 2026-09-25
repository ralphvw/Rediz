# Benchmarks

Throughput of Rediz against a local Redis-compatible server, in operations per second (higher is better). Each workload runs on a single connection for several rounds; the table shows the median. Unless noted, commands are blocking request/response round trips.

| Workload | What it does |
|---|---|
| `set_get_small` | `SET` then `GET` of a 32-byte value |
| `hset_hget_small` | `HSET` then `HGET` of a 32-byte value |
| `set_get_64k` | `SET` then `GET` of a 64 KiB value |
| `pipelined_set_get_small` | 50 `SET`/`GET` pairs (32-byte value) queued in a pipeline and sent in one round trip |

## Results

Measured on Linux against Valkey 9.1 on `127.0.0.1`, built with `ReleaseFast`. All rows were measured back to back on the same server; run-to-run noise is around ±20%, and absolute numbers differ between sessions and machines, so compare rows only within one table.

| Version | Zig | `set_get_small` | `hset_hget_small` | `set_get_64k` |
|---|---|---|---|---|
| `zig-0.13` branch | 0.13.0 | 24 | 24 | 25 |
| `zig-0.13` + `TCP_NODELAY` (experiment, not published) | 0.13.0 | 4,737 | 4,277 | 4,545 |
| `main` | 0.16.0 | 14,092 | 15,389 | 8,895 |

### Why 0.13 was so slow

- **Nagle's algorithm and delayed ACKs (~190x).** The 0.13 client wrote each fragment of a command (`*3\r\n`, `$3\r\n`, `SET`, ...) as its own small `write`. Nagle's algorithm holds a small write while an earlier one is unacknowledged, and the server, holding only part of a command, has no reply to piggyback an ACK on and waits out its ~40 ms delayed-ACK timer. Every command stalled ~40 ms (~24 ops/s), independent of value size. Setting `TCP_NODELAY` alone raised it to ~4,500 ops/s.
- **Per-byte reads and many syscalls (~3x).** The 0.13 client issued one `read` per reply byte and ~10 `write`s per command. The 0.16 client uses a 4 KB buffered reader and a single write per command, which also avoids the Nagle stall without `TCP_NODELAY`.

### What changed in 0.16

Nagle's algorithm is still enabled; the client just no longer sends the traffic that triggers the stall. The change is in `sendCommand` in `src/redis.zig`.

Before, `self.stream.writer()` was unbuffered, so every `print` and `writeAll` was its own `write` syscall and its own tiny TCP segment (about 10 for a `SET`):

```zig
var writer = self.stream.writer();
try writer.print("*{d}\r\n", .{N});
inline for (args) |arg| {
    try writer.print("${d}\r\n", .{arg.len});
    try writer.writeAll(arg);
    try writer.writeAll("\r\n");
}
```

Now the client owns a 4 KB write buffer (allocated in `connect`), and the command is written into it and flushed once:

```zig
const w = &self.writer.interface;
try w.print("*{d}\r\n", .{N});
inline for (args) |arg| {
    try w.print("${d}\r\n", .{arg.len});
    try w.writeAll(arg);
    try w.writeAll("\r\n");
}
try w.flush();
```

The whole command reaches the server in one segment, so the server replies immediately and the ACK rides on that reply instead of waiting on the delayed-ACK timer.

Commands larger than the 4 KB buffer are flushed in several writes. The 64 KiB workload still runs at ~8,900 ops/s, so it is not hitting the stall, but the buffer is what protects small commands. Setting `TCP_NODELAY` in `connect` would make this independent of write patterns; it is not currently set.

## Pipelining

Once the per-command stall is gone, a single unpipelined command costs one network round trip (~70 µs here), which is nearly all kernel and server time, not client code. Pipelining removes the round trips instead of shaving them: `client.pipeline()` queues commands in the write buffer, and `exec()` sends them with one flush and reads all the replies.

Measured back to back in one run on the same server:

| Workload | ops/s |
|---|---|
| `set_get_small` (one at a time) | 7,383 |
| `pipelined_set_get_small` (50 pairs per batch) | 384,667 |

That is about 50x. Batches should stay modest, since replies are only read after every command in the batch has been written.

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
