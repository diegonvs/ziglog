const std = @import("std");
const storage = @import("../storage/writer.zig");

/// Reads lines from stdin and writes each one as a log entry with the given level.
pub fn run(allocator: std.mem.Allocator, log_writer: storage.LogWriter, lv: u8) !void {
    var buf: [65536]u8 = undefined;
    var reader = std.fs.File.stdin().readerStreaming(&buf);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        try log_writer.writeEntry(allocator, line, lv);
    }
}
