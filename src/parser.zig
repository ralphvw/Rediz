const std = @import("std");

const Errors = error{
    InvalidInput,
};

pub fn parseResponse(buffer: []const u8) ![]const u8 {
    if (buffer.len == 0) {
        return error.EmptyBuffer;
    }

    switch (buffer[0]) {
        '+' => return parseSimpleString(buffer),
        '-' => return parseError(buffer),
        ':' => return parseInteger(buffer),
        else => return error.InvalidResponseType,
    }
}

fn parseSimpleString(buffer: []const u8) ![]const u8 {
    const end = std.mem.indexOf(u8, buffer, "\r") orelse return error.MalformedResponse;
    return buffer[1..end];
}

fn parseError(buffer: []const u8) ![]const u8 {
    const end = std.mem.indexOf(u8, buffer, "\r") orelse return error.MalformedResponse;
    return buffer[1..end];
}

fn parseInteger(buffer: []const u8) ![]const u8 {
    const end = std.mem.indexOf(u8, buffer, "\r") orelse return error.MalformedResponse;
    const value = buffer[1..end];
    // Optionally parse as an integer if needed:
    // const intValue = try std.fmt.parseInt(i64, value, 10);
    return value;
}
