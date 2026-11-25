# Changelog of the no-Mac fork

> Verified: 2026-11-25 · Source: `b7b8dd8` · Device: one iPhone Duo, iOS 27.2.1

This lists only what this fork adds or changes. Upstream's own changes are in
[CHANGELOG.md](../CHANGELOG.md); they come in through the weekly upstream sync. Each build is
published as a [release](https://github.com/TecN01R/wolkaraforever/releases) named
`duo-<date>-<commit>`.

Unofficial and unsupported: only tested on one iPhone Duo, with no claims about effectiveness or
correctness.

## 2026-11-25

### Added

- **Built-in JIT.** The External JIT app carries a helper extension that embeds StikJIT 2.0.1
  (MPL-2.0, unmodified; its licence and source location ship inside the helper). The app turns on
  JIT for itself through LocalDevVPN, with no StikDebug, SideStore or AltStore. *Tested on the Duo.*
- **JIT when the app opens.** JIT is prepared a few seconds after the app comes to the front, so
  Play starts the game at once, and JIT can be prepared in Airplane Mode before playing on mobile
  data. *JIT on opening is tested on the Duo; the full mobile-data sequence isn't yet.*
- **Linux signing with a free Apple ID.** `duo/install.sh` signs and installs with xtool-duo,
  which is xtool plus a patch that keeps the increased memory limit on free accounts. It prints
  the date the signature ends. *Tested from Fedora 44.*
- **One-step pairing.** `duo/push_pairing.sh` creates the Remote Pairing record over USB (no
  prompt) and copies it into the app. *Tested.*
- **iOS Game Mode.** The app declares Game Mode; with it, iOS raises the memory limit from 6 GiB
  to 8 GiB while the game is on screen. *Measured on the Duo.*
- **Quality render profile on the iPhone Duo.** The game gets the screen's native scale (2.81,
  2670 × 1878), so the interface is drawn pixel for pixel; the game's Render Scale lowers the 3D
  world. *Tested on the Duo.*
- **Releases.** Each green build is published as an unsigned `.ipa`, and xtool-duo as a Linux
  AppImage, with checksums and licences.
- **Upstream sync.** A weekly job merges upstream when it can; `duo/sync_upstream.sh` does it
  by hand.
- **Documentation.** [Install WolkaraForever without a Mac](../docs/INSTALL-WITHOUT-A-MAC.md),
  [llms.txt](../llms.txt), and this file.

### Changed

- **Saved game password (experimental Battle.net login).** Once a password is saved, **Play**
  starts the game at its own login screen instead of opening the browser every time. The login
  sheet gains **Sign in through the browser this time**, and, before a password is saved, **Start
  at the game's login to save a password**. *Not yet tested on a device.*

### Fixed

- **Direct touch with "iOS on Duo".** Upstream enabled direct touch only for the plain "iOS"
  interface mode; it now follows the interface mode, Duo included (patch 0901).

### Changed

- The fork's own patches are numbered `09xx` (0901, 0902), apart from upstream's sequence.
