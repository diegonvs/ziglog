const std = @import("std");

/// Representa o comando que o usuário passou na linha de comando.
/// `union(enum)` é um tagged union: cada variante tem um tipo associado.
pub const Command = union(enum) {
    start,
    find: []const u8, // carrega a query de busca
    tail,
};

pub const ParseError = error{
    NoCommand,
    UnknownCommand,
    MissingArgument,
};

/// Recebe os argumentos (sem o nome do executável) e retorna o Command.
pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return error.NoCommand;

    const cmd = args[0];

    if (std.mem.eql(u8, cmd, "start")) {
        return .start;
    } else if (std.mem.eql(u8, cmd, "find")) {
        if (args.len < 2) return error.MissingArgument;
        return .{ .find = args[1] };
    } else if (std.mem.eql(u8, cmd, "tail")) {
        return .tail;
    }

    return error.UnknownCommand;
}

test "parse start" {
    const cmd = try parse(&.{"start"});
    try std.testing.expectEqual(Command.start, cmd);
}

test "parse find com query" {
    const cmd = try parse(&.{ "find", "error" });
    try std.testing.expectEqualStrings("error", cmd.find);
}

test "parse find sem argumento retorna MissingArgument" {
    try std.testing.expectError(error.MissingArgument, parse(&.{"find"}));
}

test "parse tail" {
    const cmd = try parse(&.{"tail"});
    try std.testing.expectEqual(Command.tail, cmd);
}

test "parse sem argumentos retorna NoCommand" {
    try std.testing.expectError(error.NoCommand, parse(&.{}));
}

test "parse comando desconhecido retorna UnknownCommand" {
    try std.testing.expectError(error.UnknownCommand, parse(&.{"foo"}));
}
