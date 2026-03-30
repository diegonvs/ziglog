const std = @import("std");

pub const Level = enum(u8) {
    trace = 10,
    debug = 20,
    info = 30,
    warn = 40,
    err = 50,
    fatal = 60,

    pub fn value(self: Level) u8 {
        return @intFromEnum(self);
    }

    pub fn fromString(s: []const u8) ?Level {
        if (std.mem.eql(u8, s, "trace")) return .trace;
        if (std.mem.eql(u8, s, "debug")) return .debug;
        if (std.mem.eql(u8, s, "info")) return .info;
        if (std.mem.eql(u8, s, "warn")) return .warn;
        if (std.mem.eql(u8, s, "error")) return .err;
        if (std.mem.eql(u8, s, "fatal")) return .fatal;
        return null;
    }

    pub fn label(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info  => "INFO ",
            .warn  => "WARN ",
            .err   => "ERROR",
            .fatal => "FATAL",
        };
    }

    pub fn fromValue(v: u8) Level {
        if (v >= 60) return .fatal;
        if (v >= 50) return .err;
        if (v >= 40) return .warn;
        if (v >= 30) return .info;
        if (v >= 20) return .debug;
        return .trace;
    }
};

test "fromString recognizes all levels" {
    try std.testing.expectEqual(Level.trace, Level.fromString("trace").?);
    try std.testing.expectEqual(Level.debug, Level.fromString("debug").?);
    try std.testing.expectEqual(Level.info,  Level.fromString("info").?);
    try std.testing.expectEqual(Level.warn,  Level.fromString("warn").?);
    try std.testing.expectEqual(Level.err,   Level.fromString("error").?);
    try std.testing.expectEqual(Level.fatal, Level.fromString("fatal").?);
}

test "fromString returns null for invalid string" {
    try std.testing.expect(Level.fromString("unknown") == null);
    try std.testing.expect(Level.fromString("") == null);
}

test "value retorna o inteiro correcto" {
    try std.testing.expectEqual(@as(u8, 10), Level.trace.value());
    try std.testing.expectEqual(@as(u8, 30), Level.info.value());
    try std.testing.expectEqual(@as(u8, 50), Level.err.value());
}

test "fromValue maps to the correct level" {
    try std.testing.expectEqual(Level.trace, Level.fromValue(0));
    try std.testing.expectEqual(Level.trace, Level.fromValue(10));
    try std.testing.expectEqual(Level.info,  Level.fromValue(30));
    try std.testing.expectEqual(Level.err,   Level.fromValue(50));
    try std.testing.expectEqual(Level.fatal, Level.fromValue(60));
    try std.testing.expectEqual(Level.fatal, Level.fromValue(99));
}
