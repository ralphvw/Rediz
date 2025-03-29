const std = @import("std");
const testing = std.testing;
const RedisClient = @import("redis.zig").RedisClient;

test "RedisClient can connect and disconnect" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    // Send a PING to confirm connection
    try client.sendCommand(&[_][]const u8{"PING"});
    const response = try client.readSimpleString();
    defer std.testing.allocator.free(response);

    try testing.expect(std.mem.eql(u8, response, "+PONG"));
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
    const result = RedisClient.connect(std.testing.allocator, "redis://:wrongpasscallll@127.0.0.1:6379");
    try testing.expectError(error.AuthFailed, result);
}

test "RedisClient can select a database" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379/2");
    defer client.disconnect();

    try client.set("db_test_key", "db_test_value");
    const value = try client.get("db_test_key");

    defer std.testing.allocator.free(value.?);

    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "db_test_value"));
}

test "Redis client can get value into a stack allocated buffer" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("db_test_key", "db_test_value");
    var buffer: [100]u8 = undefined;
    const response = try client.getInto("db_test_key", buffer[0..]);
    try testing.expect(std.mem.eql(u8, response.?, "db_test_value"));
}

test "Redis client fails to get value into stack allocated buffer because size is too small" {
    var client = try RedisClient.connect(std.testing.allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("db_test_key", "db_test_value");

    var buffer: [1]u8 = undefined;

    const result = client.getInto("db_test_key", buffer[0..]);

    try testing.expectError(error.BufferTooSmall, result);
}

test "Redis client can set and get from a hashset" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.hset("lumon_employees", "emp_1", "Mark S.");
    const response = try client.hget("lumon_employees", "emp_1");
    if (response) |v| {
        try testing.expect(std.mem.eql(u8, v, "Mark S."));
        allocator.free(v);
    } else {
        try testing.expect(false);
    }
}

test "Redis client can set and get from a hashset into a stack allocated buffer" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var buffer: [100]u8 = undefined;

    try client.hset("lumon_employees", "emp_1", "Mark S.");

    const response = try client.hgetInto("lumon_employees", "emp_1", &buffer);
    if (response) |v| {
        try testing.expect(std.mem.eql(u8, v, "Mark S."));
    } else {
        try testing.expect(false);
    }
}

test "Redis client fails to get from a hashset into a stack allocated buffer" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var buffer: [1]u8 = undefined;

    try client.hset("lumon_employees", "emp_1", "Mark S.");

    const response = try client.hgetInto("lumon_employees", "emp_1", &buffer);
    if (response) |_| {
        try testing.expect(false);
    } else {
        try testing.expectError(error.BufferTooSmall, response);
    }
}
