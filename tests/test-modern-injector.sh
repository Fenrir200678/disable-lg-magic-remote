#!/bin/sh
# Test on disposable ARM and Thumb processes; never inject into a TV service.
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
"$DIR/pointer-test-$MODE" > "$DIR/target-$MODE.log" 2>&1 &
P=$!
trap 'kill "$P" 2>/dev/null || true; rm -f "/tmp/magic-pointer-ready-$P"' 0
trap 'exit 1' HUP INT TERM
sleep 1
grep -q 'position=1 wheel=2 custom=3 button=123' "$DIR/target-$MODE.log"
"$DIR/ezinject" -l "$DIR/module-$MODE.log" "$P" "$DIR/libphpbridge.so" \
    "$DIR/libphp.so" "$DIR/pointer-hook.php" "test-$MODE" > "$DIR/inject-$MODE.log" 2>&1
ATTEMPT=0
while [ ! -f "/tmp/magic-pointer-ready-$P" ] && [ "$ATTEMPT" -lt 15 ]; do
    kill -0 "$P"
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done
test -f "/tmp/magic-pointer-ready-$P"
sleep 2
kill -0 "$P"
tail -2 "$DIR/target-$MODE.log" | grep -q 'position=0 wheel=0 custom=0 button=123'
echo "PASS: $MODE hooks active; buttons unchanged; original process $P alive"
REMOTE_TEST
    then :; else RESULT=1; fi
    for LOG in target module inject; do
        ssh "$TV" "cat '$REMOTE/$LOG-$MODE.log' 2>/dev/null" > "$OUT/$LOG-$MODE.log" || true
    done
done
exit "$RESULT"
