#!/bin/sh
# Deploy the LG Magic Remote pointer-disable hook to a rooted webOS TV.
#
#   ./deploy.sh [--check] [--local-build] user@host
#
# Pushes the working files (tv/) plus the prebuilt injection toolkit
# (ezinject / libphp / hookfactory from Simon34545/lginputhook), installs the
# webosbrew boot hook, and injects immediately. Re-running is safe — the injector
# skips if lginput2 is already hooked, and nothing here restarts lginput2.
#
# Requirements (on this machine): git, ssh, tar, curl/wget, SHA-256 tool.
# On the TV: rooted (webosbrew) with
# root SSH (key auth recommended). The prebuilt binaries are 32-bit ARM EABI5
# soft-float — fine for an LG C9; verify for other models (see README).
set -eu

TV=
CHECK_ONLY=0
LOCAL_BUILD=0
for ARG in "$@"; do
    case "$ARG" in
        --check) CHECK_ONLY=1 ;;
        --local-build) LOCAL_BUILD=1 ;;
        --help|-h) echo "usage: ./deploy.sh [--check] [--local-build] user@TV-IP"; exit 0 ;;
        -*) echo "ERROR: unknown option: $ARG" >&2; exit 1 ;;
        *) [ -z "$TV" ] || { echo "ERROR: provide exactly one TV address." >&2; exit 1; }; TV=$ARG ;;
    esac
done
[ -n "$TV" ] || { echo "usage: ./deploy.sh [--check] [--local-build] user@TV-IP" >&2; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/scripts/toolkit.sh"
REF="$HERE/lginputhook-ref"
IH="$REF/service/inputhook"
# v1.4.0 is the last PHP-based toolkit; v1.5.0 replaced it with inputhookpp.
MODE=legacy
EZINJECT="$IH/ezinject"
BRIDGE=

# is the TV reachable
if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$TV" 'true' 2>/dev/null; then
    echo "ERROR: can't SSH to $TV." >&2
    echo "  - Is the TV on (not in standby — that drops SSH)? Is the IP right?" >&2
    echo "  - Is root SSH enabled (webosbrew Homebrew Channel) with your key authorized?" >&2
    exit 1
fi

if [ "$(ssh "$TV" 'id -u')" != 0 ]; then
    echo "ERROR: SSH must connect as root (use root@TV-IP or a root SSH alias)." >&2
    exit 1
fi
TARGET_HEADER=$(ssh "$TV" 'set -- $(pidof lginput2); [ "$#" -eq 1 ] || exit 1; od -An -tu1 -N40 "/proc/$1/exe"') || {
    echo "ERROR: cannot inspect a single running lginput2 process; turn on the TV and retry." >&2
    exit 1
}
if ! is_arm_softfloat_header "$TARGET_HEADER"; then
    echo "ERROR: lginput2 must be a 32-bit little-endian ARM soft-float process." >&2
    echo "No TV files were changed. Other process architectures are not supported." >&2
    exit 1
fi

# Choose the loader for the TV's libc, independently of the host OS.
GLIBC=$(ssh "$TV" 'getconf GNU_LIBC_VERSION 2>/dev/null || true')
case "$GLIBC" in
    "glibc "*)
        VERSION=${GLIBC#glibc }
        MAJOR=${VERSION%%.*}
        MINOR=${VERSION#*.}
        MINOR=${MINOR%%.*}
        case "$MAJOR:$MINOR" in
            *[!0-9:]*|:*|*:)
                echo "ERROR: cannot parse TV libc version: $GLIBC" >&2
                exit 1
                ;;
        esac
        if [ "$MAJOR" -gt 2 ] || { [ "$MAJOR" -eq 2 ] && [ "$MINOR" -ge 34 ]; }; then
            MODE=modern
            EZINJECT="$HERE/.build/modern/ezinject"
            BRIDGE="$HERE/.build/modern/libphpbridge.so"
            if [ "$LOCAL_BUILD" -eq 1 ]; then
                if ! verify_modern "$HERE/.build/modern" "$HERE/.build/modern/build-manifest.sha256"; then
                    echo "ERROR: local build missing or changed; run ./build-injector.sh first (see README)." >&2
                    exit 1
                fi
            else
                ensure_modern_release || exit 1
            fi
        fi
        ;;
    *)
        echo "ERROR: cannot determine TV glibc version with getconf GNU_LIBC_VERSION." >&2
        exit 1
        ;;
esac
echo "==> $TV uses $GLIBC ($MODE injector)"

