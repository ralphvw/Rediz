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
const RedisClient = @import("Rediz").RedisClient;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Connect to Redis (example: redis://password@localhost:6379/0)
    var client = try RedisClient.connect(allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    // Set and get value
    try client.set("zig_test", "");
    const value = try client.get("zig_test");

    if (value) |v| {
        std.debug.print("Got value: {s}\n", .{v});
        allocator.free(v);
    }
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
