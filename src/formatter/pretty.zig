const std = @import("std");

/// ANSI escape codes for terminal colors.
const reset = "\x1b[0m";
const dim = "\x1b[2m";
const red = "\x1b[31m";
const yellow = "\x1b[33m";
const green = "\x1b[32m";
const bold = "\x1b[1m";

pub const LogEntry = struct {
    ts: i64,
    msg: []const u8,
};

/// Formats and prints a log entry with colors and a human-readable timestamp.
///
/// Output: [HH:MM:SS] <colored message>
/// The message color is chosen based on keywords (case-insensitive).
pub fn print(entry: LogEntry) void {
    const hms = toHMS(entry.ts);
    const color = levelColor(entry.msg);
    const stdout = std.fs.File.stdout();
    stdout.writeAll(dim) catch return;
    // std.fmt.bufPrint builds the string on the stack without heap allocation
    var time_buf: [16]u8 = undefined;
    const time_str = std.fmt.bufPrint(&time_buf, "[{d:0>2}:{d:0>2}:{d:0>2}]", .{
        hms.h, hms.m, hms.s,
    }) catch return;
    stdout.writeAll(time_str) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll(" ") catch return;
    stdout.writeAll(color) catch return;
    stdout.writeAll(entry.msg) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll("\n") catch return;
}

/// Prints a system message (not a log entry).
/// Used for "Waiting for new logs..." and similar notices.
pub fn printInfo(msg: []const u8) void {
    const stdout = std.fs.File.stdout();
    stdout.writeAll(dim) catch return;
    stdout.writeAll(msg) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll("\n") catch return;
}

/// Prints a warning/error message from ziglog itself.
pub fn printWarn(msg: []const u8) void {
    const stdout = std.fs.File.stdout();
    stdout.writeAll(yellow) catch return;
    stdout.writeAll(msg) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll("\n") catch return;
}

// --- Internal functions ---

const HMS = struct { h: u5, m: u6, s: u6 };

/// Converts a Unix timestamp (seconds) to hour/minute/second (UTC).
/// Uses `std.time.epoch.EpochSeconds` to decompose the value.
fn toHMS(ts: i64) HMS {
    const secs: u64 = @intCast(@max(0, ts));
    const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
    const day = epoch.getDaySeconds();
    return .{
        .h = day.getHoursIntoDay(),
        .m = day.getMinutesIntoHour(),
        .s = day.getSecondsIntoMinute(),
    };
}

/// Picks an ANSI color based on keywords in the message.
fn levelColor(msg: []const u8) []const u8 {
    if (containsIgnoreCase(msg, "error") or
        containsIgnoreCase(msg, "fatal") or
        containsIgnoreCase(msg, "panic"))
        return bold ++ red;
    if (containsIgnoreCase(msg, "warn"))
        return yellow;
    if (containsIgnoreCase(msg, "info") or
        containsIgnoreCase(msg, "start") or
        containsIgnoreCase(msg, "ready"))
        return green;
    return reset;
}

/// Searches for `needle` in `haystack` ignoring case.
/// Compares byte by byte using `std.ascii.toLower`.
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != needle[j]) break;
        } else return true;
    }
    return false;
}

test "levelColor detects error" {
    try std.testing.expectEqualStrings(bold ++ red, levelColor("error: connection refused"));
    try std.testing.expectEqualStrings(bold ++ red, levelColor("ERROR: disk full"));
}

test "levelColor detects warn" {
    try std.testing.expectEqualStrings(yellow, levelColor("warn: retry"));
    try std.testing.expectEqualStrings(yellow, levelColor("WARNING: high memory"));
}

test "levelColor detects info/start/ready" {
    try std.testing.expectEqualStrings(green, levelColor("server started"));
    try std.testing.expectEqualStrings(green, levelColor("ready to accept connections"));
}

test "levelColor default with no keyword" {
    try std.testing.expectEqualStrings(reset, levelColor("something happened"));
}

test "toHMS converts timestamp correctly" {
    // Unix epoch: 1970-01-01 00:00:00
    const t0 = toHMS(0);
    try std.testing.expectEqual(@as(u5, 0), t0.h);
    try std.testing.expectEqual(@as(u6, 0), t0.m);
    try std.testing.expectEqual(@as(u6, 0), t0.s);

    // 1970-01-01 01:02:03 = 3723 seconds
    const t1 = toHMS(3723);
    try std.testing.expectEqual(@as(u5, 1), t1.h);
    try std.testing.expectEqual(@as(u6, 2), t1.m);
    try std.testing.expectEqual(@as(u6, 3), t1.s);
}

test "toHMS handles negative timestamp without panic" {
    const t = toHMS(-1);
    _ = t;
}

test "toHMS last second of day (23:59:59 = 86399s)" {
    const t = toHMS(86399);
    try std.testing.expectEqual(@as(u5, 23), t.h);
    try std.testing.expectEqual(@as(u6, 59), t.m);
    try std.testing.expectEqual(@as(u6, 59), t.s);
}

test "containsIgnoreCase matches partial substrings" {
    try std.testing.expect(containsIgnoreCase("FATAL error occurred", "fatal"));
    try std.testing.expect(containsIgnoreCase("FATAL error occurred", "error"));
    try std.testing.expect(containsIgnoreCase("FATAL error occurred", "occurred"));
}

test "containsIgnoreCase returns false when needle is longer than haystack" {
    try std.testing.expect(!containsIgnoreCase("hi", "hello"));
}

test "containsIgnoreCase with equal strings" {
    try std.testing.expect(containsIgnoreCase("error", "error"));
    try std.testing.expect(containsIgnoreCase("ERROR", "error"));
}

test "levelColor empty message returns default" {
    try std.testing.expectEqualStrings(reset, levelColor(""));
}

test "levelColor detects panic" {
    try std.testing.expectEqualStrings(bold ++ red, levelColor("panic: index out of bounds"));
}
