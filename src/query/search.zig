const std = @import("std");
const pretty = @import("../formatter/pretty.zig");

const LogEntry = pretty.LogEntry;

/// Retorna true se `entry.msg` contém `query` (case-sensitive).
/// Função separada para ser testável sem I/O.
pub fn matches(entry: LogEntry, query: []const u8) bool {
    return std.mem.indexOf(u8, entry.msg, query) != null;
}

/// Conta quantas entradas num arquivo JSONL batem com `query`.
/// Testável sem capturar stdout.
pub fn countMatches(allocator: std.mem.Allocator, file: std.fs.File, query: []const u8) !usize {
    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    var count: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (matches(parsed.value, query)) count += 1;
    }
    return count;
}

/// Lê o arquivo JSONL linha por linha, faz parse de cada entrada
/// e imprime as que contêm `query`.
pub fn run(allocator: std.mem.Allocator, path: []const u8, query: []const u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            pretty.printWarn("Nenhum log encontrado. Use 'ziglog start' primeiro.");
            return;
        },
        else => return err,
    };
    defer file.close();

    var buf: [65536]u8 = undefined;
    var reader = file.readerStreaming(&buf);

    var found: usize = 0;

    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;

        // Ignora linhas que não conseguimos parsear (arquivo corrompido, etc.)
        const parsed = std.json.parseFromSlice(LogEntry, allocator, line, .{}) catch continue;
        defer parsed.deinit();

        if (matches(parsed.value, query)) {
            pretty.print(parsed.value);
            found += 1;
        }
    }

    if (found == 0) {
        var msg_buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, "Nenhum resultado para '{s}'.", .{query}) catch "Nenhum resultado.";
        pretty.printWarn(msg);
    }
}

test "matches retorna true quando query está na mensagem" {
    const entry = LogEntry{ .ts = 0, .msg = "error: connection refused" };
    try std.testing.expect(matches(entry, "error"));
    try std.testing.expect(matches(entry, "connection"));
}

test "matches retorna false quando query não está na mensagem" {
    const entry = LogEntry{ .ts = 0, .msg = "server started" };
    try std.testing.expect(!matches(entry, "error"));
}

test "matches é case-sensitive" {
    const entry = LogEntry{ .ts = 0, .msg = "Error: something failed" };
    try std.testing.expect(!matches(entry, "error")); // 'e' minúsculo não bate
    try std.testing.expect(matches(entry, "Error"));
}

test "matches com query vazia bate em tudo" {
    const entry = LogEntry{ .ts = 0, .msg = "qualquer mensagem" };
    try std.testing.expect(matches(entry, ""));
}

test "matches bate query no início da mensagem" {
    const entry = LogEntry{ .ts = 0, .msg = "error at startup" };
    try std.testing.expect(matches(entry, "error"));
}

test "matches bate query no fim da mensagem" {
    const entry = LogEntry{ .ts = 0, .msg = "startup error" };
    try std.testing.expect(matches(entry, "error"));
}

test "countMatches lê arquivo JSONL e conta correctamente" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Escreve entradas de teste directamente como JSONL
    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"msg\":\"error: timeout\"}\n");
        try file.writeAll("{\"ts\":2,\"msg\":\"server started\"}\n");
        try file.writeAll("{\"ts\":3,\"msg\":\"error: refused\"}\n");
        try file.writeAll("{\"ts\":4,\"msg\":\"info: ready\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error"));
}

test "countMatches ignora linhas inválidas" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        defer file.close();
        try file.writeAll("{\"ts\":1,\"msg\":\"error ok\"}\n");
        try file.writeAll("linha corrompida\n");
        try file.writeAll("{\"ts\":3,\"msg\":\"error também\"}\n");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();

    try std.testing.expectEqual(@as(usize, 2), try countMatches(allocator, file, "error"));
}
