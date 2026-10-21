# Shared host-side helpers, sourced after HERE is set by the caller.
. "$HERE/releases/toolkit.conf"

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | sed 's/^.*= //'
    else
        echo "ERROR: install sha256sum, shasum, or openssl." >&2
        return 1
    fi
}

verify_modern() (
    VERIFY_DIR=$1
    MANIFEST=$2
    [ -r "$MANIFEST" ] || exit 1
    COUNT=0
    while read -r EXPECTED NAME; do
        case "$NAME" in ezinject|libphpbridge.so|ezinject-revision) ;; *) exit 1 ;; esac
        [ "${#EXPECTED}" -eq 64 ] || exit 1
        case "$EXPECTED" in *[!0-9a-f]*) exit 1 ;; esac
        [ -s "$VERIFY_DIR/$NAME" ] || exit 1
        ACTUAL=$(sha256_file "$VERIFY_DIR/$NAME") || exit 1
        [ "$ACTUAL" = "$EXPECTED" ] || exit 1
        COUNT=$((COUNT + 1))
    done < "$MANIFEST"
    [ "$COUNT" -eq 3 ] || exit 1
    [ "$(cat "$VERIFY_DIR/ezinject-revision")" = "$INJECTOR_REV" ]
)

download_file() {
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --retry 2 --output "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$2" "$1"
    else
        echo "ERROR: install curl or wget to download the release." >&2
        return 1
    fi
}

ensure_modern_release() (
    CACHE="$HERE/.build/modern"
    MANIFEST="$HERE/releases/$MODERN_RELEASE.sha256"
    if verify_modern "$CACHE" "$MANIFEST"; then
        exit 0
    fi
    mkdir -p "$HERE/.build"
    STAGE=$(mktemp -d "$HERE/.build/modern-download.XXXXXX")
    trap 'rm -rf "$STAGE"' 0
    trap 'exit 1' HUP INT TERM
    echo "==> downloading verified modern ARM toolkit $MODERN_RELEASE"
    URL="https://github.com/$RELEASE_REPO/releases/download/$MODERN_RELEASE/$MODERN_ASSET"
    download_file "$URL" "$STAGE/toolkit.tar.gz" || exit 1
    mkdir "$STAGE/payload"
    # Stream only the three expected members to explicit paths. Archive paths,
    # links, and other entries cannot write outside this staging directory.
    for NAME in ezinject libphpbridge.so ezinject-revision; do
        tar -xOzf "$STAGE/toolkit.tar.gz" "$NAME" > "$STAGE/payload/$NAME" || exit 1
    done
    if ! verify_modern "$STAGE/payload" "$MANIFEST"; then
        echo "ERROR: release checksum or revision mismatch; no TV files were changed." >&2
        exit 1
    fi
    mkdir -p "$CACHE"
    for NAME in ezinject libphpbridge.so ezinject-revision; do
        mv -f "$STAGE/payload/$NAME" "$CACHE/$NAME"
    done
    chmod +x "$CACHE/ezinject"
)

# ELF32, little-endian, EM_ARM, EABI5, and no hard-float ABI flag. Header bytes come
# from od, either on a local binary or the TV's actual /proc/<pid>/exe.
is_arm_softfloat_header() (
    set -- $1
    [ "$#" -eq 40 ] || exit 1
    [ "$1 $2 $3 $4 $5 $6" = '127 69 76 70 1 1' ] || exit 1
    shift 18
    [ "$1 $2" = '40 0' ] || exit 1
    shift 19
    [ "$3" -eq 5 ] || exit 1
    [ "$(($1 & 4))" -eq 0 ]
)
