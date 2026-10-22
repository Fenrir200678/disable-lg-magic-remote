#!/bin/sh
# Restore native input without restarting lginput2. PHP stays mapped to retain
# in-flight callback storage; all three replaced functions are reverted.
set -eu
BASE=/home/root/magic-pointer
BOOT=/var/lib/webosbrew/init.d/disable-magic-pointer
if [ -f "$BOOT" ]; then
    mv "$BOOT" "$BASE/disable-magic-pointer.disabled"
fi
WATCHER=$(cat "$BASE/watcher.lock/pid" 2>/dev/null || true)
case "$WATCHER" in
    ''|*[!0-9]*) ;;
    *)
        if [ -r "/proc/$WATCHER/cmdline" ]; then
            COMMAND=$(tr '\000' ' ' < "/proc/$WATCHER/cmdline")
            case "$COMMAND" in
                *"/home/root/magic-pointer/inject-pointer-hook.sh"*)
                    kill -TERM "$WATCHER"
                    WAIT=0
                    while kill -0 "$WATCHER" 2>/dev/null; do
                        [ "$WAIT" -lt 15 ] || { echo 'ERROR: watcher did not stop'; exit 1; }
                        sleep 1
                        WAIT=$((WAIT + 1))
                    done
                    ;;
                *) echo 'ERROR: watcher PID belongs to another command'; exit 1 ;;
            esac
        fi
        ;;
esac
set -- $(pidof lginput2)
[ "$#" -eq 1 ] || { echo 'ERROR: expected one lginput2 process'; exit 1; }
P=$1
if ! grep -q libphp "/proc/$P/maps"; then
    echo 'Stock input active; pointer autostart disabled.'
    exit 0
fi
if ! grep -q 'settings-dpad-v1' "/tmp/magic-pointer-ready-$P" 2>/dev/null &&
   ! grep -q 'settings-dpad-v1' "/tmp/magic-pointer-reverted-$P" 2>/dev/null; then
    echo 'ERROR: loaded hook has no known live rollback; no service restart attempted.'
    exit 1
fi
if [ ! -f "/tmp/magic-pointer-ready-$P" ] &&
   grep -q '^native settings-dpad-v1$' "/tmp/magic-pointer-reverted-$P" 2>/dev/null; then
    echo "Stock input already restored in lginput2=$P; pointer autostart disabled."
    exit 0
fi
rm -f "/tmp/magic-pointer-reverted-$P"
touch "/tmp/magic-pointer-revert-$P"
WAIT=0
while [ -f "/tmp/magic-pointer-ready-$P" ] || [ ! -f "/tmp/magic-pointer-reverted-$P" ]; do
    [ "$(pidof lginput2)" = "$P" ] || { echo 'ERROR: lginput2 PID changed'; exit 1; }
    [ "$WAIT" -lt 10 ] || { echo 'ERROR: live rollback was not acknowledged'; exit 1; }
    sleep 1
    WAIT=$((WAIT + 1))
done
[ "$(pidof lginput2)" = "$P" ] || { echo 'ERROR: lginput2 PID changed'; exit 1; }
grep -q '^native settings-dpad-v1$' "/tmp/magic-pointer-reverted-$P"
echo "Stock input restored in lginput2=$P; pointer autostart disabled. No service restart."
