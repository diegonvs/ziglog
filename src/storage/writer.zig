const std = @import("std");

/// Internal struct used to parse written entries back in tests.
const Entry = struct { ts: i64, msg: []const u8 };

pub const LogWriter = struct {
    file: std.fs.File,

    /// Opens (or creates) the log file in append mode.
    /// `createFile` with `truncate = false` creates the file if it does not
    /// exist, or opens it without clearing its contents if it already does.
    pub fn open(path: []const u8) !LogWriter {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        try file.seekFromEnd(0);
        return .{ .file = file };
    }

    pub fn close(self: LogWriter) void {
        self.file.close();
    }

    /// Serializes the message as a JSON line and writes it to the file.
    /// Example output: {"ts":1234567890,"msg":"server started"}
    ///
    /// `valueAlloc` serializes the value to a heap-allocated JSON string.
    /// `file.writeAll` writes the bytes directly to the file.
    pub fn writeEntry(self: LogWriter, allocator: std.mem.Allocator, message: []const u8) !void {
        const ts = std.time.timestamp();
        const json = try std.json.Stringify.valueAlloc(allocator, .{ .ts = ts, .msg = message }, .{});
        defer allocator.free(json);
        try self.file.writeAll(json);
        try self.file.writeAll("\n");
    }
};

// --- Tests ---
//
// `std.testing.tmpDir(.{})` creates an isolated temporary directory under
// `.zig-cache/tmp/<hash>/`, cleaned up automatically on `tmp.cleanup()`.
// We construct `LogWriter` directly via the public `file` field so we can
// point it at a file inside the temp dir without going through `cwd()`.

test "writeEntry produces JSON with correct msg field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "hello world");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.NoLine;

    const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello world", parsed.value.msg);
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
        try lw.writeEntry(allocator, "msg with \"quotes\" and \\backslash");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.NoLine;

    const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
    defer parsed.deinit();
    // std.json.parseFromSlice unescapes — we recover the original string
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
        try lw.writeEntry(allocator, "first");
        try lw.writeEntry(allocator, "second");
        try lw.writeEntry(allocator, "third");
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
