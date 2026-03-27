const std = @import("std");
const builtin = @import("builtin");
const pretty = @import("../formatter/pretty.zig");

const poll_interval_ns: u64 = 250 * std.time.ns_per_ms;

pub fn run(allocator: std.mem.Allocator, path: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            pretty.printWarn("Nenhum log encontrado. Use 'ziglog start' primeiro.");
            return;
        },
        else => return err,
    };
    defer file.close();

    // Começa no fim — não relê o histórico.
    var pos = try file.getEndPos();

    pretty.printInfo("Aguardando novos logs...");

    // `builtin.os.tag` é um valor comptime: Zig elimina os branches
    // não tomados sem sequer fazer type-check deles. Cada plataforma
    // compila apenas o mecanismo que ela suporta.
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

/// Lê e imprime os bytes novos desde `pos.*`.
/// Chamada por todos os mecanismos de watch após receberem uma notificação.
fn readNew(allocator: std.mem.Allocator, file: std.fs.File, pos: *u64) !void {
    const end = try file.getEndPos();
    if (end <= pos.*) return;

    // Garante que o reader começa na posição correcta,
    // independente do que tenha acontecido antes.
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

/// macOS/BSD: kqueue — mecanismo de notificação do kernel.
/// `EVFILT_VNODE` + `NOTE_WRITE` notifica quando o arquivo é escrito.
/// `EV_CLEAR` limpa o estado do evento depois de cada entrega,
/// evitando notificações duplicadas.
/// A chamada `kevent(..., null)` bloqueia a thread sem consumir CPU
/// até que o kernel entregue um evento.
fn watchKqueue(allocator: std.mem.Allocator, file: std.fs.File, pos: *u64) !void {
    const kq = try std.posix.kqueue();
    defer std.posix.close(kq);

    // Regista o interesse: queremos saber quando o arquivo for escrito.
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
        // Bloqueia até o kernel notificar uma mudança no arquivo.
        const n = try std.posix.kevent(kq, &.{}, &events, null);
        if (n == 0) continue;
        try readNew(allocator, file, pos);
    }
}

/// Linux: inotify — subsistema de notificação de eventos de ficheiros.
/// `IN.MODIFY` notifica quando o conteúdo do arquivo muda.
/// `read` no fd do inotify bloqueia até haver eventos.
fn watchInotify(allocator: std.mem.Allocator, file: std.fs.File, path: []const u8, pos: *u64) !void {
    const ifd = try std.posix.inotify_init1(0);
    defer std.posix.close(ifd);
    _ = try std.posix.inotify_add_watch(ifd, path, std.os.linux.IN.MODIFY);

    // Buffer alinhado para inotify_event structs.
    var buf: [4096]u8 align(4) = undefined;
    while (true) {
        _ = try std.posix.read(ifd, &buf);
        try readNew(allocator, file, pos);
    }
}

/// Fallback para outros sistemas: polling a cada 250ms.
fn watchPoll(allocator: std.mem.Allocator, file: std.fs.File, pos: *u64) !void {
    while (true) {
        try readNew(allocator, file, pos);
        std.Thread.sleep(poll_interval_ns);
    }
}
