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
[ -f "$DIR/ezinject" ] && [ -f "$DIR/pointer-hook.php" ] && [ -f "$LIBPHP" ] || { echo "missing files; abort"; exit 0; }

inject() {
    LP=$(pidof lginput2)
    [ -n "$LP" ] || return 1
    # Guard against double-injection (otherwise lginput2 crashes): skip if libphp is
    # already mapped into it.
    if grep -q libphp "/proc/$LP/maps" 2>/dev/null; then
        echo "lginput2=$LP already has the hook; skipping"
        return 0
    fi
    echo "injecting into lginput2=$LP (uptime=$(cut -d. -f1 /proc/uptime)s)"
    "$DIR/ezinject" "$LP" "$LIBPHP" "$DIR/pointer-hook.php" lginput2
    sleep 3
    NP=$(pidof lginput2)
    if [ "$NP" = "$LP" ] && grep -q libphp "/proc/$NP/maps" 2>/dev/null; then
        echo "OK: hook injected, lginput2 still $NP (not restarted)"
    else
        echo "WARN: inject result unexpected (lginput2 was $LP, now $NP)"
    fi
}

# Wait for lginput2 to exist at boot.
i=0
while [ -z "$(pidof lginput2)" ]; do
    sleep 2; i=$((i + 1))
    [ $i -ge 90 ] && { echo "lginput2 never appeared; abort"; exit 0; }
done
inject   # inject as soon as lginput2 exists — injection is non-disruptive, no settle needed

# Watch for lginput2 respawning (e.g. a crash) and re-inject the fresh instance.
last=$(pidof lginput2)
while true; do
    sleep 10
    cur=$(pidof lginput2)
    if [ -n "$cur" ] && [ "$cur" != "$last" ]; then
        echo "lginput2 changed $last -> $cur; re-injecting"
        sleep 3
        inject
        last=$(pidof lginput2)
    fi
done
