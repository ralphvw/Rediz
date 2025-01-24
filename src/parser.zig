const std = @import("std");

pub fn parseResponse(buffer: []u8) ![]const u8 {
    if (buffer.len == 0) {
        return error.EmptyBuffer;
    }

    switch (buffer[0]) {
        '+' => return parseSimpleString(buffer),
        '-' => return parseError(buffer),
        ':' => return parseInteger(buffer),
        '$' => return parseBulkString(buffer),
        '*' => return parseArray(buffer),
        else => return error.InvalidResponseType,
    }
}

fn parseSimpleString(buffer: []u8) ![]const u8 {
    const end = std.mem.indexOf(u8, buffer, '\r') orelse return error.MalformedResponse;
    return buffer[1..end];
}

fn parseError(buffer: []u8) ![]const u8 {
    const end = std.mem.indexOf(u8, buffer, '\r') orelse return error.MalformedResponse;
    return buffer[1..end];
}

fn parseInteger(buffer: []u8) ![]const u8 {
    const end = std.mem.indexOf(u8, buffer, '\r') orelse return error.MalformedResponse;
    const value = buffer[1..end];
    // Optionally parse as an integer if needed:
    // const intValue = try std.fmt.parseInt(i64, value, 10);
    return value;
}

fn parseBulkString(buffer: []u8) ![]const u8 {
    const lengthEnd = std.mem.indexOf(u8, buffer, '\r') orelse return error.MalformedResponse;
    const lengthStr = buffer[1..lengthEnd];
    const length = try std.fmt.parseInt(i64, lengthStr, 10);

    if (length == -1) {
        // Null bulk string
        return null;
    }

    const dataStart = lengthEnd + 2;
    const dataEnd = dataStart + @as(usize, @intCast(length));

    if (dataEnd + 2 > buffer.len or std.mem.eql([]u8, buffer[dataEnd .. dataEnd + 2], "\r\n")) {
        return error.MalformedResponse;
    }

    return buffer[dataStart..dataEnd];
}

fn parseArray(buffer: []u8) ![]const u8 {
    const lengthEnd = std.mem.indexOf(u8, buffer, '\r') orelse return error.MalformedResponse;
    const lengthStr = buffer[1..lengthEnd];
    const length = try std.fmt.parseInt(i64, lengthStr, 10);

    if (length == -1) {
        // Null array
        return null;
    }

    var result = std.mem.ArrayList([]const u8).init(std.heap.page_allocator);
    defer result.deinit();

    var cursor = lengthEnd + 2;

    for (0..length) |_| {
        const subBuffer = buffer[cursor..];
        const element = try parseResponse(subBuffer);
        try result.append(element);

        // Move cursor forward based on element size
        const elementSize = element.len + 2; // Include CRLF
        cursor += elementSize;
    }

    return result.toOwnedSlice();
}
