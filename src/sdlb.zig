const std = @import("std");
pub const c = @import("./c.zig").c;
pub usingnamespace @import("./units.zig");
pub usingnamespace @import("./audio.zig");

const WIN_MARGIN = 200;

const SDL_Error = error{
    SDL_Init,
    SDL_CreateWindow,
    SDL_CreateRenderer,
    SDL_CreateRGBSurfaceFrom,
    SDL_CreateTextureFromSurface,
    SDL_GetCurrentDisplayMode,
    SDL_SetRenderDrawBlendMode,
};

pub fn initSDL() SDL_Error!void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
        return SDL_Error.SDL_Init;
    }
}

pub fn deinitSDL() void {
    c.SDL_Quit();
}

pub fn getTick() Tick {
    return c.SDL_GetTicks();
}

pub const Game = struct {
    const KeycodeTickMap = std.AutoHashMap(Keycode, Tick);
    const DrawOptions = struct {
        flipX: bool = false,
        flipY: bool = false,
        color: Color = RGB(255, 255, 255),
    };

    alloc: *std.mem.Allocator,
    gameW: UUnit,
    gameH: UUnit,
    winW: UUnit,
    winH: UUnit,
    scale: UUnit,
    wnd: *c.SDL_Window,
    rnd: *c.SDL_Renderer,
    tick: Tick,
    fps: struct {
        fps: u32 = 0,
        counter: u32 = 0,
        lastTick: Tick,
    },
    mouse: struct {
        const MouseButtonState = struct {
            down: bool = false,
            pressed: bool = false,
        };

        x: SUnit = 0,
        y: SUnit = 0,
        scrollDeltaX: i16 = 0,
        scrollDeltaY: i16 = 0,
        left: MouseButtonState = .{},
        middle: MouseButtonState = .{},
        right: MouseButtonState = .{},
    } = .{},
    keyUpdates: struct {
        pressed: KeycodeTickMap,
        released: KeycodeTickMap,
    },

    // -- Init & Deinit --
    pub fn createZ(alloc: *std.mem.Allocator, title: [:0]const u8, w: UUnit, h: UUnit) SDL_Error!Game {
        var dm: c.SDL_DisplayMode = undefined;
        if (c.SDL_GetCurrentDisplayMode(0, &dm) != 0) {
            return SDL_Error.SDL_GetCurrentDisplayMode;
        }
        const scale = @intCast(UUnit, std.math.min(@divTrunc(dm.w - WIN_MARGIN, w), @divTrunc(dm.h - WIN_MARGIN, h)));
        const winW = @intCast(UUnit, w * scale);
        const winH = @intCast(UUnit, h * scale);

        const wnd = c.SDL_CreateWindow(title, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, winW, winH, c.SDL_WINDOW_RESIZABLE);
        if (wnd == null) {
            return SDL_Error.SDL_CreateWindow;
        }

        const rnd = c.SDL_CreateRenderer(wnd, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC);
        if (rnd == null) {
            return SDL_Error.SDL_CreateRenderer;
        }

        if (c.SDL_SetRenderDrawBlendMode(rnd, .SDL_BLENDMODE_BLEND) != 0) {
            return SDL_Error.SDL_SetRenderDrawBlendMode;
        }

        return Game{
            .alloc = alloc,
            .gameW = w,
            .gameH = h,
            .winW = winW,
            .winH = winH,
            .scale = scale,
            .wnd = wnd.?,
            .rnd = rnd.?,
            .tick = getTick(),
            .fps = .{
                .lastTick = getTick(),
            },
            .keyUpdates = .{
                .pressed = Game.KeycodeTickMap.init(alloc),
                .released = Game.KeycodeTickMap.init(alloc),
            }
        };
    }
    pub fn create(alloc: *std.mem.Allocator, comptime title: []const u8, w: UUnit, h: UUnit) !Game {
        return createZ(alloc, title ++ "\x00", w, h);
    }
    pub fn deinit(self: *Game) void {
        self.keyUpdates.pressed.deinit();
        self.keyUpdates.released.deinit();
        c.SDL_DestroyRenderer(self.rnd);
        c.SDL_DestroyWindow(self.wnd);
        self.* = undefined;
    }

    // -- Private methods --
    fn setColor(self: *const Game, color: Color) void {
        _ = c.SDL_SetRenderDrawColor(self.rnd, color.r, color.g, color.b, color.a);
    }
    fn scaleRect(self: *const Game, r: Rect) Rect {
        return .{
            .x = r.x * self.scale + @divTrunc(self.winW - self.gameW * self.scale, 2),
            .y = r.y * self.scale + @divTrunc(self.winH - self.gameH * self.scale, 2),
            .w = r.w * self.scale,
            .h = r.h * self.scale,
        };
    }
    fn unscalePoint(self: *const Game, x: SUnit, y: SUnit) struct { x: SUnit, y: SUnit } {
        return .{
            .x = @divTrunc(x - @divTrunc(self.winW - self.gameW * self.scale, 2), self.scale),
            .y = @divTrunc(y - @divTrunc(self.winH - self.gameH * self.scale, 2), self.scale),
        };
    }
    fn loadTextureFromRGBA(self: *const Game, pixels: []const u8, w: UUnit, h: UUnit) SDL_Error!Texture {
        // NOTE: uses hacky pointer conversion because we can guarantee the data won't be written to
        const surf = c.SDL_CreateRGBSurfaceFrom(@intToPtr(*c_void, @ptrToInt(pixels.ptr)), w, h, 32, w * 4, 0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000);
        if (surf == null) {
            return SDL_Error.SDL_CreateRGBSurfaceFrom;
        }
        defer c.SDL_FreeSurface(surf);
        const tx = c.SDL_CreateTextureFromSurface(self.rnd, surf);
        if (tx == null) {
            return SDL_Error.SDL_CreateTextureFromSurface;
        }
        return Texture{ .tx = tx.?, .w = w, .h = h };
    }

    // -- Public methods --
    pub fn getFPS(self: *const Game) usize {
        return self.fps.fps;
    }
    pub fn clear(self: *Game, clearColor: Color) void {
        self.setColor(clearColor);
        // should never error
        _ = c.SDL_RenderClear(self.rnd);
    }
    pub fn render(self: *Game, borderColor: Color) void {
        // Calculate FPS
        self.fps.counter += 1;
        if (self.tick - self.fps.lastTick >= 1000) {
            self.fps.fps = self.fps.counter;
            self.fps.counter = 0;
            self.fps.lastTick = self.tick;
        }

        // Draw borders
        self.setColor(borderColor);
        const vp = self.scaleRect(.{ .x = 0, .y = 0, .w = self.gameW, .h = self.gameH });
        _ = c.SDL_RenderFillRect(self.rnd, &.{ .x = 0, .y = 0, .w = self.winW, .h = @intCast(UUnit, vp.y) });
        _ = c.SDL_RenderFillRect(self.rnd, &.{ .x = 0, .y = vp.y + vp.h, .w = self.winW, .h = self.winH - @intCast(UUnit, vp.y) });
        _ = c.SDL_RenderFillRect(self.rnd, &.{ .x = vp.x + vp.w, .y = vp.y, .w = self.winW - @intCast(UUnit, vp.x), .h = self.winH - @intCast(UUnit, vp.y) });
        _ = c.SDL_RenderFillRect(self.rnd, &.{ .x = 0, .y = vp.y, .w = @intCast(UUnit, vp.x), .h = self.winH - @intCast(UUnit, vp.y) });

        // Render
        c.SDL_RenderPresent(self.rnd);
    }
    pub fn drawRect(self: *Game, color: Color, rect: Rect) void {
        self.setColor(color);
        _ = c.SDL_RenderFillRect(self.rnd, &self.scaleRect(rect).toSDL());
    }
    pub fn drawRectOutline(self: *Game, color: Color, outline: UUnit, rect: Rect) void {
        self.setColor(color);
        _ = c.SDL_RenderFillRect(self.rnd, &self.scaleRect(x, y - outline, w, outline).toSDL());
        _ = c.SDL_RenderFillRect(self.rnd, &self.scaleRect(x, y + h, w, outline).toSDL());
        _ = c.SDL_RenderFillRect(self.rnd, &self.scaleRect(x - outline, y - outline, outline, h + outline * 2).toSDL());
        _ = c.SDL_RenderFillRect(self.rnd, &self.scaleRect(x + w, y - outline, outline, h + outline * 2).toSDL());
    }
    pub fn drawSprite(self: *Game, sprite: Sprite, x: SUnit, y: SUnit, scale: UUnit, options: DrawOptions) void {
        _ = c.SDL_SetTextureAlphaMod(sprite.atlas.tx, options.color.a);
        _ = c.SDL_SetTextureColorMod(sprite.atlas.tx, options.color.r, options.color.g, options.color.b);
        // TODO: error on non-perfect int scaling
        const flip = (if (options.flipX) c.SDL_FLIP_HORIZONTAL else 0) | (if (options.flipY) c.SDL_FLIP_HORIZONTAL else 0);
        const rect = Rect{
            .x = x,
            .y = y,
            .w = sprite.srcRect.w * scale,
            .h = sprite.srcRect.h * scale,
        };
        _ = c.SDL_RenderCopyEx(self.rnd, sprite.atlas.tx, &sprite.srcRect.toSDL(), &self.scaleRect(rect).toSDL(), 0, null, @intToEnum(c.SDL_RendererFlip, flip));
    }
    pub fn drawAnim(self: *Game, animState: *AnimState, x: SUnit, y: SUnit, scale: UUnit, options: DrawOptions) void {
        // TODO: math
        while (self.tick - animState.frameTime >= animState.anim.frames[animState.currentFrame].duration) {
            animState.frameTime += animState.anim.frames[animState.currentFrame].duration;
            animState.currentFrame += 1;
            if (animState.currentFrame == animState.anim.frames.len) {
                animState.currentFrame = 0;
                if (animState.nextAnim != null) {
                    animState.anim = animState.nextAnim.?;
                    animState.nextAnim = null;
                }
            }
        }
        self.drawSprite(animState.anim.frames[animState.currentFrame].sprite, x, y, scale, options);
    }

    /// Returns true to keep running, false to exit
    pub fn loop(self: *Game) bool {
        // Clean up from last iteration
        self.mouse.scrollDeltaX = 0;
        self.mouse.scrollDeltaY = 0;
        self.mouse.left.pressed = false;
        self.mouse.right.pressed = false;
        self.mouse.middle.pressed = false;
        self.keyUpdates.pressed.clearRetainingCapacity();
        self.keyUpdates.released.clearRetainingCapacity();

        // Handle events
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) > 0) {
            switch (e.type) {
                c.SDL_QUIT => return false,
                c.SDL_WINDOWEVENT => {
                    if (e.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                        self.winW = @intCast(UUnit, e.window.data1);
                        self.winH = @intCast(UUnit, e.window.data2);
                        self.scale = std.math.min(@divTrunc(self.winW, self.gameW), @divTrunc(self.winH, self.gameH));
                        if (self.scale == 0) {
                            std.log.warn("Window too small!", .{});
                            // TODO: rather than doing this (which will make the game work but render incorrectly), make the window red or something
                            self.winW = self.gameW;
                            self.winH = self.gameH;
                            self.scale = 1;
                        }
                    }
                },
                c.SDL_MOUSEWHEEL => {
                    self.mouse.scrollDeltaX += @intCast(i16, e.wheel.x);
                    self.mouse.scrollDeltaY += @intCast(i16, e.wheel.y);
                },
                c.SDL_MOUSEMOTION => {
                    const p = self.unscalePoint(e.motion.x, e.motion.y);
                    self.mouse.x = p.x;
                    self.mouse.y = p.y;
                },
                c.SDL_MOUSEBUTTONDOWN => {
                    if (e.button.button == c.SDL_BUTTON_LEFT) {
                        self.mouse.left.down = true;
                        self.mouse.left.pressed = true;
                    } else if (e.button.button == c.SDL_BUTTON_RIGHT) {
                        self.mouse.right.down = true;
                        self.mouse.right.pressed = true;
                    } else if (e.button.button == c.SDL_BUTTON_MIDDLE) {
                        self.mouse.middle.down = true;
                        self.mouse.middle.pressed = true;
                    }
                },
                c.SDL_MOUSEBUTTONUP => {
                    if (e.button.button == c.SDL_BUTTON_LEFT) {
                        self.mouse.left.down = false;
                    } else if (e.button.button == c.SDL_BUTTON_RIGHT) {
                        self.mouse.right.down = false;
                    } else if (e.button.button == c.SDL_BUTTON_MIDDLE) {
                        self.mouse.middle.down = false;
                    }
                },
                c.SDL_KEYDOWN => self.keyUpdates.pressed.put(@intCast(Keycode, e.key.keysym.sym), e.key.timestamp) catch unreachable,
                c.SDL_KEYUP => self.keyUpdates.released.put(@intCast(Keycode, e.key.keysym.sym), e.key.timestamp) catch unreachable,
                else => {},
            }
        }

        // Update tick
        self.tick = getTick();

        return true;
    }
    /// To be ran after `Game.loop`. Will updated the given KeyStates structs according to `keybinds`.
    pub fn updateKeys(self: *Game, comptime KeyStates: type, keybinds: anytype, held: ?*KeyStates, pressed: ?*KeyStates, released: ?*KeyStates) void {
        comptime const keys = std.meta.fieldNames(KeyStates);
        inline for (keys) |key| {
            if (self.keyUpdates.pressed.contains(@field(keybinds, key))) {
                if (held == null or !@field(held.?, key)) {
                    @field(held.?, key) = true;
                    if (pressed != null) {
                        @field(pressed.?, key) = true;
                    }
                }
            } else if (pressed != null) {
                @field(pressed.?, key) = false;
            }
            if (self.keyUpdates.released.contains(@field(keybinds, key))) {
                if (held == null or @field(held.?, key)) {
                    @field(held.?, key) = false;
                    if (released != null) {
                        @field(released.?, key) = true;
                    }
                }
            } else if (released != null) {
                @field(released.?, key) = false;
            }
        }
    }

    // -- Asset methods --
    pub fn loadAssets(self: *Game, comptime assetBin: []const u8) !assetsType(assetBin) {
        const ass = comptime AssetMetadata.parse(assetBin);
        var assets: assetsType(assetBin) = undefined;
        assets.alloc = self.alloc;

        // Decompress asset data
        var assZ = try self.alloc.alloc(u8, ass.decompressedDataSize);
        if (c.ZSTD_isError(c.ZSTD_decompress(assZ.ptr, assZ.len, ass.compressedData.ptr, ass.compressedData.len)) != 0) {
            return error.zstd_decompression;
        }
        defer self.alloc.free(assZ);

        var byteI: usize = 0;

        // Load atlases
        assets.atlases = try self.alloc.alloc(Texture, ass.atlasCount);
        var atlasI: usize = 0;
        while (atlasI < ass.atlasCount) : (atlasI += 1) {
            const w = std.mem.readIntSliceBig(u16, assZ[byteI .. byteI + 2]);
            const h = std.mem.readIntSliceBig(u16, assZ[byteI + 2 .. byteI + 4]);
            assets.atlases[atlasI] = try self.loadTextureFromRGBA(assZ[byteI + 4 .. byteI + @as(usize, w) * @as(usize, h) * 4 + 4], w, h);
            byteI += @as(usize, w) * @as(usize, h) * 4 + 4;
        }

        // Load images
        inline for (ass.imageNames) |name| {
            @field(assets.images, name) = Sprite.readFromBinary(assets.atlases, assZ[byteI .. byteI + 10]);
            byteI += 10;
        }

        // Load spritesheets
        inline for (ass.sheetNames) |name| {
            const spriteCount = std.mem.readIntSliceBig(u16, assZ[byteI .. byteI + 2]);
            byteI += 2;
            var sprites = try self.alloc.alloc(Sprite, spriteCount);
            var spriteI: u16 = 0;
            while (spriteI < spriteCount) : (spriteI += 1) {
                sprites[spriteI] = Sprite.readFromBinary(assets.atlases, assZ[byteI .. byteI + 10]);
                byteI += 10;
            }
            @field(assets.sheets, name) = sprites;
        }

        // Load animations
        inline for (ass.animNames) |name| {
            const frameCount = std.mem.readIntSliceBig(u16, assZ[byteI .. byteI + 2]);
            byteI += 2;
            var frames = try self.alloc.alloc(Anim.Frame, frameCount);
            var frameI: u16 = 0;
            while (frameI < frameCount) : (frameI += 1) {
                frames[frameI].sprite = Sprite.readFromBinary(assets.atlases, assZ[byteI .. byteI + 10]);
                frames[frameI].duration = std.mem.readIntSliceBig(u16, assZ[byteI + 10 .. byteI + 12]);
                byteI += 12;
            }
            @field(assets.anims, name).frames = frames;
        }

        // Load sounds
        inline for (ass.soundNames) |name| {
            const sz = std.mem.readIntSliceBig(u32, assZ[byteI .. byteI + 4]);
            @field(assets.sounds, name) = try self.alloc.dupe(u8, assZ[byteI + 4 .. byteI + 4 + sz]);
            byteI += sz + 4;
        }

        return assets;
    }
};

