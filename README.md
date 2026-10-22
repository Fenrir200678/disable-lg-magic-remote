# Disable the LG Magic Remote pointer

This toolkit disables the on-screen pointer from an LG Magic Remote on a rooted LG webOS TV. It installs a boot hook that injects into the TV's `lginput2` process and suppresses pointer movement and wheel events. Cursor-on requests become native cursor-off events so menus can return to D-pad navigation. Physical buttons remain available. The scroll wheel is intentionally disabled along with pointer input.

Many thanks to **bciuca** for [the original disable-lg-magic-remote project](https://github.com/bciuca/disable-lg-magic-remote), which inspired this fork and provided its working foundation. This version adds support for newer glibc versions, a current injector with a PHP ABI bridge, and verified release downloads. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for credits and component notices.

## How it works

The TV's `lginput2` service exports the relevant input functions. The injector hooks these three functions:

- `lginput_uinput_send_position` — suppress pointer position
- `lginput_uinput_send_wheel` — suppress scroll wheel
- `lginput_uinput_send_custom_event` — change LG event ID 4 (cursor on) to 5 (cursor off); forward cursor-off, disconnect, and other events unchanged, with their original arguments

The button function, `lginput_uinput_send_button`, is left untouched. Injection uses [ezinject](https://github.com/smx-smx/ezinject) and the pinned `lginputhook` PHP library. The modern path uses a small native bridge to load the PHP library with the current injector ABI. The PHP hook checks Gum replacement results and retains callback storage after live rollback.

The previous version discarded both cursor-on and cursor-off events, which could leave Settings in pointer mode: a frozen cursor appeared and OK clicked its last position. With the corrected hook on the tested LG G4, Settings still initially shows a centered pointer. The first D-pad press removes it, and OK then selects the focused menu item correctly, including after reopening Settings. Completely preventing that initial appearance remains unresolved. The user also confirmed D-pad and OK operation in Glasshouse, a normal app, and on an HDMI input. Standby and cold-start behavior have not yet been verified with the corrected hook.

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

| Component  | Tested version                       |
| ---------- | ------------------------------------ |
| TV         | LG OLED G4                           |
| Model      | `OLED65G49LS.DEUQL.JP`               |
| Firmware   | `43.21.73`                           |
| webOS      | webOS 26                             |
| SDK        | `11.2.0-3703`                        |
| Kernel     | Linux `6.12.44-352`, ARM64 / aarch64 |
| `lginput2` | 32-bit ARM EABI5 soft-float          |
| glibc      | `2.39`                               |
| Access     | Root SSH                             |

Pointer suppression and physical button operation were confirmed on this TV with the original hook, including persistence across TV restarts. With the corrected hook, it's confirmed that D-pad navigation and OK work correctly in Settings after the first arrow press, including after reopening the menu. Autostart and the watcher are enabled; standby and cold-start persistence of the corrected hook have not yet been tested. Other models and firmware versions may work if they meet the requirements, but have not been verified here.

## Troubleshooting

The boot hook waits for `lginput2` to appear. If the pointer is triggered during this interval, it can remain visible until injection finishes. A readiness marker is written as `/tmp/magic-pointer-ready-<lginput2 PID>` after all three hooks install successfully.

An intermittent startup failure was observed on the tested G4: ezinject detached, but `lginput2` remained in `State: T (stopped)` with `TracerPid: 0`. The PHP hook never became ready and input stopped responding. Sending `SIGCONT` to that same process resumed it and immediately completed hook startup. The injector wrapper now checks for this condition after its injector exits (including failure) and during the readiness wait, and resumes only its own target when no tracer is attached. It refuses a fresh injection into a process that was already stopped or traced. This recovery has been verified on the affected running TV; prevention across repeated cold starts still needs verification.

For deployment or injection problems, inspect these logs on the TV:

- `/home/root/magic-pointer/inject.log`
- `/home/root/magic-pointer/module.log` (modern mode)
- `/tmp/pointer-hook.log`

If an injection fails partway through, fix the reported problem and reboot before trying again; rebooting clears the incomplete in-memory injection. The watcher stops after an injection failure instead of retrying repeatedly. If remote buttons stop responding, power-cycle the remote by removing a battery for a few seconds and reinserting it.

If the boot hook does not run, check that root access is enabled in the webOS Homebrew Channel settings, then reboot the TV.

## Uninstall

For the current hook, restore native input immediately and disable this toolkit's autostart:

```sh
./rollback.sh root@TV-IP
# or directly on the TV:
ssh root@TV-IP 'sh /home/root/magic-pointer/restore-magic-pointer.sh'
```

Rollback restores the original native functions without restarting the input service or the TV. The PHP thread remains loaded until the process exits, so callback storage is retained safely. The watcher and this project's boot hook are disabled. Reinjecting into that same process is refused; enable suppression again only after a fresh `lginput2` process is available.

Older installed hooks have no live rollback channel. Updating PHP files on disk cannot change their in-memory hooks. Deployment detects an older readiness marker and refuses double injection; a separately planned service restart or TV restart is needed to load the corrected version.

Once native input has been restored, optionally remove the installed toolkit files:

```sh
ssh root@TV-IP 'rm -rf /home/root/magic-pointer'
```
