const std = @import("std");
const parser = @import("cli/parser.zig");
const writer = @import("storage/writer.zig");
const ingest = @import("ingest/stdin_reader.zig");
const search = @import("query/search.zig");

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
            error.NoCommand => std.debug.print("Uso: ziglog <start|find <query>|tail>\n", .{}),
            error.UnknownCommand => std.debug.print("Comando desconhecido. Use: start, find, tail\n", .{}),
            error.MissingArgument => std.debug.print("Argumento faltando. Uso: ziglog find <query>\n", .{}),
        }
        std.process.exit(1);
    };

    switch (command) {
        .start => {
            const log_writer = try writer.LogWriter.open(log_path);
            defer log_writer.close();
            try ingest.run(allocator, log_writer);
        },
        .find => |query| try search.run(allocator, log_path, query),
        .tail => std.debug.print("TODO: seguir logs\n", .{}),
    }
}
