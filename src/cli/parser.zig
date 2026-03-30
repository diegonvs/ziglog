const std = @import("std");

/// Represents the command the user passed on the command line.
/// `union(enum)` is a tagged union: each variant carries its own type.
pub const Command = union(enum) {
    start,
    find: []const u8, // carries the search query
    tail,
};

pub const ParseError = error{
    NoCommand,
    UnknownCommand,
    MissingArgument,
};

/// Receives argv (without the executable name) and returns a Command.
pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return error.NoCommand;

    const cmd = args[0];

    if (std.mem.eql(u8, cmd, "start")) {
        return .start;
    } else if (std.mem.eql(u8, cmd, "find")) {
        if (args.len < 2) return error.MissingArgument;
        return .{ .find = args[1] };
    } else if (std.mem.eql(u8, cmd, "tail")) {
        return .tail;
    }

    return error.UnknownCommand;
}

test "parse start command" {
    const cmd = try parse(&.{"start"});
    try std.testing.expectEqual(Command.start, cmd);
}

test "parse find command with query" {
    const cmd = try parse(&.{ "find", "error" });
    try std.testing.expectEqualStrings("error", cmd.find);
}

test "find without argument returns MissingArgument" {
    try std.testing.expectError(error.MissingArgument, parse(&.{"find"}));
}

test "parse tail command" {
    const cmd = try parse(&.{"tail"});
    try std.testing.expectEqual(Command.tail, cmd);
}

test "no arguments returns NoCommand" {
    try std.testing.expectError(error.NoCommand, parse(&.{}));
}

test "unknown command returns UnknownCommand" {
    try std.testing.expectError(error.UnknownCommand, parse(&.{"foo"}));
}
