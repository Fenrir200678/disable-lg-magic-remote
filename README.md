# Disable the LG Magic Remote pointer

This toolkit disables the on-screen pointer from an LG Magic Remote on a rooted LG webOS TV. It installs a boot hook that injects into the TV's `lginput2` process and suppresses pointer movement, wheel events, and the cursor on/off custom events. Physical buttons remain available. The scroll wheel is intentionally disabled along with pointer input.

Many thanks to **bciuca** for [the original disable-lg-magic-remote project](https://github.com/bciuca/disable-lg-magic-remote), which inspired this fork and provided its working foundation. This version adds support for newer glibc versions, a current injector with a PHP ABI bridge, and verified release downloads. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for credits and component notices.

## How it works

The TV's `lginput2` service exports the relevant input functions. The injector hooks these three functions and makes them return without handling the event:

- `lginput_uinput_send_position` — pointer position
- `lginput_uinput_send_wheel` — scroll wheel
- `lginput_uinput_send_custom_event` — including the cursor on/off keys

The button function, `lginput_uinput_send_button`, is left untouched. Injection uses [ezinject](https://github.com/smx-smx/ezinject). The legacy path uses the pinned `lginputhook` PHP library and hook factory. The modern path uses a small native bridge to load the PHP library with the current injector ABI.

A boot hook starts a watcher that waits for `lginput2`, injects the hooks, and watches for the process to respawn. The pointer may appear briefly before injection completes.

## Requirements

- A rooted LG webOS TV with root SSH access and working key-based authentication (deployment uses non-interactive SSH).
- On the computer used to deploy: `git`, `ssh`, `tar`, and either `curl` or `wget`.
- A checksum tool: `sha256sum`, `shasum`, or `openssl`.
- Linux or macOS, or Windows through WSL. PowerShell is not supported directly.

The payload targets a 32-bit ARM EABI5 soft-float `lginput2`. The tested TV runs a 64-bit aarch64 kernel but a 32-bit ARM `lginput2`; check the process architecture rather than relying on `uname -m`.

## Install

Clone this repository and provide either the TV's address or an SSH alias configured on your computer:

```sh
git clone https://github.com/Fenrir200678/disable-lg-magic-remote.git
cd disable-lg-magic-remote
./deploy.sh root@TV-IP
# or, with an SSH alias:
./deploy.sh living-room-tv
```

`deploy.sh` reads the TV's glibc version and selects the compatible injector:

- glibc older than 2.34: legacy prebuilt injector and PHP payloads
- glibc 2.34 or newer: modern injector and bridge

For the modern path, a fresh checkout downloads the versioned release asset `magic-pointer-modern-arm.tar.gz` from this repository's v1.0.0 release. It verifies the runtime files against the checksums pinned in [`releases/v1.0.0.sha256`](releases/v1.0.0.sha256); no compiler is needed for a normal deployment. If you prefer to build locally, see [Build the modern injector](#build-the-modern-injector).

The legacy PHP and hook-factory files come from `Simon34545/lginputhook` v1.4.0, pinned to commit `3555e95650233474862fc1e3a0a4ce92709a9bd2`. Version 1.5 removed the PHP files this toolkit uses. Deployment also fetches the legacy injector and its PHP payloads as needed. Generated build and release files are kept in the ignored `.build/` directory.

### Check before installing

To validate or download the required payloads and check remote prerequisites without writing files to the TV or injecting into a process, run:

```sh
./deploy.sh --check root@TV-IP
```

### Build the modern injector

Most users do not need to build anything. To build the modern injector locally, use CMake and the [webOS native-toolchain release `webos-d7ed7ee.6`](https://github.com/webosbrew/native-toolchain/releases/tag/webos-d7ed7ee.6). After extracting and relocating the SDK according to its instructions, run:

```sh
./build-injector.sh /path/to/sdk/share/buildroot/toolchainfile.cmake
./deploy.sh --local-build root@TV-IP
```

The build pins ezinject to commit `d9338952cd01597c5fdd7d6e98991474df5dc89c` and writes its output to `.build/modern/`.

Use `--local-build` to deploy those locally built files. Its generated manifest checks local build consistency; it is not a published release signature. Without that option, deployment uses the checksum-pinned release and replaces a differing cache with the published binaries.

Maintainers can run `./package-release.sh` after testing a build. This creates `.build/release/magic-pointer-modern-arm.tar.gz` with attribution notices, and updates the three pinned runtime checksums in `releases/v1.0.0.sha256`. Commit the checksums before tagging and publishing the matching archive. Release coordinates and dependency revisions are centralized in `releases/toolkit.conf`; update them together for a new release.

The legacy injector depends on private glibc internals that are unavailable starting with glibc 2.34. The current injector uses public `dlopen`/`dlsym` interfaces. Because the PHP library retains the older ezinject module ABI, `native/phpbridge.c` calls its `lib_main` entry point without passing the modern internal context to the old `crt_init` function.

## Tested configuration

The modern injection path works on this configuration:

| Component | Tested version |
| --- | --- |
| TV | LG OLED G4 |
| Model | `OLED65G49LS.DEUQL.JP` |
| Firmware | `43.21.73` |
| webOS | webOS 26 |
| SDK | `11.2.0-3703` |
| Kernel | Linux `6.12.44-352`, ARM64 / aarch64 |
| `lginput2` | 32-bit ARM EABI5 soft-float |
| glibc | `2.39` |
| Access | Root SSH |

Pointer suppression and physical button operation were confirmed on this TV. Injection and repeated deployment kept `lginput2`'s PID stable. Disposable ARM and Thumb test processes also retained their PIDs, with the three pointer functions suppressed and the simulated button function unchanged. Reboot behavior has not been tested. Other models and firmware versions may work if they meet the requirements, but have not been verified here.

## Troubleshooting

The boot hook waits for `lginput2` to become ready. If the pointer is triggered during this interval, it can remain visible until injection finishes. A readiness marker is written as `/tmp/magic-pointer-ready-<lginput2 PID>` after all three hooks install successfully.

For deployment or injection problems, inspect these logs on the TV:

- `/home/root/magic-pointer/inject.log`
- `/home/root/magic-pointer/module.log` (modern mode)
- `/tmp/pointer-hook.log`

If an injection fails partway through, fix the reported problem and reboot before trying again; rebooting clears the incomplete in-memory injection. The watcher stops after an injection failure instead of retrying repeatedly. If remote buttons stop responding, power-cycle the remote by removing a battery for a few seconds and reinserting it.

If the boot hook does not run, check that root access is enabled in the webOS Homebrew Channel settings, then reboot the TV.

## Uninstall

Remove the boot hook and reboot the TV to restore the normal pointer behavior:

```sh
ssh root@TV-IP 'rm -f /var/lib/webosbrew/init.d/disable-magic-pointer; reboot'
```

Optionally remove the installed toolkit files:

```sh
ssh root@TV-IP 'rm -rf /home/root/magic-pointer'
```
