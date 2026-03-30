const std = @import("std");
const level_mod = @import("../level.zig");
const duration = @import("../time/duration.zig");

pub const StartOptions = struct {
    level: u8 = 30,
};

pub const FindOptions = struct {
    query: []const u8,
    min_level: u8 = 0,
    /// Unix timestamp (seconds): only show entries at or after this time.
    since: ?i64 = null,
    /// Unix timestamp (seconds): only show entries at or before this time.
    until: ?i64 = null,
};

pub const Command = union(enum) {
    start: StartOptions,
    find: FindOptions,
    tail,
};

pub const ParseError = error{
    NoCommand,
    UnknownCommand,
    MissingArgument,
    InvalidLevel,
    InvalidDuration,
};

/// Receives arguments (without the executable name) and returns the Command.
pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return error.NoCommand;

    const cmd = args[0];

    if (std.mem.eql(u8, cmd, "start")) {
        var opts = StartOptions{};
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--level")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                const lv = level_mod.Level.fromString(args[i]) orelse return error.InvalidLevel;
                opts.level = lv.value();
            }
        }
        return .{ .start = opts };
    }

    if (std.mem.eql(u8, cmd, "find")) {
        if (args.len < 2) return error.MissingArgument;
        var opts = FindOptions{ .query = args[1] };
        const now = std.time.timestamp();
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--level")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                const lv = level_mod.Level.fromString(args[i]) orelse return error.InvalidLevel;
                opts.min_level = lv.value();
            } else if (std.mem.eql(u8, args[i], "--since")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                const secs = duration.parseDuration(args[i]) catch return error.InvalidDuration;
                opts.since = now - secs;
            } else if (std.mem.eql(u8, args[i], "--until")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                if (duration.parseDuration(args[i])) |secs| {
                    opts.until = now - secs;
                } else |_| {
                    opts.until = std.fmt.parseInt(i64, args[i], 10) catch return error.InvalidDuration;
                }
            }
        }
        return .{ .find = opts };
    }

    if (std.mem.eql(u8, cmd, "tail")) return .tail;

    return error.UnknownCommand;
}

test "parse start defaults to info level" {
    const cmd = try parse(&.{"start"});
    try std.testing.expectEqual(@as(u8, 30), cmd.start.level);
}

test "parse start --level warn" {
    const cmd = try parse(&.{ "start", "--level", "warn" });
    try std.testing.expectEqual(@as(u8, 40), cmd.start.level);
}

test "parse start --level error" {
    const cmd = try parse(&.{ "start", "--level", "error" });
    try std.testing.expectEqual(@as(u8, 50), cmd.start.level);
}

test "parse start --level invalid returns InvalidLevel" {
    try std.testing.expectError(error.InvalidLevel, parse(&.{ "start", "--level", "unknown" }));
}

test "parse start --level without value returns MissingArgument" {
    try std.testing.expectError(error.MissingArgument, parse(&.{ "start", "--level" }));
}

test "parse find with query" {
    const cmd = try parse(&.{ "find", "error" });
    try std.testing.expectEqualStrings("error", cmd.find.query);
    try std.testing.expectEqual(@as(u8, 0), cmd.find.min_level);
}

test "parse find --level warn" {
    const cmd = try parse(&.{ "find", "timeout", "--level", "warn" });
    try std.testing.expectEqualStrings("timeout", cmd.find.query);
    try std.testing.expectEqual(@as(u8, 40), cmd.find.min_level);
}

test "parse find without argument returns MissingArgument" {
    try std.testing.expectError(error.MissingArgument, parse(&.{"find"}));
}

test "parse find --since sets lower bound" {
    const before = std.time.timestamp();
    const cmd = try parse(&.{ "find", "msg", "--since", "5m" });
    const after = std.time.timestamp();
    const expected_min = before - 5 * 60;
    const expected_max = after - 5 * 60;
    try std.testing.expect(cmd.find.since.? >= expected_min);
    try std.testing.expect(cmd.find.since.? <= expected_max);
    try std.testing.expectEqual(@as(?i64, null), cmd.find.until);
}

test "parse find --until with duration sets upper bound" {
    const before = std.time.timestamp();
    const cmd = try parse(&.{ "find", "msg", "--until", "1h" });
    const after = std.time.timestamp();
    const expected_min = before - 3600;
    const expected_max = after - 3600;
    try std.testing.expect(cmd.find.until.? >= expected_min);
    try std.testing.expect(cmd.find.until.? <= expected_max);
}

test "parse find --until with absolute timestamp" {
    const cmd = try parse(&.{ "find", "msg", "--until", "1700000000" });
    try std.testing.expectEqual(@as(?i64, 1700000000), cmd.find.until);
}

test "parse find --since invalid duration returns InvalidDuration" {
    try std.testing.expectError(error.InvalidDuration, parse(&.{ "find", "msg", "--since", "5x" }));
}

test "parse find --until invalid value returns InvalidDuration" {
    try std.testing.expectError(error.InvalidDuration, parse(&.{ "find", "msg", "--until", "notanumber" }));
}

test "parse tail" {
    const cmd = try parse(&.{"tail"});
    try std.testing.expectEqual(Command.tail, cmd);
}

test "parse without arguments returns NoCommand" {
    try std.testing.expectError(error.NoCommand, parse(&.{}));
}

test "parse unknown command returns UnknownCommand" {
    try std.testing.expectError(error.UnknownCommand, parse(&.{"foo"}));
}
