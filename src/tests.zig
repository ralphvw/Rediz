const std = @import("std");
const testing = std.testing;
const RedisClient = @import("redis.zig").RedisClient;

test "RedisClient can connect and disconnect" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try testing.expect(client.stream.handle != undefined);
}

test "RedisClient can set and get a key" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("test_key", "test_value");

    const value = try client.get("test_key");

    defer std.testing.allocator.free(value.?);
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "test_value"));
}

test "RedisClient handles missing keys" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    const value = try client.get("non_existent_key");
    try testing.expect(value == null);
}

test "RedisClient fails authentication with wrong password" {
    const result = RedisClient.connect(std.testing.allocator, "redis://:wrongpass@127.0.0.1:6379");
    try testing.expectError(error.AuthFailed, result);
}

// test "RedisClient can select a database" {
//     var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379/2");
//     defer client.disconnect();

//     try client.set("db_test_key", "db_test_value");
//     const value = try client.get("db_test_key");

//     try testing.expect(value != null);
//     try testing.expect(std.mem.eql(u8, value.?, "db_test_value"));
// }