const AssetMetadata = struct {
    atlasCount: u16,
    imageNames: []const []const u8,
    sheetNames: []const []const u8,
    animNames: []const []const u8,
    soundNames: []const []const u8,
    decompressedDataSize: u32,
    compressedData: []const u8,

    fn parseNames(comptime data: []const u8, byteI: *usize) []const []const u8 {
        const count = std.mem.readIntSliceBig(u16, data[byteI.* .. byteI.* + 2]);
        byteI.* += 2;
        var names: []const []const u8 = &.{};
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const strlen = std.mem.readIntSliceBig(u16, data[byteI.* .. byteI.* + 2]);
            names = names ++ [1][]const u8{data[byteI.* + 2 .. byteI.* + 2 + strlen]};
            byteI.* += strlen + 2;
        }
        return names;
    }

    fn parse(comptime data: []const u8) AssetMetadata {
        const atlasCount = std.mem.readIntSliceBig(u16, data[0..2]);

        var byteI: usize = 2;
        const imageNames = parseNames(data, &byteI);
        const sheetNames = parseNames(data, &byteI);
        const animNames = parseNames(data, &byteI);
        const soundNames = parseNames(data, &byteI);

        const decompressedDataSize = std.mem.readIntSliceBig(u32, data[byteI .. byteI + 4]);
        const compressedDataSize = std.mem.readIntSliceBig(u32, data[byteI + 4 .. byteI + 8]);
        byteI += 8;

        return AssetMetadata{
            .atlasCount = atlasCount,
            .imageNames = imageNames,
            .sheetNames = sheetNames,
            .animNames = animNames,
            .soundNames = soundNames,
            .compressedData = data[byteI .. byteI + compressedDataSize],
            .decompressedDataSize = decompressedDataSize,
        };
    }
};

