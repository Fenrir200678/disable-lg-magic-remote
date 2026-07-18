#!/bin/sh
# Deploy the LG Magic Remote pointer-disable hook to a rooted webOS TV.
#
#   ./deploy.sh user@host
#
# Pushes the working files (tv/) plus the prebuilt injection toolkit
# (ezinject / libphp / hookfactory from Simon34545/lginputhook), installs the
# webosbrew boot hook, and injects immediately. Re-running is safe — the injector
# skips if lginput2 is already hooked, and nothing here restarts lginput2.
#
# Requirements (on this machine): git, ssh. On the TV: rooted (webosbrew) with
# root SSH (key auth recommended). The prebuilt binaries are 32-bit ARM EABI5
# soft-float — fine for an LG C9; verify for other models (see README).
set -eu

TV="${1:?usage: ./deploy.sh user@TV-IP}"
HERE=$(cd "$(dirname "$0")" && pwd)
REF="$HERE/lginputhook-ref"
IH="$REF/service/inputhook"

# is the TV reachable
if ! ssh -o ConnectTimeout=8 -o BatchMode=yes "$TV" 'true' 2>/dev/null; then
    echo "ERROR: can't SSH to $TV." >&2
    echo "  - Is the TV on (not in standby — that drops SSH)? Is the IP right?" >&2
    echo "  - Is root SSH enabled (webosbrew Homebrew Channel) with your key authorized?" >&2
    exit 1
fi

# clone prebuilt toolkit if we don't already have it
if [ ! -f "$IH/ezinject" ]; then
    echo "==> cloning lginputhook (prebuilt ezinject/libphp/hookfactory)"
    git clone --depth 1 https://github.com/Simon34545/lginputhook "$REF"
fi

# match the libphp build to the TV's libcrypt.
LC=$(ssh "$TV" '[ -e /usr/lib/libcrypt.so.2 ] && echo libcrypt2 || echo libcrypt1')
echo "==> $TV uses $LC"

# scp may be absent on webOS; pipe over ssh with cat.
push() { echo "    -> $2"; ssh "$TV" "cat > '$2'" < "$1"; }

# create dirs and push files.
echo "==> deploying files"
ssh "$TV" "mkdir -p /home/root/magic-pointer/inputhook/$LC /var/lib/webosbrew/init.d"
push "$IH/ezinject"                      "/home/root/magic-pointer/inputhook/ezinject"
push "$IH/hookfactory.php"               "/home/root/magic-pointer/inputhook/hookfactory.php"
push "$IH/$LC/libphp.so"                 "/home/root/magic-pointer/inputhook/$LC/libphp.so"
push "$HERE/tv/pointer-hook.php"         "/home/root/magic-pointer/inputhook/pointer-hook.php"
push "$HERE/tv/inject-pointer-hook.sh"   "/home/root/magic-pointer/inject-pointer-hook.sh"
push "$HERE/tv/disable-magic-pointer.sh" "/var/lib/webosbrew/init.d/disable-magic-pointer"
ssh "$TV" "chmod +x /home/root/magic-pointer/inputhook/ezinject \
    /home/root/magic-pointer/inject-pointer-hook.sh \
    /var/lib/webosbrew/init.d/disable-magic-pointer"

# inject now and will auto-injects at every boot via the hook
echo "==> injecting into the running lginput2"
ssh "$TV" 'sh /home/root/magic-pointer/inject-pointer-hook.sh >/dev/null 2>&1 &'
sleep 6
ssh "$TV" 'LP=$(pidof lginput2); echo "    lginput2=$LP  hook_loaded=$(grep -c libphp /proc/$LP/maps 2>/dev/null)"; tail -2 /home/root/magic-pointer/inject.log 2>/dev/null'

echo "==> done. Shake the remote, pointer should be gone, buttons still work."
