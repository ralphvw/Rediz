const std = @import("std");

pub fn buildCommand(command: []const u8, args: []const []const u8) ![]const u8 {
    var result = std.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();
    const buf: []u8 = undefined;

    try result.appendSlice(try std.fmt.bufPrint(buf, "*{d}\r\n", .{args.len + 1}));
    try result.appendSlice(try std.fmt.bufPrint(buf, "${d}\r\n{s}\r\n", .{ command.len, command }));
    for (args) |arg| {
        try result.appendSlice(try std.fmt.bufPrint(buf, "${d}\r\n{s}\r\n", .{ arg.len, arg }));
    }

    return result.toOwnedSlice();
}
