const std = @import("std");
const testing = std.testing;
const RedisClient = @import("redis.zig").RedisClient;

test "RedisClient can connect and disconnect" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    // Send a PING to confirm connection
    try client.sendCommand(1, .{"PING"});
    const response = try client.readSimpleString();
    defer std.testing.allocator.free(response);

    try testing.expect(std.mem.eql(u8, response, "+PONG"));
}

test "RedisClient can set and get a key" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("test_key", "test_value");

    const value = try client.get("test_key");

    defer std.testing.allocator.free(value.?);
    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "test_value"));
}

test "RedisClient handles missing keys" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    const value = try client.get("non_existent_key");
    try testing.expect(value == null);
}

test "RedisClient fails authentication with wrong password" {
    const result = RedisClient.connect(std.testing.allocator, std.testing.io, "redis://:wrongpass@127.0.0.1:6379");
    try testing.expectError(error.AuthFailed, result);
}

test "RedisClient can select a database" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379/2");
    defer client.disconnect();

    try client.set("db_test_key", "db_test_value");
    const value = try client.get("db_test_key");

    defer std.testing.allocator.free(value.?);

    try testing.expect(value != null);
    try testing.expect(std.mem.eql(u8, value.?, "db_test_value"));
}

test "Redis client can get value into a stack allocated buffer" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("db_test_key", "db_test_value");
    var buffer: [100]u8 = undefined;
    const response = try client.getInto("db_test_key", buffer[0..]);
    try testing.expect(std.mem.eql(u8, response.?, "db_test_value"));
}

test "Redis client fails to get value into stack allocated buffer because size is too small" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("db_test_key", "db_test_value");

    var buffer: [1]u8 = undefined;

    const result = client.getInto("db_test_key", buffer[0..]);

    try testing.expectError(error.BufferTooSmall, result);
}

test "Redis client can set and get from a hashset" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
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
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
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
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var buffer: [1]u8 = undefined;

    try client.hset("lumon_employees", "emp_1", "Mark S.");

    const response = client.hgetInto("lumon_employees", "emp_1", &buffer);

    try testing.expectError(error.BufferTooSmall, response);
}

// RedisClient's internal read buffer is 4096 bytes. Bulk strings are read with
// `readSliceAll` directly into an allocator-owned buffer, so values should round-trip
// correctly regardless of whether they fit in that internal buffer, straddle its
// boundary, or exceed it by a wide margin. Bytes 0..255 are cycled through so the
// payload also exercises binary safety (embedded '\r' and '\n', which the old
// delimiter-based parsing was sensitive to).
test "RedisClient round-trips values of varying lengths, including binary data" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    const lengths = [_]usize{ 0, 1, 15, 512, 4095, 4096, 4097, 8192, 65536 };

    for (lengths) |len| {
        const value = try allocator.alloc(u8, len);
        defer allocator.free(value);
        for (value, 0..) |*b, i| b.* = @truncate(i);

        var key_buf: [32]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "len_test_{d}", .{len});

        try client.set(key, value);

        const result = try client.get(key);
        defer if (result) |r| allocator.free(r);

        try testing.expect(result != null);
        try testing.expect(std.mem.eql(u8, result.?, value));
    }
}

test "RedisClient handles a key name longer than the internal read buffer" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var key_buf: [5000]u8 = undefined;
    @memset(&key_buf, 'k');
    const key = key_buf[0..];

    try client.set(key, "value_for_long_key");

    const result = try client.get(key);
    defer allocator.free(result.?);

    try testing.expect(std.mem.eql(u8, result.?, "value_for_long_key"));
}

test "RedisClient getInto succeeds when buffer size exactly matches value length" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.set("exact_buf_key", "12345");

    var buffer: [5]u8 = undefined;
    const response = try client.getInto("exact_buf_key", &buffer);

    try testing.expect(std.mem.eql(u8, response.?, "12345"));
}

test "RedisClient getInto returns null for a missing key without touching the buffer" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var buffer: [16]u8 = undefined;
    const response = try client.getInto("definitely_missing_key", &buffer);

    try testing.expect(response == null);
}

