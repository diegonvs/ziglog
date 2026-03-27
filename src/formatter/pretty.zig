const std = @import("std");

/// Códigos de escape ANSI para cores no terminal.
const reset = "\x1b[0m";
const dim = "\x1b[2m";
const red = "\x1b[31m";
const yellow = "\x1b[33m";
const green = "\x1b[32m";
const bold = "\x1b[1m";

pub const LogEntry = struct {
    ts: i64,
    msg: []const u8,
};

/// Formata e imprime uma entrada de log com cores e timestamp legível.
///
/// Saída: [HH:MM:SS] <mensagem colorida>
/// A cor da mensagem é escolhida com base em palavras-chave (case-insensitive).
pub fn print(entry: LogEntry) void {
    const hms = toHMS(entry.ts);
    const color = levelColor(entry.msg);
    const stdout = std.fs.File.stdout();
    stdout.writeAll(dim) catch return;
    // std.fmt.bufPrint monta a string no stack sem alocar heap
    var time_buf: [16]u8 = undefined;
    const time_str = std.fmt.bufPrint(&time_buf, "[{d:0>2}:{d:0>2}:{d:0>2}]", .{
        hms.h, hms.m, hms.s,
    }) catch return;
    stdout.writeAll(time_str) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll(" ") catch return;
    stdout.writeAll(color) catch return;
    stdout.writeAll(entry.msg) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll("\n") catch return;
}

/// Imprime uma mensagem de sistema (não é uma entrada de log).
/// Usada para "Aguardando novos logs..." e afins.
pub fn printInfo(msg: []const u8) void {
    const stdout = std.fs.File.stdout();
    stdout.writeAll(dim) catch return;
    stdout.writeAll(msg) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll("\n") catch return;
}

/// Imprime uma mensagem de aviso/erro do próprio ziglog.
pub fn printWarn(msg: []const u8) void {
    const stdout = std.fs.File.stdout();
    stdout.writeAll(yellow) catch return;
    stdout.writeAll(msg) catch return;
    stdout.writeAll(reset) catch return;
    stdout.writeAll("\n") catch return;
}

// --- Funções internas ---

const HMS = struct { h: u5, m: u6, s: u6 };

/// Converte um timestamp Unix (segundos) para hora/minuto/segundo UTC.
/// Usa `std.time.epoch.EpochSeconds` para decompor o valor.
fn toHMS(ts: i64) HMS {
    const secs: u64 = @intCast(@max(0, ts));
    const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
    const day = epoch.getDaySeconds();
    return .{
        .h = day.getHoursIntoDay(),
        .m = day.getMinutesIntoHour(),
        .s = day.getSecondsIntoMinute(),
    };
}

/// Escolhe a cor ANSI com base em palavras-chave na mensagem.
fn levelColor(msg: []const u8) []const u8 {
    if (containsIgnoreCase(msg, "error") or
        containsIgnoreCase(msg, "fatal") or
        containsIgnoreCase(msg, "panic"))
        return bold ++ red;
    if (containsIgnoreCase(msg, "warn"))
        return yellow;
    if (containsIgnoreCase(msg, "info") or
        containsIgnoreCase(msg, "start") or
        containsIgnoreCase(msg, "ready"))
        return green;
    return reset;
}

/// Busca `needle` em `haystack` ignorando maiúsculas/minúsculas.
/// Compara byte a byte com `std.ascii.toLower`.
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != needle[j]) break;
        } else return true;
    }
    return false;
}

test "levelColor detecta error" {
    try std.testing.expectEqualStrings(bold ++ red, levelColor("error: connection refused"));
    try std.testing.expectEqualStrings(bold ++ red, levelColor("ERROR: disk full"));
}

test "levelColor detecta warn" {
    try std.testing.expectEqualStrings(yellow, levelColor("warn: retry"));
    try std.testing.expectEqualStrings(yellow, levelColor("WARNING: high memory"));
}

test "levelColor detecta info/start/ready" {
    try std.testing.expectEqualStrings(green, levelColor("server started"));
    try std.testing.expectEqualStrings(green, levelColor("ready to accept connections"));
}

test "levelColor default sem palavra-chave" {
    try std.testing.expectEqualStrings(reset, levelColor("something happened"));
}

test "toHMS converte timestamp corretamente" {
    // 1970-01-01 00:00:00 UTC
    const t0 = toHMS(0);
    try std.testing.expectEqual(@as(u5, 0), t0.h);
    try std.testing.expectEqual(@as(u6, 0), t0.m);
    try std.testing.expectEqual(@as(u6, 0), t0.s);

    // 1970-01-01 01:02:03 UTC = 3723 segundos
    const t1 = toHMS(3723);
    try std.testing.expectEqual(@as(u5, 1), t1.h);
    try std.testing.expectEqual(@as(u6, 2), t1.m);
    try std.testing.expectEqual(@as(u6, 3), t1.s);
}
