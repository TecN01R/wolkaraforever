# The no-Mac scripts (Linux, free Apple ID, Built-in JIT)

> Verified: 2026-11-25 · Source: `b7b8dd8` · Device: one iPhone Duo, iOS 27.2.1

To install, follow **[Install WolkaraForever without a Mac](../docs/INSTALL-WITHOUT-A-MAC.md)**.

> [!WARNING]
> **Only tested on one iPhone Duo (iOS 27.2.1), signed from Fedora Linux.** It's shared as is, with no claims about its effectiveness or correctness, and no support. Use it at your own risk.

This page covers what each script does and how this fork differs from upstream. What changed,
and when, is in [CHANGELOG.md](CHANGELOG.md).

## How the fork differs from upstream

- **Built-in JIT.** The External JIT app carries an app extension, `WolkaraJITHelper.appex`.
  - It embeds [StikJIT](https://github.com/StikDebug/StikJIT) 2.0.1 (MPL-2.0, unmodified). CI
    downloads it from its release and pins it by checksum in
    [duo-ipa.yml](../.github/workflows/duo-ipa.yml).
  - The app starts the extension and hands it a private XPC endpoint. The extension attaches
    through LocalDevVPN (10.7.0.1), mounts the developer disk image (downloaded once, cached in
    its own Library), and runs the universal protocol. The app then prepares its executable memory
    and the debugger detaches before any game code runs.
  - Sources: `wolkaraforever/JIT/`, `wolkaraforever/JITHelper/`, and patch 0902.
- **When JIT is set up.** The app sets up JIT each time it comes to the foreground, if
  LocalDevVPN is connected. That's what makes the mobile-data flow possible. If it couldn't, Play
  runs the same steps itself and shows them.
- **The screen the game measures at start.** Patch 0903: before the game's first window, its
  display questions are answered with the screen the app is on, not iOS's "main screen" (the
  cover screen on the Duo, 466 x 678 points). Confirmed on the Duo: the game now logs
  "Monitor 0 ... Size(951x669)" unfolded.
- **iOS on Duo touch.** Patch 0901 makes direct touch follow the interface mode, so it also works
  with **iOS on Duo**.
- **Stay signed in.** The experimental Battle.net login can keep its web session between app
  launches (opt-in, in the login sheet; upstream keeps it in memory only). *Not yet tested on a
  device.*
- **Jump instead of camera stick.** A touch-controls switch (with **Sticks and jump only**): the
  camera stick goes, a round Jump button takes its place, and the camera turns by dragging on the
  game. *Installed on the Duo; not yet confirmed in play.*
- **Reset All WoW Settings.** A UI Manager button that empties the game's `Config.wtf` except
  region, language, account name and Gamepad UI, after the usual backup. The game then starts
  with its own defaults and runs its hardware detection again. On the Duo it comes back at
  graphics level 4 with Render Scale 50%; raise Render Scale again if you'd set it higher.
- **Render profile.** On the iPhone Duo, **Quality** renders at the screen's native scale, so the
  game's interface is drawn pixel for pixel. Lower the game's own Render Scale to keep the 3D
  light. Balanced (2x) stays the default. Confirmed on the Duo (2026-11-25): its native scale is
  2.81, so Quality is 2670 × 1878 unfolded. The game then shows Resolution "Custom", and the
  number beside Render Scale is the 3D size (for example 2010x1414 at 75%).
- **Memory.**
  - xtool-duo makes Apple grant the increased memory limit on a free team.
  - The app also declares iOS Game Mode. On the iPhone Duo (2026-11-25), iOS's gamepolicyd turned
    Game Mode on for the app ("Acquired increased memory assertion"), and the limit at game start
    went from 6,144 MiB to **8,192 MiB**. No Game Mode banner appeared.
  - The limit drops back to 6 GiB whenever the app leaves the screen (and for about 2 seconds while
    JIT attaches). A game above 6 GiB that is sent to the background can then be ended by iOS.
  - To check, add `footprint` and `available` on a `memory checkpoint=` line in
    `Documents/external-jit-diagnostics.log`.

## Scripts

| Script | What it does |
| --- | --- |
| [install.sh](install.sh) | Signs the `.ipa` with xtool-duo for your free Apple ID and installs it (USB, or Wi-Fi through a netmuxd on `127.0.0.1:27099`). Running it again is the weekly renewal: the bundle ID stays `XTL-<team>.local.wolkaraforever.duo`, so the game and settings stay. It prints whether the increased memory limit was granted and when the signature ends. |
| [push_pairing.sh](push_pairing.sh) | With no argument, runs `pymobiledevice3 lockdown remotepairing --pair` (promptless over the trusted USB connection) and copies the record, converted to StikJIT's format, into the app's private `Library/StikJIT/pairingFile.plist`. It can also copy in an existing Remote Pairing file. It refuses a lockdown record. |
| [build_xtool.sh](build_xtool.sh) | Builds xtool-duo from source into `../tools/xtool-duo`. Most people download the AppImage instead. |
| [xtool-increased-memory-limit.patch](xtool-increased-memory-limit.patch) | The xtool patch. It requests `INCREASED_MEMORY_LIMIT` for free teams. `XTL_TRY_FREE_EVA=1` also asks for extended virtual addressing (paid-only per Apple; a refusal stops the install). |
| [sync_upstream.sh](sync_upstream.sh) | Merges upstream WolkaraForever (`jklock/wolkaraforever`, `main`) into `duo-baseline`. It regenerates the generated agent catalog instead of hand-merging it, stops on any other conflict, checks that the whole patch series (upstream's plus our `09xx`) still applies to a fresh platform tree, then pushes. `--check` changes nothing. Use it when the weekly job can't merge. |
| [fetch_ipa.sh](fetch_ipa.sh) | For maintainers: downloads a CI run's artifact with `gh` and checks its shape. Users download the release instead. |

The scripts look for the signer in `../tools/` (next to the clone): `xtool-duo`, then
`xtool-duo-x86_64.AppImage`, then `xtool` on PATH. `DUO_XTOOL` overrides that.

## Builds

- [duo-ipa.yml](../.github/workflows/duo-ipa.yml) builds the unsigned `.ipa` on a macOS runner on
  every push to `duo-baseline`. It verifies the package and publishes it as a release.
- [xtool-duo.yml](../.github/workflows/xtool-duo.yml) builds the xtool-duo AppImage on Ubuntu, the
  way xtool builds its own, and publishes it on the `xtool-duo` release.
- [upstream-sync.yml](../.github/workflows/upstream-sync.yml) runs every Monday. It merges new
  upstream commits, builds the result on a side branch, and only when that's green moves
  `duo-baseline` forward and publishes a release. A real conflict, a failed build, or upstream
  changes to workflow files (which GitHub doesn't let the Actions token push) stop it without
  changing anything. The run then fails, so GitHub notifies the owner; finish with
  `duo/sync_upstream.sh`.
- Our own patches are numbered `09xx`, so upstream's sequence (`00xx`) never collides with them and
  they always apply last.
- No Apple credential, certificate, profile, pairing record or device identifier is used in CI or
  committed. Signing happens only on your own computer.
