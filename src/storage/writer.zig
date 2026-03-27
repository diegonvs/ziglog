const std = @import("std");

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
