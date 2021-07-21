const std = @import("std");
const sdlb = @import("sdlb");
const c = sdlb.c;
usingnamespace sdlb.units;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    try sdlb.initSDL();
    defer sdlb.deinitSDL();

    var game = try sdlb.Game.create(alloc, "example", 64, 64);
    defer game.deinit();

    var assets = try game.loadAssets(@embedFile("assets/output.bin"));
    defer assets.deinit();

    var lightingMap = c.SDL_CreateTexture(game.rnd, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, game.w, game.h) orelse unreachable;
    defer c.SDL_DestroyTexture(lightingMap);
    _ = c.SDL_SetTextureBlendMode(lightingMap, c.SDL_BLENDMODE_BLEND);

    while (game.loop()) {
        game.clear(sdlb.RGB(0, 0, 0));
        game.drawSprite(assets.images.cooldude, 0, 0, 4, .{});

        // Move light source
        const lightX = 32 + std.math.cos(@intToFloat(f32, game.tick) / 100) * 20;
        const lightY = 32 + std.math.sin(@intToFloat(f32, game.tick) / 100) * 20;

        // Update lighting map
        var pixels: *u8 = undefined;
        var pitch: c_int = undefined;
        _ = c.SDL_LockTexture(lightingMap, null, @ptrCast([*c]?*c_void, &pixels), &pitch);
        var y: usize = 0;
        while (y < game.h) : (y += 1) {
            var row = @intToPtr([*c]u32, @ptrToInt(pixels) + y * @intCast(usize, pitch));
            var x: usize = 0;
            while (x < game.w) : (x += 1) {
                const distX = lightX - @intToFloat(f32, x);
                const distY = lightY - @intToFloat(f32, y);
                row[x] = @floatToInt(u32, std.math.min(255, std.math.sqrt(distX * distX + distY * distY) * 10));
                // row[x] = 255 - @floatToInt(u32, std.math.min(255, 1000 / (std.math.sqrt(distX * distX + distY * distY) + 1)));
            }
        }
        c.SDL_UnlockTexture(lightingMap);

        game.drawTexture(lightingMap, 0, 0, game.w, game.h, .{});
        game.render(RGB(100, 100, 100));
    }
}
