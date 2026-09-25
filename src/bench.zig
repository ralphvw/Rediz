const std = @import("std");
const RedisClient = @import("redis.zig").RedisClient;

const rounds = 5;

const Workload = struct {
    name: []const u8,
    iterations: usize,
    value_len: usize,
    hash: bool,
    batch: usize = 0,
};

const workloads = [_]Workload{
    .{ .name = "set_get_small", .iterations = 20_000, .value_len = 32, .hash = false },
    .{ .name = "hset_hget_small", .iterations = 20_000, .value_len = 32, .hash = true },
    .{ .name = "set_get_64k", .iterations = 300, .value_len = 64 * 1024, .hash = false },
    .{ .name = "pipelined_set_get_small", .iterations = 400, .value_len = 32, .hash = false, .batch = 50 },
};

const has_pipeline = @hasDecl(RedisClient, "pipeline");

fn runPipelinedBatch(client: *RedisClient, batch: usize, value: []const u8) !void {
    if (has_pipeline) {
        var pipe = client.pipeline();
        for (0..batch) |_| {
            try pipe.set("bench_key", value);
            try pipe.get("bench_key");
        }
        var replies = try pipe.exec();
        replies.deinit();
    } else {
        unreachable;
    }
}

fn runOnce(client: *RedisClient, allocator: std.mem.Allocator, io: std.Io, w: Workload, value: []const u8) !f64 {
    const start = std.Io.Timestamp.now(io, .awake);
    for (0..w.iterations) |_| {
        if (w.batch > 0) {
            try runPipelinedBatch(client, w.batch, value);
        } else if (w.hash) {
            try client.hset("bench_hash", "field", value);
            const got = (try client.hget("bench_hash", "field")).?;
            allocator.free(got);
        } else {
            try client.set("bench_key", value);
            const got = (try client.get("bench_key")).?;
            allocator.free(got);
        }
    }
    const elapsed_ns: f64 = @floatFromInt(start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds);
    const ops_per_iteration: usize = if (w.batch > 0) w.batch * 2 else 2;
    const ops: f64 = @floatFromInt(w.iterations * ops_per_iteration);
    return ops / (elapsed_ns / std.time.ns_per_s);
}

fn median(samples: []f64) f64 {
    std.mem.sort(f64, samples, {}, std.sort.asc(f64));
    return samples[samples.len / 2];
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = try RedisClient.connect(allocator, io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    for (workloads) |w| {
        if (w.batch > 0 and !has_pipeline) continue;

        const value = try allocator.alloc(u8, w.value_len);
        defer allocator.free(value);
        @memset(value, 'x');

        _ = try runOnce(&client, allocator, io, w, value);

        var samples: [rounds]f64 = undefined;
        for (&samples) |*s| s.* = try runOnce(&client, allocator, io, w, value);

        std.debug.print("{s} {d:.0}\n", .{ w.name, median(&samples) });
    }
}
