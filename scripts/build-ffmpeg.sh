#!/usr/bin/env bash

set -euo pipefail

PREFIX="$HOME/ffmpeg-custom"
WORKDIR="$HOME/ffmpeg-build"

FFMPEG_REPO="https://code.ffmpeg.org/Lynne/FFmpeg.git"
FFMPEG_BRANCH="aac_improv2"

DAV1D_REPO="https://code.videolan.org/videolan/dav1d.git"

SOXR_REPO="https://git.code.sf.net/p/soxr/code"
SOXR_COMMIT="945b592b70470e29f917f4de89b4281fbbd540c0"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$PREFIX"

cd "$WORKDIR"

# ============================================================
# dav1d
# ============================================================

echo "==> Building dav1d"

git clone --depth 1 "$DAV1D_REPO" dav1d
cd dav1d

meson setup build \
    --prefix="$PREFIX" \
    --libdir=lib \
    -Ddefault_library=static \
    --buildtype=release

ninja -C build
ninja -C build install

cd "$WORKDIR"

# ============================================================
# soxr
# ============================================================

echo "==> Building soxr"

git clone "$SOXR_REPO" soxr
cd soxr

git checkout "$SOXR_COMMIT"

# Patches from FFmpeg's build recipe
sed -i 's/VERSION 3.1 /VERSION 3.1...3.10 /g' CMakeLists.txt
sed -i 's/NOT WIN32/1/g' src/CMakeLists.txt

mkdir build
cd build

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DWITH_OPENMP=ON \
    -DBUILD_TESTS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF

make -j"$(nproc)"
make install

# Add OpenMP dependency for static linking
echo "Libs.private: -lgomp" >> "$PREFIX/lib/pkgconfig/soxr.pc"

cd "$WORKDIR"

# ============================================================
# FFmpeg
# ============================================================

echo "==> Building FFmpeg"

git clone \
    --branch "$FFMPEG_BRANCH" \
    "$FFMPEG_REPO" \
    ffmpeg

cd ffmpeg

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
# Done
# ============================================================

echo
echo "========================================"
echo "BUILD COMPLETE"
echo "========================================"
echo
echo "FFmpeg:"
echo "$PREFIX/bin/ffmpeg"
echo
echo "Version:"
"$PREFIX/bin/ffmpeg" -version | head -n 1
