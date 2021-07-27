const std = @import("std");
usingnamespace @import("sdlb");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    try initSDL();
    defer deinitSDL();

    var game = try Game.create(alloc, "example", 70, 20);
    defer game.deinit();

    var assets = try game.loadAssets(@embedFile("../output.bin"));
    defer assets.deinit();

    const font = Font{
        .sheet = assets.sheets.font,
        .glyphW = assets.sheets.font[0].srcRect.w,
        .glyphH = assets.sheets.font[0].srcRect.h,
        .mapGlyph = struct {
            fn inner(codepoint: u21) ?usize {
                const FONT_LETTER_START = 0;
                const FONT_SIGN_START = 26;

                if (codepoint >= 'A' and codepoint <= 'Z') {
                    return codepoint - 'A' + FONT_LETTER_START;
                } else if (codepoint >= 'a' and codepoint <= 'z') {
                    return codepoint - 'a' + FONT_LETTER_START;
                } else if (codepoint >= '!' and codepoint <= '9') {
                    return codepoint - '!' + FONT_SIGN_START;
                } else if (codepoint == ' ') {
                    return null; // TODO: return space
                } else if (codepoint == '\n') {
                    return null; // TODO: return newline
                } else {
                    return null;
                }
            }
        }.inner,
    };

    while (game.loop()) {
        game.clear(RGB(0, 0, 0));
        game.drawText(&font, "Hello, World!", RGB(255, 100, 0), 5, 5, 1);
        game.render(RGB(100, 100, 100));
    }
}
