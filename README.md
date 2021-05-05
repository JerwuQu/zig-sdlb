# zig-sdlb

**Work in progress - things will break and project might get renamed**

A wrapper around SDL for convenience when writing small pixel-art games.

Mostly made for usage in gamejams to reduce time spent on boilerplate for asset loading, build pipeline, and SDL rendering.

## Features

- Automatic integer scaling of pixels, with borders to maintain aspect ratio
- Script for converting assets for embedding into the executable
- Easy usage of sprites (png), animations (aseprite), and sounds (opus)

### Not in scope

- Float scaling: looks blurry and not appropriate for pixel-art
- Savedata and configs: you can use any serialisation you want
- ECS or alternatives: there are many ways to do this and such a decision shouldn't be made in this lib
- Assets in a file instead of embedded in executable: asset data is compressed and should be pretty compact for most small games

### TBD

- Fonts: support for bitmap fonts would be nice
- Keymap config (i.e. `game_name.keymap`): would be needed for pretty much every game regardless, even when some other game config isn't

## Dependencies

### zig-sdlb

- SDL2
- zstd
- opusfile (and its dependencies)

### Asset build

- `make`

#### `compile_assets.py`

- Python 3
- Pillow
- `zstd`
- `aseprite` (if you have any such files)

## License

MIT