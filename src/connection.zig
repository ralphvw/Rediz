const std = @import("std");

pub const Connection = struct {
    stream: std.net.Stream,
    allocator: *std.mem.Allocator,

    pub fn connect(allocator: *std.mem.Allocator, address: []const u8, port: u16) !Connection {
        const stream = try std.net.Stream.initConnect(.{
            .address = .{
                .ip = try std.net.Address.parseIp4(address),
                .port = port,
            },
        });
        return Connection{ .stream = stream, .allocator = allocator };
    }

    pub fn close(self: Connection) void {
        self.stream.deinit();
    }
};
