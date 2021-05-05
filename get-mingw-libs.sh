#!/bin/sh
mingwget() {
    curl -LO "https://repo.msys2.org/mingw/x86_64/$1"
    tar axvf "$1" mingw64
    rm "$1"
}
mingwget 'mingw-w64-x86_64-SDL2-2.0.14-2-any.pkg.tar.zst'
mingwget 'mingw-w64-x86_64-zstd-1.4.9-1-any.pkg.tar.zst'
mingwget 'mingw-w64-x86_64-opusfile-0.12-1-any.pkg.tar.zst'
mingwget 'mingw-w64-x86_64-libogg-1.3.4-3-any.pkg.tar.xz'
mingwget 'mingw-w64-x86_64-opus-1.3.1-1-any.pkg.tar.xz'