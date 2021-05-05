const c = @import("./c.zig").c;

pub const SUnit = i32;
pub const UUnit = u16;
pub const Rect = struct {
    x: SUnit = 0,
    y: SUnit = 0,
    w: UUnit,
    h: UUnit,

    pub fn toSDL(self: *const Rect) c.SDL_Rect {
        return .{ .x = self.x, .y = self.y, .w = self.w, .h = self.h };
    }
};
pub const URect = struct {
    x: UUnit,
    y: UUnit,
    w: UUnit,
    h: UUnit,

    pub fn toSDL(self: *const URect) c.SDL_Rect {
        return .{ .x = self.x, .y = self.y, .w = self.w, .h = self.h };
    }
};

pub const Color = c.SDL_Color;
pub fn RGBA(r: u8, g: u8, b: u8, a: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}
pub fn RGB(r: u8, g: u8, b: u8) Color {
    return RGBA(r, g, b, 255);
}

pub const Tick = u32;
pub const Keycode = u32;
