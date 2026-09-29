#!/usr/bin/env bash

set -euo pipefail

PREFIX="$HOME/ffmpeg-custom"
WORKDIR="$HOME/ffmpeg-build"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

rm -rf "$WORKDIR"
rm -rf "$PREFIX"

mkdir -p "$WORKDIR"
mkdir -p "$PREFIX"

cd "$WORKDIR"

# ============================================================
# dav1d
# ============================================================

echo "==> Building dav1d"

git clone --depth 1 \
  https://code.videolan.org/videolan/dav1d.git \
  dav1d

meson setup dav1d/build dav1d \
  --prefix="$PREFIX" \
  --libdir=lib \
  -Ddefault_library=static \
  --buildtype=release

ninja -C dav1d/build
ninja -C dav1d/build install


# ============================================================
# soxr
# ============================================================

echo "==> Building soxr"

git clone \
  https://git.code.sf.net/p/soxr/code \
  soxr

cd soxr

# Fix newer CMake
sed -i 's/VERSION 3.1 /VERSION 3.1...3.10 /' CMakeLists.txt

# Fix non-Windows configuration
sed -i 's/NOT WIN32/1/' src/CMakeLists.txt

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_INSTALL_LIBDIR=lib \
  -DWITH_OPENMP=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build build --parallel "$(nproc)"

cmake --install build

cd "$WORKDIR"


# ============================================================
# Check soxr
# ============================================================

echo "==> Checking soxr"

test -f "$PREFIX/include/soxr.h"
test -f "$PREFIX/lib/libsoxr.a"
test -f "$PREFIX/lib/pkgconfig/soxr.pc"

echo "soxr library:"
ls -lh "$PREFIX/lib/libsoxr.a"

echo
echo "soxr pkg-config:"
cat "$PREFIX/lib/pkgconfig/soxr.pc"

echo
echo "pkg-config:"
pkg-config --cflags soxr
pkg-config --libs soxr
pkg-config --static --libs soxr


# ============================================================
# FFmpeg
# ============================================================

echo "==> Building FFmpeg"

git clone \
  --branch aac_improv2 \
  https://code.ffmpeg.org/Lynne/FFmpeg.git \
  ffmpeg

cd ffmpeg

COMMIT=$(git rev-parse --short HEAD)
DATE=$(git log -1 --format=%cd --date=format:%Y%m%d)

./configure \
  --prefix="$PREFIX" \
  --pkg-config-flags="--static" \
  --enable-gpl \
  --enable-static \
  --disable-shared \
  --enable-small \
  --disable-doc \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-avdevice \
  --enable-libx264 \
  --enable-libvpx \
  --enable-libopus \
  --enable-libdav1d \
  --enable-libsoxr \
  --extra-cflags="-I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib -static -pthread"

make -j"$(nproc)"

make install


# ============================================================
# GitHub Actions outputs
# ============================================================

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "commit=$COMMIT" >> "$GITHUB_OUTPUT"
  echo "date=$DATE" >> "$GITHUB_OUTPUT"
fi


# ============================================================
# Done
# ============================================================

echo
echo "========================================"
echo "Build complete!"
echo "========================================"
echo
echo "FFmpeg:"
echo "$PREFIX/bin/ffmpeg"
echo
echo "Version:"
"$PREFIX/bin/ffmpeg" -version | head -n 1