test "RedisClient hash fields round-trip a value larger than the internal read buffer" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    const value = try allocator.alloc(u8, 10_000);
    defer allocator.free(value);
    for (value, 0..) |*b, i| b.* = @truncate(i);

    try client.hset("large_hash", "big_field", value);

    const response = try client.hget("large_hash", "big_field");
    defer if (response) |r| allocator.free(r);

    try testing.expect(response != null);
    try testing.expect(std.mem.eql(u8, response.?, value));
}

test "RedisClient returns RedisError when a bulk reply is an error" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.hset("wrongtype_hash", "field", "value");

    try testing.expectError(error.RedisError, client.get("wrongtype_hash"));
}

test "RedisClient returns InvalidResponse when a bulk reply is malformed" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.sendCommand(1, .{"PING"});

    try testing.expectError(error.InvalidResponse, client.get("any_key"));
}

test "Pipeline returns replies in order for mixed commands" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var pipe = client.pipeline();
    try pipe.set("pipe_key", "pipe_value");
    try pipe.get("pipe_key");
    try pipe.hset("pipe_hash", "field", "hash_value");
    try pipe.hget("pipe_hash", "field");
    try pipe.get("pipe_missing_key");

    var replies = try pipe.exec();
    defer replies.deinit();

    try testing.expectEqual(@as(usize, 5), replies.items.len);
    try testing.expectEqualStrings("OK", replies.items[0].status);
    try testing.expectEqualStrings("pipe_value", replies.items[1].bulk.?);
    try testing.expect(replies.items[2] == .integer);
    try testing.expectEqualStrings("hash_value", replies.items[3].bulk.?);
    try testing.expect(replies.items[4].bulk == null);
}

test "Pipeline records an error reply and keeps the connection in sync" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    try client.hset("pipe_wrongtype_hash", "field", "value");

    var pipe = client.pipeline();
    try pipe.set("pipe_before_error", "1");
    try pipe.get("pipe_wrongtype_hash");
    try pipe.set("pipe_after_error", "2");

    var replies = try pipe.exec();
    defer replies.deinit();

    try testing.expectEqualStrings("OK", replies.items[0].status);
    try testing.expect(std.mem.startsWith(u8, replies.items[1].err, "WRONGTYPE"));
    try testing.expectEqualStrings("OK", replies.items[2].status);

    const value = try client.get("pipe_after_error");
    defer if (value) |v| std.testing.allocator.free(v);
    try testing.expectEqualStrings("2", value.?);
}

test "Pipeline with no commands returns no replies" {
    var client = try RedisClient.connect(std.testing.allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    var pipe = client.pipeline();
    var replies = try pipe.exec();
    defer replies.deinit();

    try testing.expectEqual(@as(usize, 0), replies.items.len);
    try client.set("pipe_empty_check", "ok");
}

test "Pipeline handles batches larger than the internal buffers" {
    const allocator = std.testing.allocator;
    var client = try RedisClient.connect(allocator, std.testing.io, "redis://127.0.0.1:6379");
    defer client.disconnect();

    const big = try allocator.alloc(u8, 10_000);
    defer allocator.free(big);
    for (big, 0..) |*b, i| b.* = @truncate(i);

    const pairs = 300;
    var pipe = client.pipeline();
    for (0..pairs) |i| {
        var key_buf: [32]u8 = undefined;
        const key = try std.fmt.bufPrint(&key_buf, "pipe_batch_{d}", .{i});
        try pipe.set(key, if (i == 150) big else "small");
        try pipe.get(key);
    }

    var replies = try pipe.exec();
    defer replies.deinit();

    try testing.expectEqual(@as(usize, pairs * 2), replies.items.len);
    for (0..pairs) |i| {
        try testing.expectEqualStrings("OK", replies.items[i * 2].status);
        const expected: []const u8 = if (i == 150) big else "small";
        try testing.expectEqualSlices(u8, expected, replies.items[i * 2 + 1].bulk.?);
    }
}