pub fn assetsType(comptime assetBin: []const u8) type {
    const ass = AssetMetadata.parse(assetBin);
    return struct {
        alloc: *std.mem.Allocator,
        atlases: []Texture,
        images: makeStruct(ass.imageNames, Sprite, null),
        sheets: makeStruct(ass.sheetNames, []const Sprite, null),
        anims: makeStruct(ass.animNames, Anim, null),
        sounds: makeStruct(ass.soundNames, []const u8, null),

        pub fn deinit(self: *@This()) void {
            for (self.atlases) |_, i| {
                self.atlases[i].deinit();
            }
            self.alloc.free(self.atlases);
            inline for (ass.sheetNames) |name| {
                self.alloc.free(@field(self.sheets, name));
            }
            inline for (ass.animNames) |name| {
                self.alloc.free(@field(self.anims, name).frames);
            }
            inline for (ass.soundNames) |name| {
                self.alloc.free(@field(self.sounds, name));
            }
            self.* = undefined;
        }
    };
}

const Texture = struct {
    tx: *c.SDL_Texture,
    w: UUnit,
    h: UUnit,

    pub fn deinit(self: *@This()) void {
        c.SDL_DestroyTexture(self.tx);
        self.* = undefined;
    }
};

pub const Sprite = struct {
    atlas: *const Texture,
    srcRect: URect,

    /// Consumes 10 bytes
    fn readFromBinary(atlases: []const Texture, data: []u8) Sprite {
        return Sprite{
            .atlas = &atlases[std.mem.readIntSliceBig(u16, data[0..2])],
            .srcRect = URect{
                .x = std.mem.readIntSliceBig(u16, data[2..4]),
                .y = std.mem.readIntSliceBig(u16, data[4..6]),
                .w = std.mem.readIntSliceBig(u16, data[6..8]),
                .h = std.mem.readIntSliceBig(u16, data[8..10]),
            }
        };
    }
};

