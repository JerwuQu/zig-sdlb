# zig-sdlb

**Work in progress - things will break and project might get renamed**

A wrapper around SDL for convenience when writing small pixel-art games.

Mostly made for usage in gamejams to reduce time spent on boilerplate for asset loading, build pipeline, and SDL rendering.

## Features

- Automatic integer scaling of pixels, with borders to maintain aspect ratio
- Script for converting assets for embedding into the executable
- Easy usage of images (png), spritesheets (png), animations (aseprite), sounds (opus), and maps with tilesheets (Tiled)
- Very basic keymap config to allow users to reconfigure default bindings

### Not in scope

- Float scaling: looks blurry and not appropriate for pixel-art
- Savedata and configs: you can use any serialisation you want
- ECS or alternatives: there are many ways to do this and such a decision shouldn't be made in this lib
- Assets in a file instead of embedded in executable: asset data is compressed and should be pretty compact for most small games

## Dependencies

### zig-sdlb

Pay attention to which of these need a license note in your game!

- SDL2
- zstd
- opusfile (and its dependencies: ogg and opus)

### Asset build

- `make`

#### `compile_assets.py`

- Python 3
- Pillow
- `zstd`
- `aseprite` (if you have any such files)
- `tiled` (if you have any such files)

## License

MIT
