#!/bin/sh
# Package the locally built, tested ARM toolkit and pin its binary checksums.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/scripts/toolkit.sh"
INPUT="$HERE/.build/modern"
OUT="$HERE/.build/release"
STAGE=$(mktemp -d "$HERE/.build/release-package.XXXXXX")
trap 'rm -rf "$STAGE"' 0
trap 'exit 1' HUP INT TERM
[ "$(cat "$INPUT/ezinject-revision")" = "$INJECTOR_REV" ]
mkdir -p "$OUT"
MANIFEST="$STAGE/$MODERN_RELEASE.sha256"
for NAME in ezinject libphpbridge.so ezinject-revision; do
    cp "$INPUT/$NAME" "$STAGE/$NAME"
    printf '%s  %s\n' "$(sha256_file "$STAGE/$NAME")" "$NAME" >> "$MANIFEST"
done
for NAME in ezinject libphpbridge.so; do
    is_arm_softfloat_header "$(od -An -tu1 -N40 "$STAGE/$NAME")" || {
        echo "ERROR: $NAME is not a 32-bit ARM soft-float ELF." >&2
        exit 1
    }
done
cp "$HERE/.build/ezinject-src/COPYING" "$STAGE/COPYING.ezinject"
cp "$HERE/THIRD_PARTY_NOTICES.md" "$STAGE/THIRD_PARTY_NOTICES.md"
cp "$HERE/native/phpbridge.c" "$STAGE/phpbridge.c"
tar -czf "$OUT/$MODERN_ASSET" -C "$STAGE" \
    ezinject libphpbridge.so ezinject-revision COPYING.ezinject THIRD_PARTY_NOTICES.md phpbridge.c
verify_modern "$INPUT" "$MANIFEST"
cp "$MANIFEST" "$HERE/releases/$MODERN_RELEASE.sha256"
cp "$MANIFEST" "$OUT/$MODERN_RELEASE.sha256"
echo "==> packaged $OUT/$MODERN_ASSET"
echo "==> updated releases/$MODERN_RELEASE.sha256; commit this before tagging the release"
