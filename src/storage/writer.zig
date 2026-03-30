const std = @import("std");

const Entry = struct { ts: i64, level: u8, msg: []const u8 };

pub const LogWriter = struct {
    file: std.fs.File,

    /// Opens (or creates) the log file in append mode.
    pub fn open(path: []const u8) !LogWriter {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        try file.seekFromEnd(0);
        return .{ .file = file };
    }

    pub fn close(self: LogWriter) void {
        self.file.close();
    }

    /// Serializes the message and level as a JSON line and writes to the file.
    /// Example output: {"ts":1234567890,"level":30,"msg":"hello world"}
    pub fn writeEntry(self: LogWriter, allocator: std.mem.Allocator, message: []const u8, lv: u8) !void {
        const ts = std.time.timestamp();
        const json = try std.json.Stringify.valueAlloc(allocator, .{ .ts = ts, .level = lv, .msg = message }, .{});
        defer allocator.free(json);
        try self.file.writeAll(json);
        try self.file.writeAll("\n");
    }
};

test "writeEntry produces JSON with correct msg and level" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "hello world", 30);
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.NoLine;

    const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello world", parsed.value.msg);
    try std.testing.expectEqual(@as(u8, 30), parsed.value.level);
    try std.testing.expect(parsed.value.ts > 0);
}

test "writeEntry escapes special characters in JSON" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "msg with \"quotes\" and \\backslash", 20);
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.NoLine;

    const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("msg with \"quotes\" and \\backslash", parsed.value.msg);
}

test "writeEntry accumulates multiple entries (append mode)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "first", 10);
        try lw.writeEntry(allocator, "second", 30);
        try lw.writeEntry(allocator, "third", 50);
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);

    var count: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
        defer parsed.deinit();
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}
