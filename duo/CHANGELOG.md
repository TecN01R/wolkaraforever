# Changelog of the no-Mac fork

> Verified: 2026-11-25 · Source: `b7b8dd8` · Device: one iPhone Duo, iOS 27.2.1

This lists only what this fork adds or changes. Upstream's own changes are in
[CHANGELOG.md](../CHANGELOG.md); they come in through the weekly upstream sync. Each build is
published as a [release](https://github.com/TecN01R/wolkaraforever/releases) named
`duo-<date>-<commit>`.

Unofficial and unsupported: only tested on one iPhone Duo, with no claims about effectiveness or
correctness.

## 2026-11-26

### Added

- **Unfolded, the game stays in landscape** (patch 0904). On the Duo's inner screen iOS treated
  the app as resizable and turned it to portrait, despite the iPhone's landscape-only setting
  (from iOS 27 that setting is a preference). On a phone screen at least 600 points on its
  shorter side, which is only the Duo's inner screen, the game now asks for landscape and then
  asks iOS to hold it while the game is visible. The cover screen keeps turning as before. iOS
  does not promise to honour the request. *Not yet tested on the Duo.*

- **Reset Positions in the layout editor.** Beside **Done editing**: every control of the
  arrangement being edited (Full or Simple) goes back to its default place, after a one-item
  confirmation menu. Sizes, switches and ability zones stay. *Confirmed on the Duo.*
- The fork's build also runs the `Config.wtf` rules tests.

### Moved

- **To the owner's `personal` branch:** *Reset WoW Settings on This Device* (a reset of the game's
  whole `Config.wtf`, first named Reset All WoW Settings), *Jump instead of camera stick* and
  *Stay signed in* (the experimental Battle.net login's opt-in to keep its web session between
  launches). They are one player's preferences rather than what this fork is for, so they are not
  in its releases. Stay signed in also went against upstream's rule that the sign-in session is
  never kept, so the first launch of a release without it removes any session an earlier build
  kept on the device.

### Fixed

- **Questie installed without its database.** The Add-On Manager skipped any add-on manifest
  (`.toc`) larger than 256 KiB, so a folder whose manifests are all large did not count as an
  add-on. QuestieDB keeps its database in its manifests (12 to 55 MB each), so importing
  Questie's archive installed Questie and QuestieTrace, left QuestieDB out without a word, and
  Questie then reported "QuestieDB not installed". The manager now reads the first 256 KiB of a
  manifest instead of skipping it. Not Duo-specific: upstream has the same code, and the fix is
  on branch `fix/addon-large-toc`, based on upstream's `main`. *Fixture-tested; not yet tested on
  the Duo.* If Questie is already installed, remove it in the Add-On Manager and import the
  archive again.
- **Closing page off-centre.** The "World of Warcraft Forever has closed" countdown page had no
  horizontal centring, so on the Duo's wide unfolded screen it sat to the right. It is now
  centred. (Upstream's page; a candidate to send upstream.)
- **The game measured the cover screen while starting on the inner one.** Before its first
  window, the game was told about iOS's "main screen", which on the Duo is the cover screen
  (466 x 678 points), so its log read "Monitor 0 ... Size(678x466)" and its hardware detection
  used that size while it played on the 951 x 669 point inner screen. It is now told about the
  screen the app is on (patch 0903, a candidate for upstream). The window itself was always
  resized correctly a moment later. Confirmed on the Duo: unfolded, the game now logs
  "Monitor 0 ... Size(951x669) ... Refresh Rate(120Hz)". Since then it also picks the window
  scene the player is using when there are several, the same one the game's window then goes
  on, and answers a question from another thread with the main thread's last answer instead of
  the main screen.
- **Duo Quality after folding or unfolding.** The game's scale is fixed for a session, and
  Quality used the scale of whichever screen the launcher was on, so a session started folded
  drew 3x on the 2.8x inner screen after unfolding, about 14% more pixels than the panel. Quality
  is now the inner screen's scale wherever a session starts (remembered once the launcher has
  been shown unfolded); on the cover screen that is 2.81, a little under its native 3.
- **The graphics-only reset's list (upstream's).** 26 of its 49 setting names do not exist in
  WoW: Forever. They are replaced by the names the client uses, and the list now includes what
  it missed: the frame-rate caps, Target FPS, the raid and battleground graphics set, lighting,
  global illumination and PBR liquid detail. It still leaves `hwDetect`, as before, so it still
  does not re-run hardware detection. The unused performance preset's two frame-cap names are
  corrected the same way.
- **Battery Saver comments (upstream's)** said it reads the device's thermal state. It reads
  the charger and Low Power Mode only, as its rule says; the comments now agree.

### Notes

- The graphics-only reset leaves the game's `hwDetect` marker in place. On the Duo the game then
  came back at Graphics Quality 7, not the 4 its detection reports. The graphics reset is
  unchanged.

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
- **Stay signed in (experimental Battle.net login).** An opt-in in the login sheet keeps
  Battle.net's web session on the device between app launches, so the sign-in page needs no
  typing after a restart. Off by default, as upstream keeps the session in memory only. *Not yet
  tested on a device.*

### Fixed

- **Direct touch with "iOS on Duo".** Upstream enabled direct touch only for the plain "iOS"
  interface mode; it now follows the interface mode, Duo included (patch 0901).

### Changed

- The fork's own patches are numbered `09xx` (0901, 0902, and 0903-0904 from 2026-11-26), apart from
  upstream's sequence.
