const std = @import("std");
const level_mod = @import("../level.zig");

pub const StartOptions = struct {
    level: u8 = 30,
};

pub const FindOptions = struct {
    query: []const u8,
    min_level: u8 = 0,
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
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--level")) {
                i += 1;
                if (i >= args.len) return error.MissingArgument;
                const lv = level_mod.Level.fromString(args[i]) orelse return error.InvalidLevel;
                opts.min_level = lv.value();
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
