const std = @import("std");

/// Estrutura interna usada para fazer parse das entradas gravadas.
/// Usada nos testes para verificar o output sem depender do formatter.
const Entry = struct { ts: i64, msg: []const u8 };

pub const LogWriter = struct {
    file: std.fs.File,

    /// Abre (ou cria) o arquivo de log em modo append.
    /// `createFile` com `truncate = false` cria o arquivo se não existir,
    /// ou abre sem apagar o conteúdo se já existir.
    pub fn open(path: []const u8) !LogWriter {
        const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        try file.seekFromEnd(0);
        return .{ .file = file };
    }

    pub fn close(self: LogWriter) void {
        self.file.close();
    }

    /// Serializa a mensagem como uma linha JSON e grava no arquivo.
    /// Exemplo de saída: {"ts":1234567890,"msg":"hello world"}
    ///
    /// `valueAlloc` serializa o valor para uma string JSON alocada em memória.
    /// `file.writeAll` grava os bytes diretamente no arquivo.
    pub fn writeEntry(self: LogWriter, allocator: std.mem.Allocator, message: []const u8) !void {
        const ts = std.time.timestamp();
        const json = try std.json.Stringify.valueAlloc(allocator, .{ .ts = ts, .msg = message }, .{});
        defer allocator.free(json);
        try self.file.writeAll(json);
        try self.file.writeAll("\n");
    }
};

// --- Testes ---
//
// `std.testing.tmpDir(.{})` cria um directório temporário isolado em
// `.zig-cache/tmp/<hash>/`. Como `LogWriter.file` é público, podemos
// construir o struct directamente com um handle do tmp dir, sem
// depender de `cwd()`.

test "writeEntry produz JSON com campo msg correcto" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "hello world");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.NoLine;

    const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello world", parsed.value.msg);
    try std.testing.expect(parsed.value.ts > 0);
}

test "writeEntry escapa caracteres especiais em JSON" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "msg com \"aspas\" e \\barra");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);
    const line = (try reader.interface.takeDelimiter('\n')) orelse return error.NoLine;

    const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
    defer parsed.deinit();
    // std.json.parseFromSlice faz unescape — recuperamos a string original
    try std.testing.expectEqualStrings("msg com \"aspas\" e \\barra", parsed.value.msg);
}

test "writeEntry acumula múltiplas entradas (modo append)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const file = try tmp.dir.createFile("log.jsonl", .{});
        const lw = LogWriter{ .file = file };
        defer lw.close();
        try lw.writeEntry(allocator, "primeira");
        try lw.writeEntry(allocator, "segunda");
        try lw.writeEntry(allocator, "terceira");
    }

    const file = try tmp.dir.openFile("log.jsonl", .{});
    defer file.close();
    var buf: [4096]u8 = undefined;
    var reader = file.readerStreaming(&buf);

    var count: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(Entry, allocator, line, .{});
        defer parsed.deinit();
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}
