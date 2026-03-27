const std = @import("std");
const storage = @import("../storage/writer.zig");

/// Lê linhas do stdin e grava cada uma como entrada de log.
///
/// No Zig 0.15, o reader precisa de um buffer explícito — ele serve como
/// buffer interno para leituras eficientes (lê blocos do SO em vez de um
/// byte por vez). `readerStreaming` é usado porque stdin é um stream
/// sequencial, sem suporte a leitura posicional.
///
/// `takeDelimiter('\n')` retorna:
///   - uma slice da linha (sem o '\n') enquanto há dados
///   - `null` quando chega ao EOF sem bytes restantes
pub fn run(allocator: std.mem.Allocator, log_writer: storage.LogWriter) !void {
    var buf: [65536]u8 = undefined;
    var reader = std.fs.File.stdin().readerStreaming(&buf);

    while (try reader.interface.takeDelimiter('\n')) |line| {
        try log_writer.writeEntry(allocator, line);
    }
}
