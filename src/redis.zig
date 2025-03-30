const std = @import("std");
const net = std.net;
const mem = std.mem;
const Uri = std.Uri;

pub const RedisClient = struct {
    stream: net.Stream,
    allocator: mem.Allocator,

    const Self = @This();

    /// Connect to a Redis server using the provided URI.
    /// The URI should be in the format: redis://[username:password@]host[:port][/db]
    /// If the port is not specified, it defaults to 6379.
    /// If the database is not specified, it defaults to 0.
    /// If the username is not specified, it defaults to an empty string.
    /// If the password is not specified, it defaults to an empty string.
    /// The function returns a RedisClient instance on success or an error on failure.
    pub fn connect(allocator: mem.Allocator, uri: []const u8) !Self {
        const parsed_uri = try Uri.parse(uri);
        const port = parsed_uri.port orelse 6379;
        const host = parsed_uri.host.?;
        const address = try net.Address.resolveIp(host.percent_encoded, port);

        const stream = try net.tcpConnectToAddress(address);

        var client = Self{
            .stream = stream,
            .allocator = allocator,
        };

        if (parsed_uri.password) |password| {
            try client.auth(password.percent_encoded);
        }

        const path = parsed_uri.path;
        if (path.percent_encoded.len > 1 and path.percent_encoded[0] == '/') {
            const db = try std.fmt.parseInt(u8, path.percent_encoded[1..], 10);
            try client.select(db);
        }

        return client;
    }

    /// Disconnect from the Redis server.
    pub fn disconnect(self: *Self) void {
        self.stream.close();
    }

    /// Send a command to the Redis server.
    pub fn sendCommand(self: *Self, comptime N: usize, args: [N][]const u8) !void {
        var writer = self.stream.writer();
        try writer.print("*{d}\r\n", .{N});
        inline for (args) |arg| {
            try writer.print("${d}\r\n", .{arg.len});
            try writer.writeAll(arg);
            try writer.writeAll("\r\n");
        }
    }

    /// Read a simple string response from the Redis server.
    pub fn readSimpleString(self: *Self) ![]const u8 {
        var reader = self.stream.reader();
        const line = try reader.readUntilDelimiterAlloc(self.allocator, '\r', 1024);
        // skip bytes if line string starts with '\n'
        if (line.len > 0 and line[0] == '\n') {
            const new_line = try self.allocator.alloc(u8, line.len - 1);
            std.mem.copyForwards(u8, new_line, line[1..]);
            self.allocator.free(line);
            return new_line;
        }

        return line;
    }

    /// Read a bulk string response from the Redis server.
    fn readBulkString(self: *Self) !?[]const u8 {
        var reader = self.stream.reader();
        const len = try reader.readUntilDelimiterAlloc(self.allocator, '\r', 1024);
        defer self.allocator.free(len);
        if (containsChar(len, '-')) {
            return null;
        }

        const length = std.fmt.parseInt(usize, len[2..], 10) catch return null;
        if (length == -1) return null;

        var data = try self.allocator.alloc(u8, length + 1);
        errdefer self.allocator.free(data);
        try reader.readNoEof(data);
        try reader.skipBytes(2, .{});
        if (data.len > 0 and data[0] == '\n') {
            const new_data = try self.allocator.alloc(u8, data.len - 1);
            std.mem.copyForwards(u8, new_data, data[1..]);
            self.allocator.free(data);
            return new_data;
        }

        return data;
    }

    /// Sets a key-value pair in Redis.
    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        try self.sendCommand(3, .{ "SET", key, value });
        const response = try self.readSimpleString();
        defer self.allocator.free(response);
        if (!mem.eql(u8, response, "+OK")) {
            return error.RedisError;
        }
    }

    /// Gets the value of a key from Redis.
    /// Retuns an allocated string. Remember to free it after use.
    /// Returns null if the key does not exist.
    pub fn get(self: *Self, key: []const u8) !?[]const u8 {
        try self.sendCommand(2, .{ "GET", key });
        return try self.readBulkString();
    }

    /// Gets the value of a key from Redis and copies it into the provided buffer.
    /// Returns an error if the buffer is too small.
    /// Returns null if the key does not exist.
    pub fn getInto(self: *Self, key: []const u8, buffer: []u8) !?[]const u8 {
        try self.sendCommand(2, .{ "GET", key });

        const result = try self.readBulkString();
        if (result == null) return null;

        const value = result.?;

        if (buffer.len < value.len) {
            self.allocator.free(value);
            return error.BufferTooSmall;
        }

        std.mem.copyForwards(u8, buffer[0..value.len], value);
        self.allocator.free(value);

        return buffer[0..value.len];
    }

    /// Sets a field in a Redis hash.
    /// Equivalent to: HSET key field value
    pub fn hset(self: *Self, key: []const u8, field: []const u8, value: []const u8) !void {
        try self.sendCommand(4, .{ "HSET", key, field, value });
        const response = try self.readSimpleString();
        defer self.allocator.free(response);
        if (!std.mem.startsWith(u8, response, ":")) {
            return error.RedisError;
        }
    }

    /// Gets the value of a field in a Redis hash.
    /// Returns null if field or key doesn't exist.
    /// Caller must free the returned value.
    pub fn hget(self: *Self, key: []const u8, field: []const u8) !?[]const u8 {
        try self.sendCommand(3, .{ "HGET", key, field });
        return try self.readBulkString();
    }

    /// Gets the value of a field in a Redis hash and copies it into the provided buffer.
    /// Returns null if the field or key doesn't exist.
    /// Returns an error if the buffer is too small.
    pub fn hgetInto(self: *Self, key: []const u8, field: []const u8, buffer: []u8) !?[]const u8 {
        try self.sendCommand(3, .{ "HGET", key, field });

        const result = try self.readBulkString();
        if (result == null) return null;

        const value = result.?;

        if (buffer.len < value.len) {
            self.allocator.free(value);
            return error.BufferTooSmall;
        }

        std.mem.copyForwards(u8, buffer[0..value.len], value);
        self.allocator.free(value);

        return buffer[0..value.len];
    }

    /// Authenticates with the Redis server using the provided password.
    fn auth(self: *Self, password: []const u8) !void {
        try self.sendCommand(2, .{ "AUTH", password });
        const response = try self.readSimpleString();
        defer self.allocator.free(response);
        if (!mem.eql(u8, response, "+OK")) {
            return error.AuthFailed;
        }
    }

    /// Selects a Redis database.
    pub fn select(self: *Self, db: u8) !void {
        var buf: [16]u8 = undefined;
        const db_str = try std.fmt.bufPrint(&buf, "{}", .{db});
        try self.sendCommand(2, .{ "SELECT", db_str });
        const response = try self.readSimpleString();
        defer self.allocator.free(response);
        if (!mem.eql(u8, response, "+OK")) {
            return error.SelectFailed;
        }
    }

    /// Helper function to check if a byte array contains a specific character.
    fn containsChar(input: []const u8, target: u8) bool {
        for (input) |char| {
            if (char == target) {
                return true;
            }
        }
        return false;
    }
};
