const std = @import("std");
const builtin = @import("builtin");
const pretty = @import("../formatter/pretty.zig");

/// Polling interval in nanoseconds (250ms).
const poll_interval_ns: u64 = 250 * std.time.ns_per_ms;

/// Watches the log file and prints new lines as they arrive.
///
/// Polling strategy:
/// 1. Advances to the end of the file on open (does not replay history)
/// 2. Every 250ms checks whether the file size has grown
/// 3. Reads the new bytes and prints them line by line
///
/// `std.Thread.sleep` suspends the thread for the interval without consuming CPU.
pub fn run(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            pretty.printWarn("No logs found. Use 'ziglog start' first.");
            return;
        },
        else => return err,
    };
    defer file.close();

    // Start at end of file — do not replay history
    var pos = try file.getEndPos();

    pretty.printInfo("Waiting for new logs...");

    // `builtin.os.tag` is a comptime value: Zig eliminates non-taken branches
    // without even type-checking them. Each platform compiles only the mechanism
    // it supports.
    if (builtin.os.tag == .macos or builtin.os.tag == .ios or
        builtin.os.tag == .tvos or builtin.os.tag == .watchos)
    {
        try watchKqueue(allocator, file, &pos);
    } else if (builtin.os.tag == .linux) {
        try watchInotify(allocator, file, path, &pos);
    } else {
        try watchPoll(allocator, file, &pos);
    }
}

/// Reads and prints new bytes since `pos.*`.
/// Called by all watch mechanisms after receiving a notification.
fn readNew(allocator: std.mem.Allocator, file: std.fs.File, pos: *u64) !void {
    const end = try file.getEndPos();
    if (end <= pos.*) return;

    // Ensure the reader starts at the correct position,
    // regardless of what happened before.
    try file.seekTo(pos.*);

    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    while (try reader.interface.takeDelimiter('\n')) |raw| {
        if (raw.len == 0) continue;
        const entry = std.json.parseFromSlice(pretty.LogEntry, allocator, raw, .{}) catch continue;
        defer entry.deinit();
        pretty.print(entry.value);
    }
    pos.* = end;
}

/// macOS/BSD: kqueue — kernel event notification mechanism.
/// `EVFILT_VNODE` + `NOTE_WRITE` notifies when the file is written.
/// `EV_CLEAR` clears the event state after each delivery,
/// preventing duplicate notifications.
/// The `kevent(..., null)` call blocks the thread without consuming CPU
/// until the kernel delivers an event.
fn watchKqueue(allocator: std.mem.Allocator, file: std.fs.File, pos: *u64) !void {
    const kq = try std.posix.kqueue();
    defer std.posix.close(kq);

    // Register interest: we want to know when the file is written.
    const change = std.posix.Kevent{
        .ident = @intCast(file.handle),
        .filter = std.c.EVFILT.VNODE,
        .flags = std.c.EV.ADD | std.c.EV.ENABLE | std.c.EV.CLEAR,
        .fflags = std.c.NOTE.WRITE | std.c.NOTE.EXTEND,
        .data = 0,
        .udata = 0,
    };
    _ = try std.posix.kevent(kq, &.{change}, &.{}, null);

    var events: [1]std.posix.Kevent = undefined;
    while (true) {
        // Block until the kernel notifies a change in the file.
        const n = try std.posix.kevent(kq, &.{}, &events, null);
        if (n == 0) continue;
        try readNew(allocator, file, pos);
    }
}

/// Linux: inotify — file event notification subsystem.
/// `IN.MODIFY` notifies when the file content changes.
/// `read` on the inotify fd blocks until events are available.
fn watchInotify(allocator: std.mem.Allocator, file: std.fs.File, path: []const u8, pos: *u64) !void {
    const ifd = try std.posix.inotify_init1(0);
    defer std.posix.close(ifd);
    _ = try std.posix.inotify_add_watch(ifd, path, std.os.linux.IN.MODIFY);

    // Aligned buffer for inotify_event structs.
    var buf: [4096]u8 align(4) = undefined;
    while (true) {
        _ = try std.posix.read(ifd, &buf);
        try readNew(allocator, file, pos);
    }
}

/// Fallback for other systems: polling every 250ms.
fn watchPoll(allocator: std.mem.Allocator, file: std.fs.File, pos: *u64) !void {
    while (true) {
        try readNew(allocator, file, pos);
        std.Thread.sleep(poll_interval_ns);
    }
}
