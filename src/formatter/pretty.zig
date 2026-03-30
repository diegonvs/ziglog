const std = @import("std");
const level_mod = @import("../level.zig");

/// ANSI escape codes for terminal colors.
const reset = "\x1b[0m";
const dim = "\x1b[2m";
const red = "\x1b[31m";
const yellow = "\x1b[33m";
const green = "\x1b[32m";
const bold = "\x1b[1m";

pub const LogEntry = struct {
    ts: i64,
    level: u8 = 30,
    msg: []const u8,
};

/// Formats and prints a log entry with colors and a human-readable timestamp.
///
/// Output: [HH:MM:SS] LEVEL <colored message>
pub fn print(entry: LogEntry) void {
    const hms = toHMS(entry.ts);
    const color = levelColor(entry.level);
    const lbl = level_mod.Level.fromValue(entry.level).label();
    const stdout = std.fs.File.stdout();
    stdout.writeAll(dim) catch return;
    var time_buf: [16]u8 = undefined;
    const time_str = std.fmt.bufPrint(&time_buf, "[{d:0>2}:{d:0>2}:{d:0>2}]", .{
        hms.h, hms.m, hms.s,
    }) catch return;
    stdout.writeAll(time_str) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll(" ") catch return;
    stdout.writeAll(color) catch return;
    stdout.writeAll(lbl) catch return;
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

/// Returns the ANSI color for a numeric log level.
fn levelColor(lv: u8) []const u8 {
    if (lv >= 60) return bold ++ red;
    if (lv >= 50) return bold ++ red;
    if (lv >= 40) return yellow;
    if (lv >= 30) return green;
    return dim;
}

test "levelColor error/fatal returns bold red" {
    try std.testing.expectEqualStrings(bold ++ red, levelColor(50));
    try std.testing.expectEqualStrings(bold ++ red, levelColor(60));
}

test "levelColor warn returns yellow" {
    try std.testing.expectEqualStrings(yellow, levelColor(40));
}

test "levelColor info returns green" {
    try std.testing.expectEqualStrings(green, levelColor(30));
}

test "levelColor debug/trace returns dim" {
    try std.testing.expectEqualStrings(dim, levelColor(20));
    try std.testing.expectEqualStrings(dim, levelColor(10));
}

test "toHMS converts timestamp correctly" {
    const t0 = toHMS(0);
    try std.testing.expectEqual(@as(u5, 0), t0.h);
    try std.testing.expectEqual(@as(u6, 0), t0.m);
    try std.testing.expectEqual(@as(u6, 0), t0.s);

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
