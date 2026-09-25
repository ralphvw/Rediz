const std = @import("std");
const Io = std.Io;
const net = std.Io.net;
const mem = std.mem;
const Uri = std.Uri;

pub const RedisClient = struct {
    io: Io,
    stream: net.Stream,
    reader: net.Stream.Reader,
    writer: net.Stream.Writer,
    allocator: mem.Allocator,

    const Self = @This();

    const read_buffer_size = 4096;
    const write_buffer_size = 4096;

    /// Connect to a Redis server using the provided URI.
    /// The URI should be in the format: redis://[username:password@]host[:port][/db]
    /// If the port is not specified, it defaults to 6379.
    /// If the database is not specified, it defaults to 0.
    /// If the username is not specified, it defaults to an empty string.
    /// If the password is not specified, it defaults to an empty string.
    /// The function returns a RedisClient instance on success or an error on failure.
    pub fn connect(allocator: mem.Allocator, io: Io, uri: []const u8) !Self {
        const parsed_uri = try Uri.parse(uri);
        const port = parsed_uri.port orelse 6379;
        const host = parsed_uri.host.?;

        const address = try net.IpAddress.resolve(io, host.percent_encoded, port);
        const stream = try net.IpAddress.connect(&address, io, .{ .mode = .stream });
        errdefer stream.close(io);

        const read_buf = try allocator.alloc(u8, read_buffer_size);
        errdefer allocator.free(read_buf);
        const write_buf = try allocator.alloc(u8, write_buffer_size);
        errdefer allocator.free(write_buf);

        var client = Self{
            .io = io,
            .stream = stream,
            .reader = stream.reader(io, read_buf),
            .writer = stream.writer(io, write_buf),
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
        self.stream.close(self.io);
        self.allocator.free(self.reader.interface.buffer);
        self.allocator.free(self.writer.interface.buffer);
    }

    /// Send a command to the Redis server.
    pub fn sendCommand(self: *Self, comptime N: usize, args: [N][]const u8) !void {
        const w = &self.writer.interface;
        try w.print("*{d}\r\n", .{N});
        inline for (args) |arg| {
            try w.print("${d}\r\n", .{arg.len});
            try w.writeAll(arg);
            try w.writeAll("\r\n");
        }
        try w.flush();
    }

    /// Reads one CRLF-terminated line from the server, without the trailing "\r\n".
    /// The returned slice is only valid until the next read call.
    fn readLine(self: *Self) ![]u8 {
        const r = &self.reader.interface;
        const line = try r.takeDelimiterInclusive('\n');
        var end = line.len;
        if (end > 0 and line[end - 1] == '\n') end -= 1;
        if (end > 0 and line[end - 1] == '\r') end -= 1;
        return line[0..end];
    }

    /// Read a simple string response from the Redis server.
    pub fn readSimpleString(self: *Self) ![]const u8 {
        const line = try self.readLine();
        return try self.allocator.dupe(u8, line);
    }

    /// Read a bulk string response from the Redis server.
    fn readBulkString(self: *Self) !?[]const u8 {
        const line = try self.readLine();
        if (line.len == 0) return error.InvalidResponse;
        switch (line[0]) {
            '$' => {},
            '-' => return error.RedisError,
            else => return error.InvalidResponse,
        }
        if (mem.eql(u8, line[1..], "-1")) return null;

        const length = std.fmt.parseInt(usize, line[1..], 10) catch return error.InvalidResponse;

        const data = try self.allocator.alloc(u8, length);
        errdefer self.allocator.free(data);

        const r = &self.reader.interface;
        try r.readSliceAll(data);
        try r.discardAll(2); // trailing "\r\n"

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
};

pub const Client = RedisClient;
