<p align="center"><img src="docs/assets/wolkaraforever-logo.png" width="360" alt="WolkaraForever"></p>

# WolkaraForever

## Play WoW Forever on iPhone or iPad without a Mac (free Apple ID, no paid developer account)

> ### 📲 [Install guide: WolkaraForever without a Mac →](docs/INSTALL-WITHOUT-A-MAC.md)
> About 30 minutes, with a Linux PC, a USB cable and a free Apple ID. On the phone you also need the
> free **[LocalDevVPN](https://apps.apple.com/app/id6755608044)** app, connected whenever you start
> the game. The [quick install](#quick-install-linux) commands are below.

**This fork of [WolkaraForever](https://github.com/jklock/wolkaraforever)** lets you run World of
Warcraft Forever locally on an **iPhone or iPad** with **no Mac**, **no Xcode**, **no paid Apple
Developer account**, **no jailbreak** and **no streaming**. You sign and install it from a
**Linux** PC with a **free Apple ID**, and the app turns on **JIT by itself** (built-in StikJIT, no
StikDebug, SideStore or AltStore). The only extra app on the phone is
[LocalDevVPN](https://apps.apple.com/app/id6755608044), and it's **required**.

> [!WARNING]
> **Only tested on one iPhone Duo (iOS 27.2.1), signed from Fedora Linux.** It's shared as is, with no claims about its effectiveness or correctness, and no support. Use it at your own risk.

### Quick install (Linux)

The [guide](docs/INSTALL-WITHOUT-A-MAC.md) explains every step:

```sh
mkdir -p ~/wolkara/tools && cd ~/wolkara
git clone https://github.com/TecN01R/wolkaraforever.git
curl -fL -o tools/xtool-duo-x86_64.AppImage https://github.com/TecN01R/wolkaraforever/releases/download/xtool-duo/xtool-duo-x86_64.AppImage
chmod +x tools/xtool-duo-x86_64.AppImage
curl -fLO https://github.com/TecN01R/wolkaraforever/releases/latest/download/wolkaraforever-duo-unsigned.ipa
tools/xtool-duo-x86_64.AppImage auth login          # your free Apple ID ("Password")
cd wolkaraforever
duo/install.sh ~/wolkara/wolkaraforever-duo-unsigned.ipa   # phone on USB, unlocked
# on the phone: Developer Mode on, and trust your Apple ID (Settings > General > VPN & Device Management)
duo/push_pairing.sh                                 # once: lets the app turn on JIT by itself
# on the phone: install LocalDevVPN from the App Store, connect it, open "Tolkara", tap Play
```

| | |
| --- | --- |
| Download the app (unsigned `.ipa`) | [Latest release](https://github.com/TecN01R/wolkaraforever/releases/latest) |
| Download the signer for free Apple IDs (`xtool-duo`, Linux AppImage) | [xtool-duo release](https://github.com/TecN01R/wolkaraforever/releases/tag/xtool-duo) |
| Tested on | Only one iPhone Duo, iOS 27.2.1, signed from Fedora Linux. Nothing else is tested, and no claim is made for any other device or system |
| Keeps | the increased memory limit, game downloads and updates, add-ons, touch controls, your data across the weekly re-signing |
| Confirmed on that Duo | JIT (on Play and when the app opens), login and gameplay, an 8 GiB memory limit with iOS Game Mode, and the interface at native resolution (Quality). Not yet run end to end: playing on mobile data |

What this fork changes: [duo/README.md](duo/README.md) and its [changelog](duo/CHANGELOG.md).
Third-party notices: [NOTICE.md](NOTICE.md).

Unofficial: not affiliated with Blizzard, Apple or the upstream WolkaraForever project. Provided as is,
without warranty (see [LICENSE](LICENSE)) and without support. This project contains no game files; you need your own game
account.

---

## Upstream WolkaraForever (the Mac route)

The rest of this page is upstream's README. It describes the original route, which uses a Mac and a
paid developer membership.

> Verified: 2026-11-21 · Source: `8375cbb`

Run World of Warcraft Forever locally on an iPad or iPhone with a source-built WolkaraForever installation. The app downloads and maintains your game data, then starts the unchanged client through Tolkara. It is not a streaming service and does not include game files.

## Before you begin

You need an Apple-silicon Mac, current Xcode and command-line tools, XcodeGen, Python 3, a paid Apple Developer membership, and an unlocked device in Developer Mode. Reserve about 70 GB for Forever. An Intel Mac runs the same commands and is warned about, not refused, but the documented path and the device builds are arm64.

## Install from source

```sh
git clone https://github.com/jklock/wolkaraforever.git
cd wolkaraforever
cp local.env.example local.env
wolkaraforever/tools/install_prerequisites.sh --check
wolkaraforever/tools/device_variables.sh --write
wolkaraforever/tools/preflight.sh
wolkaraforever/tools/install.sh
```

Read [Install WolkaraForever](docs/INSTALLATION.md) before you begin, and
[Build and run WolkaraForever](docs/BUILDING.md) for the execution modes, the simulator runs, and
the unsigned External JIT package. If you would rather sideload a package than build the app,
[Install the unsigned External JIT app](docs/SIDELOADING.md) is that route.

## What you can do

- Download, resume, repair, update, and start a selected Forever client.
- Choose game and app languages independently.
- Choose an iPadOS or iOS on Duo interface.
- Manage supported add-ons and recover your interface safely.
- Use touch, keyboard, controller, and optional dictation input.
- Cap the frame rate and dim an idle session with Battery Saver, and keep the game's sound without
  loading iOS's audio device layer into it.
- Keep one game password on the device, behind Face ID, for the opt-in experimental Battle.net
  login.

Read [Use WolkaraForever](docs/USING_WOLKARAFOREVER.md) and [iPhone use](docs/IPHONE.md) for procedures.
When something breaks, [Send us a log](docs/SENDING_LOGS.md) — it takes a few taps on the
iPad and needs no computer.

## Safety and support

No mode patches, re-signs, or redistributes game code. WolkaraForever does not automate gameplay, bypass integrity checks, or inspect a running game beyond loading and verification. Read [Compatibility](COMPATIBILITY.md) for support limits and [Security](SECURITY.md) to report a vulnerability.

## Thank you

Thank you to everyone who has opened a pull request, reported a problem, reviewed a change, or
contributed to Wolkara, Tolkara, and WolkaraForever. Project attribution is maintained in
[Contributors](CONTRIBUTORS.md).
