# Credits and third-party components

## Original project

This repository builds on [bciuca/disable-lg-magic-remote](https://github.com/bciuca/disable-lg-magic-remote), whose original implementation established the PHP pointer hooks, deployment script, and webOS Homebrew boot integration. Thank you to bciuca for the idea and working foundation. Its Git history is retained in this fork.

The upstream repository did not contain a license file at the time this fork was prepared. This fork does not assign a new blanket license to that inherited code.

## ezinject

[smx-smx/ezinject](https://github.com/smx-smx/ezinject), by Stefano Moioli, supplies the modern injector and module CRT. The build uses unmodified upstream source at commit `d9338952cd01597c5fdd7d6e98991474df5dc89c` with the public glibc loader path enabled. The release archive includes its original Zlib license notice as `COPYING.ezinject`.

`native/phpbridge.c` is an additional integration module in this fork, built with that CRT. It is not part of upstream ezinject.

## lginputhook and Frida Gum

[Simon34545/lginputhook](https://github.com/Simon34545/lginputhook) v1.4.0, commit `3555e95650233474862fc1e3a0a4ce92709a9bd2`, provides the existing PHP library, hook factory, and legacy injector. Deployment downloads these from their upstream repository; they are not bundled in this fork's modern release archive. Their original notices and dependencies remain in the upstream project, including its [license file](https://github.com/Simon34545/lginputhook/blob/v1.4.0/LICENSE.md).

The PHP library embeds [Frida Gum](https://github.com/frida/frida-gum), which implements the actual function interception.

## Toolchain and rooting

The ARM binaries were built using the [webOS Homebrew native toolchain](https://github.com/webosbrew/native-toolchain), release `webos-d7ed7ee.6`. The toolchain itself is not bundled in the release archive.

The boot integration relies on [webOS Homebrew](https://www.webosbrew.org/) and its root-enabled Homebrew Channel. This project is independent of LG and these upstream projects.
