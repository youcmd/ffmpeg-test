#!/usr/bin/env bash

set -euo pipefail

PREFIX="$HOME/ffmpeg-custom"
WORKDIR="$HOME/ffmpeg-build"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

rm -rf "$WORKDIR" "$PREFIX"
mkdir -p "$WORKDIR" "$PREFIX"

cd "$WORKDIR"

# dav1d
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

# soxr
git clone \
  https://git.code.sf.net/p/soxr/code \
  soxr

cd soxr

git checkout 945b592b70470e29f917f4de89b4281fbbd540c0

sed -i 's/VERSION 3.1 /VERSION 3.1...3.10 /' CMakeLists.txt
sed -i 's/NOT WIN32/1/' src/CMakeLists.txt

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DWITH_OPENMP=OFF \
  -DBUILD_TESTS=OFF \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_SHARED_LIBS=OFF

cmake --build build --parallel "$(nproc)"
cmake --install build

cd "$WORKDIR"

# FFmpeg
git clone \
  --branch aac_improv2 \
  https://code.ffmpeg.org/Lynne/FFmpeg.git \
  ffmpeg

cd ffmpeg

./configure \
  --prefix="$PREFIX" \
  --pkg-config-flags="--static" \
  --enable-gpl \
  --enable-static \
  --disable-shared \
  --enable-small \
  --disable-debug \
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
  --extra-ldflags="-L$PREFIX/lib" \
  --extra-libs="-lsoxr -lm -pthread"

make -j"$(nproc)"
make install

strip "$PREFIX/bin/ffmpeg"
