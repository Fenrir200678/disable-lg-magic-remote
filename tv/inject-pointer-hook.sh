#!/bin/sh
# Inject the pointer-disabling hook into the running lginput2 (via ezinject), and
# keep it injected across any lginput2 respawn. This is non-disruptive. It does
# not restart lginput2, so the Magic Remote's radio link is never disturbed
# Launched detached at boot by the webosbrew hook (disable-magic-pointer).
DIR=/home/root/magic-pointer/inputhook
LOG=/home/root/magic-pointer/inject.log
exec >>"$LOG" 2>&1
echo "=== injector start $(date) uptime=$(cut -d. -f1 /proc/uptime)s ==="

# Pick the libphp build matching the TV's libcrypt (lginputhook ships both variants).
LC=$([ -e /usr/lib/libcrypt.so.2 ] && echo libcrypt2 || echo libcrypt1)
LIBPHP="$DIR/$LC/libphp.so"
MODE=$(cat "$DIR/toolkit-mode" 2>/dev/null || echo legacy)
[ -f "$DIR/ezinject" ] && [ -f "$DIR/hookfactory.php" ] && [ -f "$DIR/pointer-hook.php" ] && [ -f "$LIBPHP" ] || { echo "missing files; abort"; exit 1; }
case "$MODE" in
    modern) [ -f "$DIR/libphpbridge.so" ] || { echo "missing PHP bridge; abort"; exit 1; } ;;
    legacy) ;;
    *) echo "unknown toolkit mode: $MODE"; exit 1 ;;
esac

inject() {
    LP=$(pidof lginput2)
    [ -n "$LP" ] || return 1
    # Guard against double-injection (otherwise lginput2 crashes): skip if libphp is
    # already mapped into it.
    if grep -q libphp "/proc/$LP/maps" 2>/dev/null; then
        if [ -f "/tmp/magic-pointer-reverted-$LP" ]; then
            echo "lginput2=$LP was rolled back; refusing reinjection into the same process"
            return 1
        fi
        if grep -q '^installed settings-dpad-v1$' "/tmp/magic-pointer-ready-$LP" 2>/dev/null; then
            echo "lginput2=$LP already has the hook; skipping"
            return 0
        fi
        echo "libphp is loaded without the current hook marker; refusing double-injection"
        echo "An older hook needs a fresh lginput2 process; no service restart attempted."
        return 1
    fi
    rm -f "/tmp/magic-pointer-ready-$LP" "/tmp/magic-pointer-revert-$LP" "/tmp/magic-pointer-reverted-$LP"
    echo "injecting into lginput2=$LP (uptime=$(cut -d. -f1 /proc/uptime)s)"
    if [ "$MODE" = modern ]; then
        "$DIR/ezinject" -l /home/root/magic-pointer/module.log "$LP" \
            "$DIR/libphpbridge.so" "$LIBPHP" "$DIR/pointer-hook.php" lginput2 || return 1
    else
        "$DIR/ezinject" "$LP" "$LIBPHP" "$DIR/pointer-hook.php" lginput2 || return 1
    fi
    # PHP runs on its own thread. Mapping libphp alone does not prove that
    # PHP has started or that the three hooks have been installed.
    attempt=0
    while [ "$attempt" -lt 15 ]; do
        NP=$(pidof lginput2)
        [ "$NP" = "$LP" ] || { echo "ERROR: lginput2 changed $LP -> $NP during injection"; return 1; }
        if grep -q '^installed settings-dpad-v1$' "/tmp/magic-pointer-ready-$LP" 2>/dev/null && grep -q libphp "/proc/$LP/maps" 2>/dev/null; then
            echo "OK: all hooks ready, lginput2 still $LP (not restarted)"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "ERROR: PHP hook did not become ready; inspect /tmp/pointer-hook.log and module.log"
    return 1
}

# Wait for lginput2 to exist at boot.
i=0
while [ -z "$(pidof lginput2)" ]; do
    sleep 2; i=$((i + 1))
    [ $i -ge 90 ] && { echo "lginput2 never appeared; abort"; exit 0; }
done
inject || exit 1
[ "${1:-}" = --once ] && exit 0

# Keep a single watcher when deploy.sh is run repeatedly.
LOCK=/home/root/magic-pointer/watcher.lock
if ! mkdir "$LOCK" 2>/dev/null; then
    OLD=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
        echo "watcher already running as $OLD"
        exit 0
    fi
    rm -f "$LOCK/pid"
    rmdir "$LOCK" 2>/dev/null && mkdir "$LOCK" 2>/dev/null || exit 1
fi
echo "$$" > "$LOCK/pid"
trap 'rm -f "$LOCK/pid"; rmdir "$LOCK" 2>/dev/null' 0
trap 'exit 0' HUP INT TERM

# Watch for lginput2 respawning (e.g. a crash) and re-inject the fresh instance.
last=$(pidof lginput2)
while true; do
    sleep 10
    cur=$(pidof lginput2)
    if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
        echo "lginput2 changed $last -> $cur; re-injecting"
        sleep 3
        inject || exit 1
        last=$(pidof lginput2)
    fi
done
