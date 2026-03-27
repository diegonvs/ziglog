const std = @import("std");

/// Intervalo de polling em nanosegundos (250ms).
const poll_interval_ns: u64 = 250 * std.time.ns_per_ms;

/// Observa o arquivo de log e imprime novas linhas à medida que chegam.
///
/// Estratégia de polling:
/// 1. Avança até o fim do arquivo na abertura (não repete histórico)
/// 2. A cada 250ms verifica se o tamanho do arquivo cresceu
/// 3. Lê os bytes novos e imprime linha por linha
///
/// `std.time.sleep` suspende a thread pelo intervalo sem consumir CPU.
pub fn run(allocator: std.mem.Allocator, path: []const u8) !void {
    _ = allocator;
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("Nenhum log encontrado. Use 'ziglog start' primeiro.\n", .{});
            return;
        },
        else => return err,
    };
    defer file.close();

    // Começa no fim do arquivo — não relê o histórico
    var pos = try file.getEndPos();
    try file.seekTo(pos);

    std.debug.print("Aguardando novos logs...\n", .{});

    while (true) {
        const end = try file.getEndPos();

        if (end > pos) {
            var buf: [65536]u8 = undefined;
            var reader = file.readerStreaming(&buf);

            // Lê apenas os bytes novos desde `pos`
            while (try reader.interface.takeDelimiter('\n')) |raw| {
                std.debug.print("{s}\n", .{raw});
            }

            pos = end;
        }

        std.Thread.sleep(poll_interval_ns);
    }
}
