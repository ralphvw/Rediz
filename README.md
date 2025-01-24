# REDIZ

A Zig library for interacting with Redis.

## Features

- Connect to Redis
- `SET` and `GET` commands

## Installation

Clone this repository and add it as a dependency in your Zig project.

## Usage

```zig
const std = @import("std");
const Redis = @import("Rediz/redis.zig").Redis;

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var redis = try Redis.connect(&allocator, "127.0.0.1", 6379);

    try redis.set("key", "value");
    const value = try redis.get("key");
    std.debug.print("Value: {s}\n", .{value});
}
```

## Adding Rediz to Your Project

You can include Rediz in your project by adding the following to your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("example", "src/main.zig");
    exe.setBuildMode(mode);

    // Add Rediz as a dependency
    const rediz = b.downloadGit(
        .{
            .url = "https://github.com/ralphvw/Rediz.git",
            .hash = "<commit-hash>", // Replace with a specific commit or version tag
        },
        .{}
    );
    exe.addModule("Rediz", rediz.module("redis.zig"));
    exe.linkLibrary(rediz.artifact);

    exe.install();
}
```
