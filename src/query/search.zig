const std = @import("std");
const pretty = @import("../formatter/pretty.zig");

const LogEntry = pretty.LogEntry;

/// Returns true if `entry` matches the query, meets the minimum level,
/// and falls within the optional [since, until] time window (Unix seconds).
pub fn matches(entry: LogEntry, query: []const u8, min_level: u8, since: ?i64, until: ?i64) bool {
    if (entry.level < min_level) return false;
    if (std.mem.indexOf(u8, entry.msg, query) == null) return false;
    if (since) |s| if (entry.ts < s) return false;
    if (until) |u| if (entry.ts > u) return false;
    return true;
}

/// Counts how many entries in a JSONL file match `query` at or above `min_level`
/// and within the optional [since, until] time window.
/// Testable without capturing stdout.
pub fn countMatches(allocator: std.mem.Allocator, file: std.fs.File, query: []const u8, min_level: u8, since: ?i64, until: ?i64) !usize {
    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    var count: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (matches(parsed.value, query, min_level, since, until)) count += 1;
    }
    return count;
}

/// Reads the JSONL file line by line, parses each entry, and prints those
/// that contain `query` at or above `min_level` and within the time window.
pub fn run(allocator: std.mem.Allocator, path: []const u8, query: []const u8, min_level: u8, since: ?i64, until: ?i64) !void {
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

        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        if (matches(parsed.value, query, min_level, since, until)) {
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

test "matches returns true when query is in message and level is sufficient" {
    const entry = LogEntry{ .ts = 0, .level = 50, .msg = "error: connection refused" };
    try std.testing.expect(matches(entry, "error", 0, null, null));
    try std.testing.expect(matches(entry, "error", 50, null, null));
}

test "matches returns false when level is below min_level" {
    const entry = LogEntry{ .ts = 0, .level = 30, .msg = "info: started" };
    try std.testing.expect(!matches(entry, "info", 40, null, null));
}

test "matches returns false when query is not in message" {
    const entry = LogEntry{ .ts = 0, .level = 30, .msg = "server started" };
    try std.testing.expect(!matches(entry, "error", 0, null, null));
}

test "matches is case-sensitive" {
    const entry = LogEntry{ .ts = 0, .level = 50, .msg = "Error: something failed" };
    try std.testing.expect(!matches(entry, "error", 0, null, null));
    try std.testing.expect(matches(entry, "Error", 0, null, null));
}

test "matches with empty query matches everything at sufficient level" {
    const entry = LogEntry{ .ts = 0, .level = 30, .msg = "any message" };
    try std.testing.expect(matches(entry, "", 0, null, null));
    try std.testing.expect(matches(entry, "", 30, null, null));
    try std.testing.expect(!matches(entry, "", 40, null, null));
}

test "matches filters by since" {
    const entry = LogEntry{ .ts = 1000, .level = 30, .msg = "msg" };
    try std.testing.expect(matches(entry, "msg", 0, 900, null));
    try std.testing.expect(matches(entry, "msg", 0, 1000, null));
    try std.testing.expect(!matches(entry, "msg", 0, 1001, null));
}

test "matches filters by until" {
    const entry = LogEntry{ .ts = 1000, .level = 30, .msg = "msg" };
    try std.testing.expect(matches(entry, "msg", 0, null, 1100));
    try std.testing.expect(matches(entry, "msg", 0, null, 1000));
    try std.testing.expect(!matches(entry, "msg", 0, null, 999));
}

test "matches filters by since and until window" {
    const inside = LogEntry{ .ts = 1000, .level = 30, .msg = "msg" };
    const before = LogEntry{ .ts = 500, .level = 30, .msg = "msg" };
    const after = LogEntry{ .ts = 2000, .level = 30, .msg = "msg" };
    try std.testing.expect(matches(inside, "msg", 0, 900, 1500));
    try std.testing.expect(!matches(before, "msg", 0, 900, 1500));
    try std.testing.expect(!matches(after, "msg", 0, 900, 1500));
}

test "countMatches reads JSONL and counts correctly" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"level\":50,\"msg\":\"error: timeout\"}\n");
        try file.writeAll("{\"ts\":2,\"level\":30,\"msg\":\"server started\"}\n");
        try file.writeAll("{\"ts\":3,\"level\":50,\"msg\":\"error: refused\"}\n");
        try file.writeAll("{\"ts\":4,\"level\":30,\"msg\":\"info: ready\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error", 0, null, null));
}

test "countMatches filters by min_level" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"level\":30,\"msg\":\"info message\"}\n");
        try file.writeAll("{\"ts\":2,\"level\":40,\"msg\":\"warn message\"}\n");
        try file.writeAll("{\"ts\":3,\"level\":50,\"msg\":\"error message\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "message", 40, null, null));
}

test "countMatches falls back to level=30 for entries without level field" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        // Old-format entry without level field — should default to 30 (info)
        try file.writeAll("{\"ts\":1,\"msg\":\"legacy entry\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 1), try countMatches(allocator, file, "legacy", 0, null, null));
    const file2 = try tmp.dir.openFile("log.jsonl", .{});
    defer file2.close();
    try std.testing.expectEqual(@as(usize, 0), try countMatches(allocator, file2, "legacy", 40, null, null));
}

test "countMatches ignores malformed lines" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"level\":50,\"msg\":\"error ok\"}\n");
        try file.writeAll("corrupted line\n");
        try file.writeAll("{\"ts\":3,\"level\":50,\"msg\":\"error too\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error", 0, null, null));
}

test "countMatches filters by since and until" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":100,\"level\":30,\"msg\":\"old entry\"}\n");
        try file.writeAll("{\"ts\":500,\"level\":30,\"msg\":\"mid entry\"}\n");
        try file.writeAll("{\"ts\":900,\"level\":30,\"msg\":\"new entry\"}\n");
    }

    {
        const file = try tmp.dir.openFile("log.jsonl", .{});
        defer file.close();
        try std.testing.expectEqual(@as(usize, 1), try countMatches(allocator, file, "entry", 0, 400, 700));
    }
    {
        const file = try tmp.dir.openFile("log.jsonl", .{});
        defer file.close();
        try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "entry", 0, 400, null));
    }
    {
        const file = try tmp.dir.openFile("log.jsonl", .{});
        defer file.close();
        try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "entry", 0, null, 700));
    }
}
