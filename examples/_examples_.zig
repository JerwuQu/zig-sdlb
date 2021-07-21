const std = @import("std");

pub fn main() !u8 {
    const examples = .{
        .@"general" = @import("./general.zig"),
        .@"bitmap-font" = @import("./bitmap-font.zig"),
        .@"pixel-lighting" = @import("./pixel-lighting.zig"),
    };

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    if (args.len != 2) {
        std.log.err("USAGE: examples <example name>", .{});
        return 1;
    }

    const arg = std.mem.spanZ(args[1]);

    const exFields = comptime std.meta.fields(@TypeOf(examples));
    inline for (exFields) |exField| {
        if (std.mem.eql(u8, exField.name, arg)) {
            std.log.info("running example '{s}'", .{exField.name});
            try @field(examples, exField.name).main();
            return 0;
        }
    }

    std.log.err("no such example '{s}'", .{arg});
    return 1;
}