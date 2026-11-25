# Notices

> Verified: 2026-11-21 · Source: `8375cbb`

WolkaraForever continues Wolkara by fJavierLasso and uses the Tolkara runtime by Vasilii Kharitonov and Tolkara contributors. The repository retains the applicable MIT license and third-party notices.

The project uses Apple public SDK frameworks, system zlib, and Python standard-library components. It does not include game files, Apple operating-system components, signing material, or extracted system assets. The only certificates in a build are public trust anchors — no private keys — that a build exports from the builder's own Mac (`CompatibilityRootCertificates.plist`), because the game validates Battle.net's certificate against macOS's system root certificates.

The Forever manifest and archive readers were informed by public format references, including TACTSharp. See the source headers and license files for exact attribution obligations.

## This fork (TecN01R/wolkaraforever, no-Mac builds)

This unofficial fork adds, in addition to the above:

- **StikJIT 2.0.1** by the StikDebug authors, under the Mozilla Public License 2.0. It is embedded
  unmodified, as `StikJIT.framework`, in the app's `WolkaraJITHelper.appex`, which also carries
  `StikJIT-LICENSE.txt` and `StikJIT-NOTICE.txt`. Source: <https://github.com/StikDebug/StikJIT/tree/2.0.1>.
- **xtool** by Kabir Oberai and contributors, under the MIT license, with
  [duo/xtool-increased-memory-limit.patch](duo/xtool-increased-memory-limit.patch). It is published
  as the `xtool-duo` Linux AppImage, with xtool's licence attached to that release. Source:
  <https://github.com/xtool-org/xtool>.
- **LocalDevVPN** (App Store) is required on the device but is not included or redistributed.

The fork's own changes are under this repository's MIT license, and are listed in
[duo/CHANGELOG.md](duo/CHANGELOG.md).
