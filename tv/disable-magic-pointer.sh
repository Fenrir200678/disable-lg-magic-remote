#!/bin/sh
# webosbrew boot hook: disable the LG Magic Remote on-screen pointer.
#
# Launches the injector detached, so it never blocks startup.sh. The injector
# waits for lginput2, then injects the pointer-disabling hook via ezinject without
# restarting lginput2 so the remote's radio link is never disturbed.
#
# Install as /var/lib/webosbrew/init.d/disable-magic-pointer (chmod +x).
DIR=/home/root/magic-pointer

[ -f "$DIR/inject-pointer-hook.sh" ] && [ -f "$DIR/inputhook/ezinject" ] || exit 0

nohup /bin/sh "$DIR/inject-pointer-hook.sh" >/dev/null 2>&1 &
exit 0
