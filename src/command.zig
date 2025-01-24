const std = @import("std");

pub fn buildCommand(command: []const u8, args: [][]const u8) []u8 {
    var result = std.mem.ArrayList(u8).init(std.heap.page_allocator);
    defer result.deinit();

    try result.appendFmt("*{d}\r\n", args.len + 1);
    try result.appendFmt("${d}\r\n{s}\r\n", command.len, command);
    for (args) |arg| {
        try result.appendFmt("${d}\r\n{s}\r\n", arg.len, arg);
    }

    return result.toOwnedSlice();
}
