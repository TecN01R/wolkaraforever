# The no-Mac scripts (Linux, free Apple ID, Built-in JIT)

To install, follow **[Install WolkaraForever without a Mac](../docs/INSTALL-WITHOUT-A-MAC.md)**.

> [!WARNING]
> **Only tested on one iPhone Duo (iOS 27.2.1), signed from Fedora Linux.** It's shared as is, with no claims about its effectiveness or correctness, and no support. Use it at your own risk.

This page covers what each script does and how this fork differs from upstream.

## How the fork differs from upstream

- **Built-in JIT.** The External JIT app carries an app extension, `WolkaraJITHelper.appex`.
  - It embeds [StikJIT](https://github.com/StikDebug/StikJIT) 2.0.1 (MPL-2.0, unmodified). CI
    downloads it from its release and pins it by checksum in
    [duo-ipa.yml](../.github/workflows/duo-ipa.yml).
  - The app starts the extension and hands it a private XPC endpoint. The extension attaches
    through LocalDevVPN (10.7.0.1), mounts the developer disk image (downloaded once, cached in
    its own Library), and runs the universal protocol. The app then prepares its executable memory
    and the debugger detaches before any game code runs.
  - Sources: `wolkaraforever/JIT/`, `wolkaraforever/JITHelper/`, and patch 0091.
- **When JIT is set up.** The app sets up JIT each time it comes to the foreground, if
  LocalDevVPN is connected. That's what makes the mobile-data flow possible. If it couldn't, Play
  runs the same steps itself and shows them.
- **iOS on Duo touch.** Patch 0090 makes direct touch follow the interface mode, so it also works
  with **iOS on Duo**.
- **Render profile.** On the iPhone Duo, **Quality** renders at the screen's native scale, so the
  game's interface is drawn pixel for pixel. Lower the game's own Render Scale to keep the 3D
  light. Balanced (2x) stays the default.
- **Memory.**
  - xtool-duo makes Apple grant the increased memory limit on a free team.
  - The app also declares iOS Game Mode. With Game Mode on, the limit is expected to rise from
    about 6 GB to about 8 GB (measured by Playport on a 12 GB iPhone; **not yet confirmed on the
    Duo**).
  - To check, add `footprint` and `available` on a `memory checkpoint=` line in
    `Documents/external-jit-diagnostics.log`.

## Scripts

| Script | What it does |
| --- | --- |
| [install.sh](install.sh) | Signs the `.ipa` with xtool-duo for your free Apple ID and installs it (USB, or Wi-Fi through a netmuxd on `127.0.0.1:27099`). Running it again is the weekly renewal: the bundle ID stays `XTL-<team>.local.wolkaraforever.duo`, so the game and settings stay. It prints whether the increased memory limit was granted and when the signature ends. |
| [push_pairing.sh](push_pairing.sh) | With no argument, runs `pymobiledevice3 lockdown remotepairing --pair` (promptless over the trusted USB connection) and copies the record, converted to StikJIT's format, into the app's private `Library/StikJIT/pairingFile.plist`. It can also copy in an existing Remote Pairing file. It refuses a lockdown record. |
| [build_xtool.sh](build_xtool.sh) | Builds xtool-duo from source into `../tools/xtool-duo`. Most people download the AppImage instead. |
| [xtool-increased-memory-limit.patch](xtool-increased-memory-limit.patch) | The xtool patch. It requests `INCREASED_MEMORY_LIMIT` for free teams. `XTL_TRY_FREE_EVA=1` also asks for extended virtual addressing (paid-only per Apple; a refusal stops the install). |
| [fetch_ipa.sh](fetch_ipa.sh) | For maintainers: downloads a CI run's artifact with `gh` and checks its shape. Users download the release instead. |

The scripts look for the signer in `../tools/` (next to the clone): `xtool-duo`, then
`xtool-duo-x86_64.AppImage`, then `xtool` on PATH. `DUO_XTOOL` overrides that.

## Builds

- [duo-ipa.yml](../.github/workflows/duo-ipa.yml) builds the unsigned `.ipa` on a macOS runner on
  every push to `duo-baseline`. It verifies the package and publishes it as a release.
- [xtool-duo.yml](../.github/workflows/xtool-duo.yml) builds the xtool-duo AppImage on Ubuntu, the
  way xtool builds its own, and publishes it on the `xtool-duo` release.
- No Apple credential, certificate, profile, pairing record or device identifier is used in CI or
  committed. Signing happens only on your own computer.
