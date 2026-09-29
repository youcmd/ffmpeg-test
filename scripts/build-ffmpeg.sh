#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

PREFIX="$HOME/ffmpeg-custom"
WORKDIR="$HOME/ffmpeg-build"

FFMPEG_REPO="https://code.ffmpeg.org/Lynne/FFmpeg.git"
FFMPEG_BRANCH="aac_improv2"

DAV1D_REPO="https://code.videolan.org/videolan/dav1d.git"
SOXR_REPO="https://github.com/chirlu/soxr.git"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# ============================================================
# Helper functions
# ============================================================

die()
{
    echo
    echo "ERROR: $*" >&2
    exit 1
}

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

# ============================================================
# Start
# ============================================================

section "FFmpeg Static Build"

echo "PREFIX  : $PREFIX"
echo "WORKDIR : $WORKDIR"
echo "FFmpeg  : $FFMPEG_BRANCH"

echo
echo "PKG_CONFIG_PATH:"
echo "$PKG_CONFIG_PATH"

# ============================================================
# Clean build directory
# ============================================================

section "Preparing Build Directory"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
mkdir -p "$PREFIX"

cd "$WORKDIR"

# ============================================================
# Build dav1d
# ============================================================

section "Building dav1d"

git clone \
    --depth 1 \
    "$DAV1D_REPO" \
    dav1d

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

echo
echo "dav1d installed."

echo
echo "dav1d files:"
find "$PREFIX" -type f | grep -E 'dav1d|pkgconfig' || true

# ============================================================
# Build soxr
# ============================================================

section "Building soxr"

git clone \
    --depth 1 \
    "$SOXR_REPO" \
    soxr

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

cd "$WORKDIR"

# ============================================================
# Verify soxr installation
# ============================================================

section "Checking soxr"

echo "==> Installed soxr files"

find "$PREFIX" -type f \
    \( \
        -name 'libsoxr*' \
        -o -name 'soxr.h' \
        -o -name 'soxr.pc' \
        -o -name 'soxr-lsr.pc' \
    \) \
    -print

# ------------------------------------------------------------
# Check static library
# ------------------------------------------------------------

echo
echo "==> Checking libsoxr.a"

if [[ ! -f "$PREFIX/lib/libsoxr.a" ]]; then
    die "libsoxr.a was not installed"
fi

ls -lh "$PREFIX/lib/libsoxr.a"

# ------------------------------------------------------------
# Check header
# ------------------------------------------------------------

echo
echo "==> Checking soxr.h"

if [[ ! -f "$PREFIX/include/soxr.h" ]]; then
    die "soxr.h was not installed"
fi

ls -lh "$PREFIX/include/soxr.h"

# ------------------------------------------------------------
# Check pkg-config
# ------------------------------------------------------------

echo
echo "==> Checking soxr.pc"

if [[ ! -f "$PREFIX/lib/pkgconfig/soxr.pc" ]]; then
    die "soxr.pc was not installed"
fi

cat "$PREFIX/lib/pkgconfig/soxr.pc"

echo
echo "==> pkg-config version"

pkg-config --modversion soxr

echo
echo "==> pkg-config cflags"

pkg-config --cflags soxr

echo
echo "==> pkg-config static libs"

pkg-config --libs --static soxr

# ============================================================
# Direct soxr compiler/linker test
# ============================================================

section "Direct soxr Compiler/Linker Test"

cat > /tmp/test-soxr.c <<'EOF'
#include <soxr.h>

int main(void)
{
    soxr_error_t error = NULL;

    soxr_t soxr = soxr_create(
        48000,
        44100,
        2,
        &error,
        NULL,
        NULL,
        NULL
    );

    if (soxr)
        soxr_delete(soxr);

    return error != NULL;
}
EOF

echo "Source:"
cat /tmp/test-soxr.c

echo
echo "Compiler:"
cc --version | head -n 1

echo
echo "Compile/link command:"
echo "cc -I$PREFIX/include /tmp/test-soxr.c -L$PREFIX/lib -lsoxr -lm -o /tmp/test-soxr"

cc \
    -I"$PREFIX/include" \
    /tmp/test-soxr.c \
    -L"$PREFIX/lib" \
    -lsoxr \
    -lm \
    -o /tmp/test-soxr

echo
echo "SUCCESS: direct soxr compile/link test passed."

# ============================================================
# Clone FFmpeg
# ============================================================

section "Building FFmpeg"

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

# ============================================================
# FFmpeg environment
# ============================================================

section "FFmpeg Build Environment"

echo "PREFIX:"
echo "$PREFIX"

echo
echo "PKG_CONFIG_PATH:"
echo "$PKG_CONFIG_PATH"

echo
echo "soxr pkg-config:"
pkg-config --modversion soxr
pkg-config --cflags soxr
pkg-config --libs --static soxr

echo
echo "Compiler:"
cc --version | head -n 1

echo
echo "Library:"
ls -lh "$PREFIX/lib/libsoxr.a"

echo
echo "Header:"
ls -lh "$PREFIX/include/soxr.h"

# ============================================================
# FFmpeg configure
# ============================================================

section "Running FFmpeg configure"

set +e

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
    --extra-ldflags="-L$PREFIX/lib -static"

CONFIGURE_STATUS=$?

set -e

# ============================================================
# Dump configure log on failure
# ============================================================

if [[ $CONFIGURE_STATUS -ne 0 ]]; then

    echo
    echo "============================================================"
    echo "FFmpeg configure FAILED"
    echo "============================================================"

    echo
    echo "==> libsoxr references in config.log"

    grep -n -i -C 20 "soxr" \
        ffbuild/config.log \
        || true

    echo
    echo "==> soxr_create references in config.log"

    grep -n -i -C 20 "soxr_create" \
        ffbuild/config.log \
        || true

    echo
    echo "==> Last 150 lines of config.log"

    tail -n 150 ffbuild/config.log

    exit "$CONFIGURE_STATUS"
fi

echo
echo "FFmpeg configure succeeded."

# ============================================================
# Build FFmpeg
# ============================================================

section "Compiling FFmpeg"

make -j"$(nproc)"

# ============================================================
# Install FFmpeg
# ============================================================

section "Installing FFmpeg"

make install

# ============================================================
# Final verification
# ============================================================

section "Final Build"

if [[ ! -x "$PREFIX/bin/ffmpeg" ]]; then
    die "FFmpeg binary was not installed"
fi

echo
echo "FFmpeg binary:"
ls -lh "$PREFIX/bin/ffmpeg"

echo
echo "FFmpeg version:"
"$PREFIX/bin/ffmpeg" -version | head -n 5

# ============================================================
# GitHub Actions outputs
# ============================================================

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "commit=$COMMIT" >> "$GITHUB_OUTPUT"
    echo "date=$DATE" >> "$GITHUB_OUTPUT"
fi

# ============================================================
# Done
# ============================================================

section "BUILD COMPLETE"

echo
echo "FFmpeg:"
echo "$PREFIX/bin/ffmpeg"

echo
echo "Commit:"
echo "$COMMIT"

echo
echo "Date:"
echo "$DATE"

echo
echo "Static libraries:"
find "$PREFIX/lib" -maxdepth 1 -type f -name '*.a' -printf '%f\n' | sort
