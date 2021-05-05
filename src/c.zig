pub const c = @cImport({
    @cInclude("SDL.h");
    @cInclude("opus/opusfile.h");
    @cInclude("zstd.h");
});
