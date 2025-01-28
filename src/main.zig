const std = @import("std");
const RedisClient = @import("redis.zig").RedisClient;

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
