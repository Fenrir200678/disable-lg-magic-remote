# Disable the pointer on the LG Magic Remote

This script disables the pointer on LG Magic Remotes on rooted webOS LG TVs at boot time.

Use at your own risk. There's no code modification on the TV and is completely reversable so it _should_ be safe. The script simply injects a hook into a running system process to no-op the system pointer functions at boot time. I tested this on my TV (2019 C9 OLED) and am mostly satisfied with it (see [known issues](#known-issues)).


## Why?

I built this because I hated the pointer showing up unexpectedly (like when sitting on the couch and the remote moves), which then triggered some player UI or TV menu. I've tried different solutions to disable the pointer but nothing was robust enough or as seamless as I wanted. I was using a dumb IR universal remote that worked great, but I still preferred the design and feel of the Magic Remote.

## How it works

At the service layer `lginput2` (`com.webos.service.mrcu` on the [Luna service URI](https://webostv.developer.lge.com/develop/references/magic-remote)) exposes the emit paths of the magic remote as
separate functions:

- `lginput_uinput_send_position` — cursor X/Y
- `lginput_uinput_send_wheel` — scroll
- `lginput_uinput_send_custom_event` — the LG cursor on/off keys
- `lginput_uinput_send_button` — the real buttons

Inject a hook (via [`ezinject`](https://github.com/smx-smx/ezinject)) into the running `lginput2` that turns the first three functions into no-ops and leaves `send_button` alone. Injection uses [ptrace](https://man7.org/linux/man-pages/man2/ptrace.2.html) to load a small PHP hook via [`lginputhook`](https://github.com/Simon34545/lginputhook)'s `libphp` + [Frida-Gum](https://github.com/frida/frida-gum) `hookfactory`.


At boot time, `/var/lib/webosbrew/init.d/disable-magic-pointer` launches `inject-pointer-hook.sh`, which waits
for `lginput2` (usually ~30 seconds into boot), injects the hook as soon as it appears, and re-injects if `lginput2` ever
respawns. The cursor can become actiqve before injection happens if triggered by shaking the remote or pressing the Home button.

## Requirements

- A rooted ([webOS Homebrew](https://www.webosbrew.org/rooting/)) LG TV with root SSH enabled.
- Dev environment: just git and ssh if using the pre-built binaries.
- The prebuilt `ezinject`/`libphp.so` are 32-bit ARM EABI5 soft-float, glibc. You can compile from source if you really want, all dependencies are open source.

## Install

```bash
git clone git@github.com:bciuca/lg-magic-remote.git
cd lg-magic-remote
./deploy.sh root@YOUR_TV_IP
```

### What deploy.sh does

- clones `lginputhook` for the prebuilt binaries 
- picks the right `libphp` for your TV's `libcrypt`
- pushes everything into place 
- installs the boot hook (no restart needed)

This is the on-TV layout `deploy.sh` creates:

```
/home/root/magic-pointer/
  inject-pointer-hook.sh                          <- tv/inject-pointer-hook.sh
  inputhook/
    ezinject                                      <- lginputhook .../inputhook/ezinject
    hookfactory.php                               <- lginputhook .../inputhook/hookfactory.php
    pointer-hook.php                              <- tv/pointer-hook.php
    libcrypt1/libphp.so                           <- lginputhook .../inputhook/libcrypt1/libphp.so
                                                     (libcrypt2 if /usr/lib/libcrypt.so.2 exists)
/var/lib/webosbrew/init.d/disable-magic-pointer   <- tv/disable-magic-pointer.sh
```

## Uninstall

Uninstalling removes the boot hook and reboots to clean stock with the default pointer behavior.

```bash
ssh root@YOUR_TV_IP 'rm -f /var/lib/webosbrew/init.d/disable-magic-pointer; reboot'

# optional, remove the files 
ssh root@YOUR_TV_IP 'rm -rf /home/root/magic-pointer'
```

## Known issues

- Sometimes root access is reset and the boot hook will not work
  - **Fix:** Open webOS Homebrew Channel app and go into settings and make sure root is on,
    then reboot the TV.

- The remote buttons may become unresponsive, except for the power button.
  - **Fix:** Power cycle the remote by pulling out a battery for a few seconds and reinserting.

- If the pointer comes on right before the hook, you'll have a frozen pointer on the screen for about 30 seconds
  until it disappears. The pointer may prevent you from using the d-pad to navigate depending on where the 
  pointer last froze on the screen.
  - **Fix:** Just wait it out, the pointer will disappear.


