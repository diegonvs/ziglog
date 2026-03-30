const std = @import("std");
const parser = @import("cli/parser.zig");
const writer = @import("storage/writer.zig");
const ingest = @import("ingest/stdin_reader.zig");
const search = @import("query/search.zig");
const tailer = @import("tail/tailer.zig");

const log_path = "ziglog.jsonl";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cmd_args: []const []const u8 = if (args.len > 1) args[1..] else &.{};

    const command = parser.parse(cmd_args) catch |err| {
        switch (err) {
            error.NoCommand => std.debug.print("Usage: ziglog <start|find <query>|tail>\n", .{}),
            error.UnknownCommand => std.debug.print("Unknown command. Use: start, find, tail\n", .{}),
            error.MissingArgument => std.debug.print("Missing argument. Usage: ziglog find <query>\n", .{}),
            error.InvalidLevel => std.debug.print("Invalid level. Use: trace, debug, info, warn, error, fatal\n", .{}),
            error.InvalidDuration => std.debug.print("Invalid duration. Use format: 30s, 5m, 1h, 2d\n", .{}),
        }
        std.process.exit(1);
    };

    switch (command) {
        .start => |opts| {
            const log_writer = try writer.LogWriter.open(log_path);
            defer log_writer.close();
            try ingest.run(allocator, log_writer, opts.level);
        },
        .find => |opts| try search.run(allocator, log_path, opts.query, opts.min_level, opts.since, opts.until),
        .tail => try tailer.run(allocator, log_path),
    }
}
