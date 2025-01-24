const std = @import("std");
const Redis = @import("redis.zig").Redis;

pub fn main() !void {
    var allocator = std.heap.page_allocator;
    var redis = try Redis.connect(&allocator, "127.0.0.1", 6379);

    try redis.set("foo", "bar");
    const value = try redis.get("foo");
    std.debug.print("Value: {s}\n", .{value});
}
