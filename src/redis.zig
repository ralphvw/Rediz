const std = @import("std");
const net = std.net;
const mem = std.mem;
const Uri = std.Uri;

pub const RedisClient = struct {
    stream: net.Stream,
    allocator: mem.Allocator,

    const Self = @This();

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

    pub fn disconnect(self: *Self) void {
        self.stream.close();
    }

    fn sendCommand(self: *Self, args: []const []const u8) !void {
        var writer = self.stream.writer();
        std.debug.print("Sending command: ", .{});
        for (args, 0..) |arg, i| {
            std.debug.print("{s}", .{arg});
            if (i < args.len - 1) std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});
        try writer.print("*{d}\r\n", .{args.len});
        for (args) |arg| {
            try writer.print("${d}\r\n", .{arg.len});
            try writer.writeAll(arg);
            try writer.writeAll("\r\n");
        }
    }

    fn readSimpleString(self: *Self) ![]const u8 {
        var reader = self.stream.reader();
        const line = try reader.readUntilDelimiterAlloc(self.allocator, '\r', 1024);
        // skip bytes if line string starts with '\n'
        if (line.len > 0 and line[0] == '\n') {
            const new_line = try self.allocator.alloc(u8, line.len - 1);
            std.mem.copyForwards(u8, new_line, line[1..]);
            self.allocator.free(line);
            return new_line;
        }
        // try reader.skipBytes(1, .{}); // skip '\n'
        std.debug.print("Simple string raw: \"{s}\"\n", .{line});
        return line;
    }

    fn readBulkString(self: *Self) !?[]const u8 {
        var reader = self.stream.reader();
        const len = try reader.readUntilDelimiterAlloc(self.allocator, '\r', 1024);
        defer self.allocator.free(len);
        if (containsChar(len, '-')) {
            return null;
        }

        const length = try std.fmt.parseInt(usize, len[2..], 10);
        if (length == -1) return null;

        var data = try self.allocator.alloc(u8, length + 1);
        errdefer self.allocator.free(data);
        try reader.readNoEof(data);
        try reader.skipBytes(2, .{});
        if (data.len > 0 and data[0] == '\n') {
            const new_data = try self.allocator.alloc(u8, data.len - 1);
            std.mem.copyForwards(u8, new_data, data[1..]);
            self.allocator.free(data);
            std.debug.print("Response after get: {s}\n", .{new_data});
            return new_data;
        }

        return data;
    }

    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        try self.sendCommand(&[_][]const u8{ "SET", key, value });
        const response = try self.readSimpleString();
        std.debug.print("Response: {s}", .{response});
        defer self.allocator.free(response);
        if (!mem.eql(u8, response, "+OK")) {
            return error.RedisError;
        }
    }

    pub fn get(self: *Self, key: []const u8) !?[]const u8 {
        try self.sendCommand(&[_][]const u8{ "GET", key });
        return try self.readBulkString();
    }

    fn auth(self: *Self, password: []const u8) !void {
        try self.sendCommand(&[_][]const u8{ "AUTH", password });
        const response = try self.readSimpleString();
        defer self.allocator.free(response);
        if (!mem.eql(u8, response, "+OK")) {
            return error.AuthFailed;
        }
    }

    pub fn select(self: *Self, db: u8) !void {
        var buf: [16]u8 = undefined;
        const db_str = try std.fmt.bufPrint(&buf, "{}", .{db});
        try self.sendCommand(&[_][]const u8{ "SELECT", db_str });
        const response = try self.readSimpleString();
        defer self.allocator.free(response);
        if (!mem.eql(u8, response, "+OK")) {
            return error.SelectFailed;
        }
    }

    fn containsChar(input: []const u8, target: u8) bool {
        for (input) |char| {
            if (char == target) {
                return true;
            }
        }
        return false;
    }
};
