const std = @import("std");
usingnamespace @import("sdlb");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = &gpa.allocator;

    try initSDL();
    defer deinitSDL();

    var game = try Game.create(alloc, "example", 64, 64);
    defer game.deinit();

    var assets = try game.loadAssets(@embedFile("../output.bin"));
    defer assets.deinit();

    var audioDevice = try AudioDevice.openDefault(alloc);
    defer audioDevice.deinit();

    var letterAnim = AnimState{ .anim = &assets.anims.letters_MainAnim };

    const keybinds = loadKeyConfig("example.keymap", .{
        .left = c.SDLK_a,
        .right = c.SDLK_d,
        .up = c.SDLK_w,
        .down = c.SDLK_s,
        .playSound = c.SDLK_SPACE,
    });
    saveKeyConfig("example.keymap", keybinds) catch {};
    const KeyStates = makeKeyStates(@TypeOf(keybinds));
    var keysHeld = KeyStates{};
    var keysPressed = KeyStates{};

    var dudeX: SUnit = 1;
    var dudeY: SUnit = 1;

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

        game.clear(RGB(0, 0, 0));
        game.drawMap(&assets.maps.ex_map, 0, 0, 1);
        game.drawRect(RGB(255, 0, 0), .{ .x = 10, .y = 10, .w = 4, .h = 4 });
        game.drawSprite(assets.sheets.specks[@divTrunc(game.tick, 1000) % assets.sheets.specks.len], 8, 8, 1, .{});
        game.drawAnim(&letterAnim, 34, 10, 1, .{});
        game.drawSprite(assets.images.cooldude, dudeX, dudeY, 1, .{});
        game.render(RGB(100, 100, 100));
        // std.log.info("FPS: {}", .{ game.getFPS() });
    }
}
