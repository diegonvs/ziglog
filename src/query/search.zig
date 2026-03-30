const std = @import("std");
const pretty = @import("../formatter/pretty.zig");

const LogEntry = pretty.LogEntry;

/// Returns true if `entry` matches the query and meets the minimum level.
pub fn matches(entry: LogEntry, query: []const u8, min_level: u8) bool {
    return entry.level >= min_level and std.mem.indexOf(u8, entry.msg, query) != null;
}

/// Counts how many entries in a JSONL file match `query` at or above `min_level`.
/// Testable without capturing stdout.
pub fn countMatches(allocator: std.mem.Allocator, file: std.fs.File, query: []const u8, min_level: u8) !usize {
    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    var count: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (matches(parsed.value, query, min_level)) count += 1;
    }
    return count;
}

/// Reads the JSONL file line by line, parses each entry, and prints those
/// that contain `query` at or above `min_level`.
pub fn run(allocator: std.mem.Allocator, path: []const u8, query: []const u8, min_level: u8) !void {
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

        if (matches(parsed.value, query, min_level)) {
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
    try std.testing.expect(matches(entry, "error", 0));
    try std.testing.expect(matches(entry, "error", 50));
}

test "matches returns false when level is below min_level" {
    const entry = LogEntry{ .ts = 0, .level = 30, .msg = "info: started" };
    try std.testing.expect(!matches(entry, "info", 40));
}

test "matches returns false when query is not in message" {
    const entry = LogEntry{ .ts = 0, .level = 30, .msg = "server started" };
    try std.testing.expect(!matches(entry, "error", 0));
}

test "matches is case-sensitive" {
    const entry = LogEntry{ .ts = 0, .level = 50, .msg = "Error: something failed" };
    try std.testing.expect(!matches(entry, "error", 0));
    try std.testing.expect(matches(entry, "Error", 0));
}

test "matches with empty query matches everything at sufficient level" {
    const entry = LogEntry{ .ts = 0, .level = 30, .msg = "any message" };
    try std.testing.expect(matches(entry, "", 0));
    try std.testing.expect(matches(entry, "", 30));
    try std.testing.expect(!matches(entry, "", 40));
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

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error", 0));
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

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "message", 40));
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

    try std.testing.expectEqual(@as(usize, 1), try countMatches(allocator, file, "legacy", 0));
    const file2 = try tmp.dir.openFile("log.jsonl", .{});
    defer file2.close();
    try std.testing.expectEqual(@as(usize, 0), try countMatches(allocator, file2, "legacy", 40));
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

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error", 0));
}