pub const Anim = struct {
    pub const Frame = struct {
        sprite: Sprite,
        duration: Tick,
    };

    frames: []Frame,
};

pub const AnimState = struct {
    anim: *const Anim,
    nextAnim: ?*const Anim = null,
    currentFrame: usize = 0,
    frameTime: Tick = 0,
};

/// Convenience function for not having to create the KeyStates struct yourself
pub fn makeKeyStates(comptime keybindContainerType: type) type {
    // TODO: verify that all value types are Keycode
    return makeStruct(std.meta.fieldNames(keybindContainerType), bool, false);
}

/// Create a KeyMap struct out of defaults, loading config into it for values that exist
pub fn loadKeyConfig(filename: []const u8, comptime defaults: anytype) keymapFromDefaults(defaults) {
    var out: keymapFromDefaults(defaults) = defaults;
    var f = std.fs.cwd().openFile(filename, .{}) catch return out;
    defer f.close();
    var reader = f.reader();
    var i: usize = 0;
    var line: [1024]u8 = undefined;
    while (true) {
        const char = reader.readByte() catch null;
        if (char == null or char.? == '\n') {
            if (i > 0) {
                line[i] = 0; // Null-term
                var split = std.mem.split(line[0..i], ":");
                i = 0;
                const fieldName = split.next() orelse continue;
                const keyName = split.rest();
                const kc = c.SDL_GetKeyFromName(keyName.ptr);
                if (kc == c.SDLK_UNKNOWN) {
                    std.log.warn("unknown key '{s}', using default", .{std.mem.spanZ(keyName)});
                    continue;
                }
                inline for (comptime std.meta.fieldNames(@TypeOf(out))) |name| {
                    if (std.mem.eql(u8, name, fieldName)) {
                        @field(out, name) = @intCast(Keycode, kc);
                    }
                }
            }
            if (char == null) {
                break;
            }
        } else if (char.? != ' ' and char.? != '\r') {
            line[i] = char.?;
            i += 1;
            if (i == line.len - 1) {
                std.log.warn("key config lines too long, aborting read", .{});
                return out;
            }
        }
    }
    return out;
}

fn keymapFromDefaults(comptime defaults: anytype) type {
    return makeStruct(std.meta.fieldNames(@TypeOf(defaults)), Keycode, @intCast(Keycode, c.SDLK_UNKNOWN));
}

pub fn saveKeyConfig(filename: []const u8, keys: anytype) !void {
    var f = try std.fs.cwd().createFile(filename, .{});
    defer f.close();
    var writer = f.writer();
    inline for (comptime std.meta.fieldNames(@TypeOf(keys))) |name| {
        try std.fmt.format(writer, "{s}:{s}\n", .{ name, c.SDL_GetKeyName(@intCast(i32, @field(keys, name))) });
    }
}

fn makeStruct(comptime names: []const []const u8, comptime valueType: type, comptime defaultValue: anytype) type {
    var fields: [names.len]std.builtin.TypeInfo.StructField = undefined;
    var i = 0;
    while (i < names.len) : (i += 1) {
        fields[i].name = names[i];
        fields[i].field_type = valueType;
        fields[i].default_value = defaultValue;
        fields[i].is_comptime = false;
        fields[i].alignment = 0;
    }
    return @Type(std.builtin.TypeInfo{ .Struct = .{
        .layout = .Auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}
