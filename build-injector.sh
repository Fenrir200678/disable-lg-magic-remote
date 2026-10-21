#!/bin/sh
# Cross-build the modern injector and PHP ABI bridge for glibc >= 2.34.
# Usage: ./build-injector.sh /path/to/sdk/share/buildroot/toolchainfile.cmake
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/scripts/toolkit.sh"
TOOLCHAIN=${1:?usage: ./build-injector.sh /path/to/toolchainfile.cmake}
TOOLCHAIN=$(cd "$(dirname "$TOOLCHAIN")" && pwd)/$(basename "$TOOLCHAIN")
REV=$INJECTOR_REV
SRC="$HERE/.build/ezinject-src"
BUILD="$HERE/.build/ezinject"
NATIVE="$HERE/.build/native"
OUT="$HERE/.build/modern"

command -v cmake >/dev/null
[ -f "$TOOLCHAIN" ] || { echo "ERROR: toolchain file not found: $TOOLCHAIN" >&2; exit 1; }
mkdir -p "$HERE/.build"
if [ ! -d "$SRC" ]; then
    git clone https://github.com/smx-smx/ezinject.git "$SRC"
fi
if [ -n "$(git -C "$SRC" status --porcelain)" ]; then
    echo "ERROR: $SRC has local changes; preserve them before rebuilding." >&2
    exit 1
fi
if ! git -C "$SRC" cat-file -e "$REV^{commit}" 2>/dev/null; then
    git -C "$SRC" fetch origin "$REV"
fi
git -C "$SRC" checkout --detach "$REV"

# The SDK targets an older libc. Explicitly select the public dlopen/dlsym
# path used on the TV's glibc >= 2.34 instead of detecting the SDK's libc.
cmake -S "$SRC" -B "$BUILD" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.14 \
    -DEZ_LIBC=generic -DHAVE_LIBDL_IN_LIBC=ON \
    -DUSE_ARM_THUMB=OFF -DUSE_CAPSTONE=OFF -DUSE_FRIDA_GUM=OFF
cmake --build "$BUILD" --target ezinject ezinject_crt --parallel 4
cmake -S "$HERE/native" -B "$NATIVE" \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DCMAKE_BUILD_TYPE=Release \
    -DEZINJECT_SOURCE_DIR="$SRC" -DEZINJECT_BUILD_DIR="$BUILD"
cmake --build "$NATIVE" --parallel 4
mkdir -p "$OUT"
cp "$BUILD/ezinject" "$NATIVE/libphpbridge.so" "$OUT/"
printf '%s\n' "$REV" > "$OUT/ezinject-revision"
MANIFEST="$OUT/build-manifest.sha256"
: > "$MANIFEST"
for NAME in ezinject libphpbridge.so ezinject-revision; do
    printf '%s  %s\n' "$(sha256_file "$OUT/$NAME")" "$NAME" >> "$MANIFEST"
done
echo "==> built $OUT/ezinject and libphpbridge.so"
