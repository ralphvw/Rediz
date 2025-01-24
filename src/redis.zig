//! Main redis package

const std = @import("std");
const Connection = @import("connection.zig");
const buildCommand = @import("command.zig").buildCommand;
const parseResponse = @import("parser.zig").parseResponse;

pub const Redis = struct {
    connection: Connection,

    pub fn connect(allocator: *std.mem.Allocator, address: []const u8, port: u16) !Redis {
        return Redis{ .connection = try Connection.connect(allocator, address, port) };
    }

    pub fn set(self: *Redis, key: []const u8, value: []const u8) !void {
        const cmd = buildCommand("SET", .{ key, value });
        try self.connection.stream.writer().writeAll(cmd);
        var buffer: [1024]u8 = undefined;
        _ = try self.connection.stream.reader().read(&buffer);
    }

    pub fn get(self: *Redis, key: []const u8) ![]const u8 {
        const cmd = buildCommand("GET", .{key});
        try self.connection.stream.writer().writeAll(cmd);
        var buffer: [1024]u8 = undefined;
        const response = try self.connection.stream.reader().read(&buffer);
        return parseResponse(response);
    }
};