# Pin the toolkit, including clones left behind by older deploy.sh versions.
if [ ! -d "$REF" ]; then
    echo "==> cloning lginputhook (prebuilt ezinject/libphp/hookfactory)"
    git clone --depth 1 --branch v1.4.0 https://github.com/Simon34545/lginputhook "$REF"
fi
if [ ! -d "$REF/.git" ]; then
    echo "ERROR: $REF is not a toolkit Git checkout." >&2
    exit 1
fi
if [ "$(git -C "$REF" rev-parse HEAD)" != "$TOOLKIT_REV" ]; then
    if [ -n "$(git -C "$REF" status --porcelain)" ]; then
        echo "ERROR: $REF has local changes; preserve them before retrying." >&2
        exit 1
    fi
    echo "==> selecting compatible lginputhook v1.4.0 ($TOOLKIT_REV)"
    git -C "$REF" fetch --depth 1 origin "$TOOLKIT_REV"
    git -C "$REF" checkout --detach "$TOOLKIT_REV"
fi

# match the libphp build to the TV's libcrypt.
LC=$(ssh "$TV" '[ -e /usr/lib/libcrypt.so.2 ] && echo libcrypt2 || echo libcrypt1')
echo "==> $TV uses $LC"

# Validate the entire payload before creating or changing files on the TV.
for file in "$EZINJECT" ${BRIDGE:+"$BRIDGE"} "$IH/hookfactory.php" "$IH/$LC/libphp.so" \
    "$HERE/tv/pointer-hook.php" "$HERE/tv/inject-pointer-hook.sh" \
    "$HERE/tv/disable-magic-pointer.sh"; do
    if [ ! -s "$file" ] || [ ! -r "$file" ]; then
        echo "ERROR: missing, empty, or unreadable deployment file: $file" >&2
        exit 1
    fi
done
for FILE in "$EZINJECT" ${BRIDGE:+"$BRIDGE"} "$IH/$LC/libphp.so"; do
    if ! is_arm_softfloat_header "$(od -An -tu1 -N40 "$FILE")"; then
        echo "ERROR: incompatible ARM deployment file: $FILE" >&2
        exit 1
    fi
done
if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "==> checks passed; payloads are ready. No TV files were changed and no injection was attempted."
    exit 0
fi

# Replace files atomically: truncating a mapped .so on a repeat deployment
# could crash the process that is already using it. scp may be absent on webOS.
push() { echo "    -> $2"; ssh "$TV" "cat > '$2.upload-$$' && mv -f '$2.upload-$$' '$2'" < "$1"; }

# create dirs and push files.
echo "==> deploying files"
ssh "$TV" "mkdir -p /home/root/magic-pointer/inputhook/$LC /var/lib/webosbrew/init.d"
push "$EZINJECT"                         "/home/root/magic-pointer/inputhook/ezinject"
if [ "$MODE" = modern ]; then
    push "$BRIDGE" "/home/root/magic-pointer/inputhook/libphpbridge.so"
fi
printf '%s\n' "$MODE" | ssh "$TV" 'cat > /home/root/magic-pointer/inputhook/toolkit-mode'
push "$IH/hookfactory.php"               "/home/root/magic-pointer/inputhook/hookfactory.php"
push "$IH/$LC/libphp.so"                 "/home/root/magic-pointer/inputhook/$LC/libphp.so"
push "$HERE/tv/pointer-hook.php"         "/home/root/magic-pointer/inputhook/pointer-hook.php"
push "$HERE/tv/inject-pointer-hook.sh"   "/home/root/magic-pointer/inject-pointer-hook.sh"
ssh "$TV" "chmod +x /home/root/magic-pointer/inputhook/ezinject \
    /home/root/magic-pointer/inject-pointer-hook.sh"

# inject now and will auto-injects at every boot via the hook
echo "==> injecting into the running lginput2"
if ! ssh "$TV" 'sh /home/root/magic-pointer/inject-pointer-hook.sh --once'; then
    ssh "$TV" 'tail -20 /home/root/magic-pointer/inject.log' >&2
    echo "ERROR: hook installation failed; autostart was not installed." >&2
    exit 1
fi

# Enable autostart only after the initial injection succeeds.
push "$HERE/tv/disable-magic-pointer.sh" "/var/lib/webosbrew/init.d/disable-magic-pointer"
ssh "$TV" 'chmod +x /var/lib/webosbrew/init.d/disable-magic-pointer'
ssh "$TV" 'sh /var/lib/webosbrew/init.d/disable-magic-pointer'

echo "==> done. Shake the remote, pointer should be gone, buttons still work."
