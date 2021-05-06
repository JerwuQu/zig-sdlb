const std = @import("std");
const sdlb = @import("sdlb");

const assetsBin = @embedFile("assets/output.bin");
const Assets = sdlb.assetsType(assetsBin);

fn drawText(game: *sdlb.Game, assets: *Assets, str: []const u8, color: sdlb.Color, x: sdlb.SUnit, y: sdlb.SUnit) void {
    const FONT_LETTER_START = 0;
    const FONT_SIGN_START = 26;
    const FONT_W = assets.sheets.font[0].srcRect.w;
    const FONT_H = assets.sheets.font[0].srcRect.h;
    var tx: sdlb.SUnit = 0;
    var ty: sdlb.SUnit = 0;
    for (str) |char| {
        if (char >= 'A' and char <= 'Z') {
            game.drawSprite(assets.sheets.font[char - 'A' + FONT_LETTER_START], x + tx, y + ty, 1, .{ .color = color });
            tx += FONT_W + 1;
        } else if (char >= 'a' and char <= 'z') {
            game.drawSprite(assets.sheets.font[char - 'a' + FONT_LETTER_START], x + tx, y + ty, 1, .{ .color = color });
            tx += FONT_W + 1;
        } else if (char >= '!' and char <= '9') {
            game.drawSprite(assets.sheets.font[char - '!' + FONT_SIGN_START], x + tx, y + ty, 1, .{ .color = color });
            tx += FONT_W + 1;
        } else if (char == ' ') {
            tx += FONT_W;
        } else if (char == '\n') {
            tx = 0;
            ty += FONT_H + 1;
        } else {
            std.log.err("Unrecognized glyph {}", .{char});
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    try sdlb.initSDL();
    defer sdlb.deinitSDL();

    var game = try sdlb.Game.create(alloc, "example", 70, 20);
    defer game.deinit();

    var assets = try game.loadAssets(assetsBin);
    defer assets.deinit();

    while (game.loop()) {
        game.clear(sdlb.RGB(0, 0, 0));
        drawText(&game, &assets, "Hello, World!", sdlb.RGB(255, 100, 0), 5, 5);
        game.render(sdlb.RGB(100, 100, 100));
    }
}