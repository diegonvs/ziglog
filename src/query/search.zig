const std = @import("std");
const pretty = @import("../formatter/pretty.zig");

const LogEntry = pretty.LogEntry;

/// Returns true if `entry.msg` contains `query` (case-sensitive).
/// Kept as a pure function (no I/O) for testability.
pub fn matches(entry: LogEntry, query: []const u8) bool {
    return std.mem.indexOf(u8, entry.msg, query) != null;
}

/// Counts how many entries in a JSONL file match `query`.
/// Testable without capturing stdout.
pub fn countMatches(allocator: std.mem.Allocator, file: std.fs.File, query: []const u8) !usize {
    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    var count: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (matches(parsed.value, query)) count += 1;
    }
    return count;
}

/// Reads the JSONL file line by line, parses each entry,
/// and prints the ones that contain `query`.
pub fn run(allocator: std.mem.Allocator, path: []const u8, query: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            pretty.printWarn("No logs found. Use 'ziglog start' first.");
            return;
        },
        else => return err,
    };
    defer file.close();

    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);

    var found: usize = 0;

    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;

        // Skip lines we cannot parse (corrupted file, etc.)
        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        if (matches(parsed.value, query)) {
            pretty.print(parsed.value);
            found += 1;
        }
    }

    if (found == 0) {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "No results for '{s}'.", .{query}) catch "No results.";
        pretty.printWarn(msg);
    }
}

test "matches returns true when query is in the message" {
    const entry = LogEntry{ .ts = 0, .msg = "error: connection refused" };
    try std.testing.expect(matches(entry, "error"));
    try std.testing.expect(matches(entry, "connection"));
}

test "matches returns false when query is not in the message" {
    const entry = LogEntry{ .ts = 0, .msg = "server started" };
    try std.testing.expect(!matches(entry, "error"));
}

test "matches is case-sensitive" {
    const entry = LogEntry{ .ts = 0, .msg = "Error: something failed" };
    try std.testing.expect(!matches(entry, "error")); // lowercase 'e' does not match
    try std.testing.expect(matches(entry, "Error"));
}

test "matches with empty query matches everything" {
    const entry = LogEntry{ .ts = 0, .msg = "any message" };
    try std.testing.expect(matches(entry, ""));
}

test "matches query at the start of the message" {
    const entry = LogEntry{ .ts = 0, .msg = "error at startup" };
    try std.testing.expect(matches(entry, "error"));
}

test "matches query at the end of the message" {
    const entry = LogEntry{ .ts = 0, .msg = "startup error" };
    try std.testing.expect(matches(entry, "error"));
}

test "countMatches reads JSONL file and counts correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"msg\":\"error: timeout\"}\n");
        try file.writeAll("{\"ts\":2,\"msg\":\"server started\"}\n");
        try file.writeAll("{\"ts\":3,\"msg\":\"error: refused\"}\n");
        try file.writeAll("{\"ts\":4,\"msg\":\"info: ready\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error"));
}

test "countMatches skips corrupted lines" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"msg\":\"error ok\"}\n");
        try file.writeAll("corrupted line\n");
        try file.writeAll("{\"ts\":3,\"msg\":\"error too\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error"));
}
