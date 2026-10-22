#!/bin/sh
# Exercise the settings hooks against disposable ARM and Thumb processes.
# This script never attaches to or operates the TV input service.
set -eu
TV=${1:?usage: ./tests/test-modern-injector.sh user@TV-IP}
HERE=$(cd "$(dirname "$0")/.." && pwd)
REMOTE="/tmp/magic-pointer-test-$$"
OUT="$HERE/.build/test-logs"
LC=$(ssh "$TV" '[ -e /usr/lib/libcrypt.so.2 ] && echo libcrypt2 || echo libcrypt1')
mkdir -p "$OUT"
ssh "$TV" "mkdir '$REMOTE'"
trap 'ssh "$TV" "rm -rf '\''$REMOTE'\''" >/dev/null 2>&1 || true' 0

push() { ssh "$TV" "cat > '$REMOTE/$2'" < "$1"; }
push "$HERE/.build/modern/ezinject" ezinject
push "$HERE/.build/modern/libphpbridge.so" libphpbridge.so
push "$HERE/.build/native/pointer-test-arm" pointer-test-arm
push "$HERE/.build/native/pointer-test-thumb" pointer-test-thumb
push "$HERE/lginputhook-ref/service/inputhook/$LC/libphp.so" libphp.so
push "$HERE/lginputhook-ref/service/inputhook/hookfactory.php" hookfactory.php
push "$HERE/tv/pointer-hook.php" pointer-hook.php
ssh "$TV" "chmod +x '$REMOTE/ezinject' '$REMOTE/pointer-test-arm' '$REMOTE/pointer-test-thumb'"

RESULT=0
for MODE in arm thumb; do
    if ssh "$TV" "sh -s -- '$REMOTE' '$MODE'" <<'REMOTE_TEST'
set -eu
DIR=$1
MODE=$2
READY="/tmp/magic-pointer-ready-$$"
REVERT="/tmp/magic-pointer-revert-$$"
REVERTED="/tmp/magic-pointer-reverted-$$"
BASE='position=1 wheel=2 custom_on=104 mode_after_on=1 custom6=106 custom2=102 custom_off=105 mode_after_off=0 buttons=3721,5640,5652 arg_errors=0'
ACTIVE='position=0 wheel=0 custom_on=105 mode_after_on=0 custom6=106 custom2=102 custom_off=105 mode_after_off=0 buttons=3721,5640,5652 arg_errors=0'
P=
cleanup() {
    if [ -n "$P" ]; then kill "$P" 2>/dev/null || true; fi
    rm -f "$READY" "$REVERT" "$REVERTED"
}
trap cleanup 0
trap 'exit 1' HUP INT TERM

"$DIR/pointer-test-$MODE" > "$DIR/target-$MODE.log" 2>&1 &
P=$!
# Remove only this disposable target's markers before injection, after its PID is known.
READY="/tmp/magic-pointer-ready-$P"
REVERT="/tmp/magic-pointer-revert-$P"
REVERTED="/tmp/magic-pointer-reverted-$P"
rm -f "$READY" "$REVERT" "$REVERTED"
sleep 1
grep -F -x "$BASE" "$DIR/target-$MODE.log" >/dev/null

# The cleanup trap is active before injection, and owns only this target PID's
# three markers and disposable process.
"$DIR/ezinject" -l "$DIR/module-$MODE.log" "$P" "$DIR/libphpbridge.so" \
    "$DIR/libphp.so" "$DIR/pointer-hook.php" "test-$MODE" > "$DIR/inject-$MODE.log" 2>&1
ATTEMPT=0
while ! grep -q '^installed settings-dpad-v1$' "$READY" 2>/dev/null && [ "$ATTEMPT" -lt 20 ]; do
    kill -0 "$P"
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
grep -q '^installed settings-dpad-v1$' "$READY"
sleep 2

# Wait for two identical whole output lines, so a hook landing midway through
# an iteration cannot create a false failure or a false pass.
ATTEMPT=0
STABLE=0
while [ "$ATTEMPT" -lt 15 ] && [ "$STABLE" -lt 2 ]; do
    kill -0 "$P"
    if [ "$(tail -n 1 "$DIR/target-$MODE.log")" = "$ACTIVE" ]; then
        STABLE=$((STABLE + 1))
    else
        STABLE=0
    fi
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
test "$STABLE" -ge 2

# Revert only these test hooks in place. The target remains alive and its next
# full iteration must return to the native behavior.
touch "$REVERT"
ATTEMPT=0
while [ ! -f "$REVERTED" ] && [ "$ATTEMPT" -lt 10 ]; do
    kill -0 "$P"
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
test -f "$REVERTED"
grep -q '^native settings-dpad-v1$' "$REVERTED"
test ! -e "$READY"
kill -0 "$P"
ATTEMPT=0
STABLE=0
while [ "$ATTEMPT" -lt 12 ] && [ "$STABLE" -lt 2 ]; do
    kill -0 "$P"
    if [ "$(tail -n 1 "$DIR/target-$MODE.log")" = "$BASE" ]; then
        STABLE=$((STABLE + 1))
    else
        STABLE=0
    fi
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
test "$STABLE" -ge 2
echo "PASS: $MODE settings hooks, cursor-state remap, argument forwarding, button passthrough, and live revert (PID $P)"
REMOTE_TEST
    then :; else RESULT=1; fi
    for LOG in target module inject; do
        ssh "$TV" "cat '$REMOTE/$LOG-$MODE.log' 2>/dev/null" > "$OUT/$LOG-$MODE.log" || true
    done
done
exit "$RESULT"
