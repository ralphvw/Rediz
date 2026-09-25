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
        try self.writeCommand(N, args);
        try self.writer.interface.flush();
    }

    /// Encodes a command into the write buffer without flushing it.
    fn writeCommand(self: *Self, comptime N: usize, args: [N][]const u8) !void {
        const w = &self.writer.interface;
        try w.print("*{d}\r\n", .{N});
        inline for (args) |arg| {
            try w.print("${d}\r\n", .{arg.len});
            try w.writeAll(arg);
            try w.writeAll("\r\n");
        }
    }

    /// Starts a pipeline: commands are queued locally and sent together by `exec`,
    /// costing one network round trip for the whole batch.
    pub fn pipeline(self: *Self) Pipeline {
        return .{ .client = self };
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
        return try self.readPayload(self.allocator, length);
    }

    /// Reads `length` bytes of bulk string payload plus its trailing "\r\n".
    fn readPayload(self: *Self, allocator: mem.Allocator, length: usize) ![]u8 {
        const data = try allocator.alloc(u8, length);
        errdefer allocator.free(data);

        const r = &self.reader.interface;
        try r.readSliceAll(data);
        try r.discardAll(2);

        return data;
    }

    /// Reads one reply of any type. Strings are allocated from `allocator`.
    fn readReply(self: *Self, allocator: mem.Allocator) !Reply {
        const line = try self.readLine();
        if (line.len == 0) return error.InvalidResponse;
        const body = line[1..];
        switch (line[0]) {
            '+' => return .{ .status = try allocator.dupe(u8, body) },
            '-' => return .{ .err = try allocator.dupe(u8, body) },
            ':' => return .{ .integer = std.fmt.parseInt(i64, body, 10) catch return error.InvalidResponse },
            '$' => {
                if (mem.eql(u8, body, "-1")) return .{ .bulk = null };
                const length = std.fmt.parseInt(usize, body, 10) catch return error.InvalidResponse;
                return .{ .bulk = try self.readPayload(allocator, length) };
            },
            else => return error.InvalidResponse,
        }
    }

    /// Sets a key-value pair in Redis.
    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        try self.sendCommand(3, .{ "SET", key, value });
        const response = try self.readLine();
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
        const response = try self.readLine();
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
        const response = try self.readLine();
        if (!mem.eql(u8, response, "+OK")) {
            return error.AuthFailed;
        }
    }

    /// Selects a Redis database.
    pub fn select(self: *Self, db: u8) !void {
        var buf: [16]u8 = undefined;
        const db_str = try std.fmt.bufPrint(&buf, "{}", .{db});
        try self.sendCommand(2, .{ "SELECT", db_str });
        const response = try self.readLine();
        if (!mem.eql(u8, response, "+OK")) {
            return error.SelectFailed;
        }
    }
};

/// A single reply from the server.
pub const Reply = union(enum) {
    /// Simple string reply, without the leading '+' (e.g. "OK").
    status: []const u8,
    /// Error reply, without the leading '-' (e.g. "WRONGTYPE ...").
    err: []const u8,
    integer: i64,
    /// Bulk string reply. Null when the key or field does not exist.
    bulk: ?[]const u8,
};

/// The replies of an executed pipeline, in the order the commands were queued.
/// All strings are owned by the `Replies` and are freed by `deinit`.
pub const Replies = struct {
    arena: std.heap.ArenaAllocator,
    items: []const Reply,

    pub fn deinit(self: *Replies) void {
        self.arena.deinit();
    }
};

/// A batch of commands sent to the server together.
/// Keep batches modest: the server's replies are only read after every command
/// has been written, so an enormous batch can fill both sides' socket buffers.
pub const Pipeline = struct {
    client: *RedisClient,
    count: usize = 0,

    /// Queues an arbitrary command.
    pub fn command(self: *Pipeline, comptime N: usize, args: [N][]const u8) !void {
        try self.client.writeCommand(N, args);
        self.count += 1;
    }

    pub fn set(self: *Pipeline, key: []const u8, value: []const u8) !void {
        try self.command(3, .{ "SET", key, value });
    }

    pub fn get(self: *Pipeline, key: []const u8) !void {
        try self.command(2, .{ "GET", key });
    }

    pub fn hset(self: *Pipeline, key: []const u8, field: []const u8, value: []const u8) !void {
        try self.command(4, .{ "HSET", key, field, value });
    }

    pub fn hget(self: *Pipeline, key: []const u8, field: []const u8) !void {
        try self.command(3, .{ "HGET", key, field });
    }

    /// Sends all queued commands and reads one reply for each.
    /// A Redis error reply is recorded as `.err` and does not stop the batch.
    /// Only I/O and protocol failures make this return an error, after which the
    /// connection should be discarded.
    pub fn exec(self: *Pipeline) !Replies {
        const count = self.count;
        self.count = 0;

        try self.client.writer.interface.flush();

        var arena = std.heap.ArenaAllocator.init(self.client.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();

        const items = try allocator.alloc(Reply, count);
        for (items) |*item| item.* = try self.client.readReply(allocator);

        return .{ .arena = arena, .items = items };
    }
};

pub const Client = RedisClient;
