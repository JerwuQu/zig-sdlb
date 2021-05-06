const std = @import("std");
const sdlb = @import("sdlb");
const c = sdlb.c;

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

    var audioDevice = try sdlb.AudioDevice.openDefault(alloc);
    defer audioDevice.deinit();

    var letterAnim = sdlb.AnimState{ .anim = &assets.anims.letters_MainAnim };

    const keybinds = sdlb.loadKeyConfig("example.keymap", .{
        .left = c.SDLK_a,
        .right = c.SDLK_d,
        .up = c.SDLK_w,
        .down = c.SDLK_s,
        .playSound = c.SDLK_SPACE,
    });
    sdlb.saveKeyConfig("example.keymap", keybinds) catch {};
    const KeyStates = sdlb.makeKeyStates(@TypeOf(keybinds));
    var keysHeld = KeyStates{};
    var keysPressed = KeyStates{};

    var dudeX: sdlb.SUnit = 1;
    var dudeY: sdlb.SUnit = 1;

    while (game.loop()) {
        game.updateKeys(KeyStates, keybinds, &keysHeld, &keysPressed, null);
        if (keysHeld.left) {
            dudeX -= 1;
        }
        if (keysHeld.right) {
            dudeX += 1;
        }
        if (keysHeld.up) {
            dudeY -= 1;
        }
        if (keysHeld.down) {
            dudeY += 1;
        }
        if (keysPressed.playSound) {
            _ = try audioDevice.play(assets.sounds.zoop, .{});
        }

        game.clear(sdlb.RGB(0, 0, 0));
        game.drawRect(sdlb.RGB(255, 0, 0), .{ .w = 32, .h = 32 });
        game.drawSprite(assets.sheets.specks[@divTrunc(game.tick, 1000) % assets.sheets.specks.len], 8, 8, 4, .{});
        game.drawAnim(&letterAnim, 34, 10, 1, .{});
        game.drawSprite(assets.images.cooldude, dudeX, dudeY, 1, .{});
        game.render(sdlb.RGB(100, 100, 100));
        // std.log.info("FPS: {}", .{ game.getFPS() });
    }
}
