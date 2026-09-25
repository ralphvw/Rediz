# REDIZ

A Zig library for interacting with Redis.

## Features

- Connect to Redis
- `SET` and `GET` commands
- `HSET` and `HGET` commands

## Requirements

Zig 0.16.0 or newer. For Zig 0.13, use the [`zig-0.13`](https://github.com/ralphvw/Rediz/tree/zig-0.13) branch.

## Performance

Operations per second on a local server (higher is better). See [BENCHMARKS.md](./BENCHMARKS.md) for details.

| Version | Zig | `SET`/`GET` | `HSET`/`HGET` | `SET`/`GET` 64 KiB |
|---|---|---|---|---|
| `zig-0.13` branch | 0.13.0 | 24 | 24 | 25 |
| `main` | 0.16.0 | 14,092 | 15,389 | 8,895 |

## Installation

`zig fetch --save git+https://github.com/ralphvw/rediz#main`

## Usage

```zig
const std = @import("std");
const rediz = @import("rediz");

pub fn main() !void {
    // Setting up the allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Setting up I/O
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Connect to Redis (example: redis://password@localhost:6379/0)
    var client = try rediz.Client.connect(allocator, io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    // Set a key-value pair
    try client.set("zig_test", "");

    // Get value into a heap-allocated buffer (caller must free)
    const value = try client.get("zig_test");

    if (value) |v| {
        std.debug.print("Got value: {s}\n", .{v});
        allocator.free(v); // Caller must free
    }

    // Get value into a stack allocated buffer
    var buffer: [100]u8 = undefined;
    var response: []const u8 = undefined;
    if (try client.getInto("some_key", buffer[0..])) |v| {
        response = v;
    }
}
```

## Adding Rediz to Your Project

You can include Rediz in your project by adding the following to your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    /// ... build script

    const rediz = b.dependency("rediz", .{
        .target = target,
        .optimize = optimize,
    });

    // the executable from your call to b.addExecutable(...)
    exe.root_module.addImport("rediz", rediz.module("rediz"));
}
```

## 🤝 Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to contribute, set up your environment, and submit pull requests.
