const std = @import("std");

pub const ParseError = error{InvalidDuration};

/// Parses a duration string like "5m", "1h", "2d", "30s" and returns seconds.
/// Supported units: s (seconds), m (minutes), h (hours), d (days).
pub fn parseDuration(s: []const u8) ParseError!i64 {
    if (s.len < 2) return error.InvalidDuration;
    const unit = s[s.len - 1];
    const num_str = s[0 .. s.len - 1];
    const num = std.fmt.parseInt(i64, num_str, 10) catch return error.InvalidDuration;
    if (num <= 0) return error.InvalidDuration;
    return switch (unit) {
        's' => num,
        'm' => num * 60,
        'h' => num * 3600,
        'd' => num * 86400,
        else => error.InvalidDuration,
    };
}

test "parseDuration seconds" {
    try std.testing.expectEqual(@as(i64, 30), try parseDuration("30s"));
}

test "parseDuration minutes" {
    try std.testing.expectEqual(@as(i64, 300), try parseDuration("5m"));
}

test "parseDuration hours" {
    try std.testing.expectEqual(@as(i64, 3600), try parseDuration("1h"));
}

test "parseDuration days" {
    try std.testing.expectEqual(@as(i64, 172800), try parseDuration("2d"));
}

test "parseDuration invalid unit" {
    try std.testing.expectError(error.InvalidDuration, parseDuration("5x"));
}

test "parseDuration non-numeric prefix" {
    try std.testing.expectError(error.InvalidDuration, parseDuration("abch"));
}

test "parseDuration zero is invalid" {
    try std.testing.expectError(error.InvalidDuration, parseDuration("0m"));
}

test "parseDuration too short" {
    try std.testing.expectError(error.InvalidDuration, parseDuration("m"));
}
