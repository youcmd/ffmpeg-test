#!/usr/bin/env bash

set -euo pipefail

PREFIX="$HOME/ffmpeg-custom"
WORKDIR="$HOME/ffmpeg-build"

FFMPEG_REPO="https://code.ffmpeg.org/Lynne/FFmpeg.git"
FFMPEG_BRANCH="aac_improv2"

DAV1D_REPO="https://code.videolan.org/videolan/dav1d.git"
SOXR_REPO="https://github.com/chirlu/soxr.git"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

echo "========================================"
echo " FFmpeg Static Build"
echo "========================================"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
mkdir -p "$PREFIX"

cd "$WORKDIR"

# ------------------------------------------------------------
# Build dav1d
# ------------------------------------------------------------

echo
echo "==> Building dav1d"

git clone --depth 1 "$DAV1D_REPO" dav1d

cd dav1d
mkdir build
cd build

meson setup .. \
    --prefix="$PREFIX" \
    --libdir="$PREFIX/lib" \
    -Ddefault_library=static \
    --buildtype=release

ninja
ninja install

cd "$WORKDIR"

# ------------------------------------------------------------
# Build soxr
# ------------------------------------------------------------

echo
echo "==> Building soxr"

git clone --depth 1 "$SOXR_REPO" soxr

cd soxr
mkdir build
cd build

cmake \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR="lib" \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DWITH_OPENMP=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    ..

cmake --build . --parallel "$(nproc)"
cmake --install .

# soxr does not provide soxr.pc through this CMake build.
mkdir -p "$PREFIX/lib/pkgconfig"

cat > "$PREFIX/lib/pkgconfig/soxr.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: soxr
Description: The SoX Resampler library
Version: 0.1.3
Libs: -L\${libdir} -lsoxr -lm
Cflags: -I\${includedir}
EOF

echo
echo "==> Checking soxr"

pkg-config --modversion soxr
pkg-config --cflags soxr
pkg-config --libs --static soxr

cd "$WORKDIR"

# ------------------------------------------------------------
# Build FFmpeg
# ------------------------------------------------------------

echo
echo "==> Building FFmpeg"

git clone \
    --branch "$FFMPEG_BRANCH" \
    "$FFMPEG_REPO" \
    ffmpeg

cd ffmpeg

COMMIT=$(git rev-parse --short HEAD)
DATE=$(git log -1 --format=%cd --date=format:'%Y%m%d')

echo
echo "FFmpeg commit : $COMMIT"
echo "FFmpeg date   : $DATE"
echo

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
    --extra-ldflags="-static"

make -j"$(nproc)"
make install

# ------------------------------------------------------------
# Build metadata for GitHub Actions
# ------------------------------------------------------------

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "commit=$COMMIT" >> "$GITHUB_OUTPUT"
    echo "date=$DATE" >> "$GITHUB_OUTPUT"
fi

echo
echo "========================================"
echo " Build complete"
echo "========================================"
echo
echo "FFmpeg:"
"$PREFIX/bin/ffmpeg" -version | head -n 3

echo
echo "Location:"
echo "$PREFIX"
