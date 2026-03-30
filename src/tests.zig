const std = @import("std");

comptime {
    _ = @import("level.zig");
    _ = @import("cli/parser.zig");
    _ = @import("storage/writer.zig");
    _ = @import("query/search.zig");
    _ = @import("formatter/pretty.zig");
    _ = @import("time/duration.zig");
}
