const std = @import("std");

pub const Connection = struct {
    stream: std.net.Stream,
    allocator: *std.mem.Allocator,

    pub fn connect(allocator: *std.mem.Allocator, address: []const u8, port: u16) !Connection {
        const ipAddress = try std.net.Ip4Address.parse(address, port);
        const stream = try std.net.tcpConnectToAddress(.{ .in = ipAddress });
        return Connection{ .stream = stream, .allocator = allocator };
    }

    pub fn close(self: Connection) void {
        self.stream.deinit();
    }
};
