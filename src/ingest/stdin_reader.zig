const std = @import("std");
const storage = @import("../storage/writer.zig");

/// Reads lines from stdin and writes each one as a log entry.
///
/// In Zig 0.15, the reader requires an explicit buffer — it serves as
/// the internal buffer for efficient reads (reads OS blocks instead of
/// one byte at a time). `readerStreaming` is used because stdin is a
/// sequential stream with no support for positional reads.
///
/// `takeDelimiter('\n')` returns:
///   - a slice of the line (without the '\n') while there is data
///   - `null` when EOF is reached with no remaining bytes
pub fn run(allocator: std.mem.Allocator, log_writer: storage.LogWriter) !void {
    var buf: [65536]u8 = undefined;
    var reader = std.fs.File.stdin().readerStreaming(&buf);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        try log_writer.writeEntry(allocator, line);
    }
}
