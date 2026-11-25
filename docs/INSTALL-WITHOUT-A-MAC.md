# Install WolkaraForever on iPhone or iPad without a Mac (free Apple ID, Linux)

Play **World of Warcraft Forever** (WoW Forever) on your iPhone or iPad with **WolkaraForever**:

- **no Mac** and **no Xcode**: you sign and install from a **Linux** PC;
- **no paid Apple Developer account**: a **free Apple ID** works;
- **no jailbreak** and **no streaming**: the game runs on the phone itself;
- **no StikDebug, SideStore or AltStore**: the app turns on **JIT** by itself (Built-in JIT);
- you still get the **increased memory limit**, which stock xtool drops on free accounts.

The only extra app on the phone is **LocalDevVPN** (free, App Store).

> [!WARNING]
> **Only tested on one iPhone Duo (iOS 27.2.1), signed from Fedora Linux.** It's shared as is, with no claims about its effectiveness or correctness, and no support. Use it at your own risk.

The steps take about 30 minutes, plus the game download (about 70 GB, on the phone).

## What works today

| | Status |
| --- | --- |
| iPhone Duo, iOS 27.2.1, signed from Fedora 44 Linux | **Tested**: JIT (also prepared on opening the app), game start, login and gameplay work; increased memory limit granted, and iOS Game Mode raises it to 8 GiB; the Quality render profile draws the interface at the screen's native 2670 × 1878 |
| Other iPhones and iPads | **Not tested.** No claim either way |
| Other Linux distributions (Ubuntu, Debian, Arch…) | **Not tested.** No claim either way |
| Windows, through WSL2 with USB passthrough | Possible in principle (xtool supports it); **not tested** |
| macOS | Not needed. If you have a Mac, upstream's [Mac route](INSTALLATION.md) also works |

You may [open an issue](https://github.com/TecN01R/wolkaraforever/issues) to share what happened on
your device, but there's no support and no reply is promised. This is unofficial: not affiliated
with Blizzard, Apple or the upstream WolkaraForever project.

## What you need

- An **iPhone or iPad** on iOS 17.4 or later, with about 80 GB free.
- A **free Apple ID**. A spare Apple ID is fine; xtool signs in to Apple with it directly.
- A **Linux PC** (x86-64) and a **USB cable** for the phone.
- A WoW Forever account. This project contains **no game files**; the app downloads the game.

## Step 1: set up the computer (once)

Install `usbmuxd` (it talks to the phone over USB), `git` and `pymobiledevice3`:

```sh
# Ubuntu / Debian
sudo apt install usbmuxd git pipx
# Fedora
sudo dnf install usbmuxd git pipx

pipx install pymobiledevice3
pipx ensurepath   # then open a new terminal
```

Get this repository's scripts, the patched xtool, and the app. They go in one folder,
`~/wolkara`:

```sh
mkdir -p ~/wolkara/tools && cd ~/wolkara
git clone https://github.com/TecN01R/wolkaraforever.git
curl -fL -o tools/xtool-duo-x86_64.AppImage \
  https://github.com/TecN01R/wolkaraforever/releases/download/xtool-duo/xtool-duo-x86_64.AppImage
chmod +x tools/xtool-duo-x86_64.AppImage
curl -fLO https://github.com/TecN01R/wolkaraforever/releases/latest/download/wolkaraforever-duo-unsigned.ipa
```

`xtool-duo` is [xtool](https://github.com/xtool-org/xtool) with
[one small patch](../duo/xtool-increased-memory-limit.patch). The patch asks Apple for the
increased memory limit, which stock xtool drops for free accounts. Without it the game gets
about half the memory.

## Step 2: sign in to Apple (once)

```sh
~/wolkara/tools/xtool-duo-x86_64.AppImage auth login
```

Choose **Password** (the free-account option), then enter your Apple ID, password and the
two-factor code. Your credentials go only to Apple. Nothing is uploaded anywhere else, and
nothing goes to GitHub.

## Step 3: install the app

1. Connect the phone with the USB cable and unlock it. If it asks **Trust This Computer?**,
   tap **Trust** and enter your passcode.
2. Run:

   ```sh
   cd ~/wolkara/wolkaraforever
   duo/install.sh ~/wolkara/wolkaraforever-duo-unsigned.ipa
   ```

   Answer `y` when it asks whether the app is closed. At the end it should say
   `increased-memory-limit granted`, and it prints the date the signature ends.

## Step 4: allow the app on the phone (once)

1. **Developer Mode**: **Settings → Privacy & Security → Developer Mode** → on. The phone
   restarts; after the restart, confirm **Turn On**.
   (The switch only appears after step 3 has installed the app.)
2. **Trust your Apple ID**: **Settings → General → VPN & Device Management** → your Apple ID →
   **Trust**.

## Step 5: pair the phone for JIT (once)

With the phone still connected by USB and unlocked:

```sh
cd ~/wolkara/wolkaraforever
duo/push_pairing.sh
```

This pairs your computer with the phone's developer service (no prompt, because the phone already
trusts this computer over USB). It then copies that pairing into the app's private storage, where
the app uses it to turn on JIT by itself. The pairing never leaves your computer and your phone.
Don't share it: it gives developer access to your phone.

## Step 6: install LocalDevVPN (once)

Install [**LocalDevVPN**](https://apps.apple.com/app/id6755608044) from the App Store, open it, and
tap **Connect** (allow the VPN configuration). It lets the app reach the phone's own developer
service. It's a loopback connection: none of your traffic leaves the phone through it.

## Step 7: play

1. Make sure **LocalDevVPN** is connected.
2. Open **Tolkara** (the app's name on the Home Screen).
3. iPhone: **Launcher Manager → iOS on Duo** for the phone interface. iPad: keep **iPadOS**.
   For a sharp interface on the iPhone Duo, choose **Render profile → Quality**. Then in the game,
   lower **Options → Graphics → Render Scale** (75% keeps the 3D light).
4. Choose the edition, region and game language, tap **Install**, and wait for the download.
5. Tap **Play**. The first time, the app downloads Apple's developer disk image (once) and turns
   on JIT. This takes a few seconds, then the game starts.

Touch controls, a controller or a keyboard all work. [Use WolkaraForever](USING_WOLKARAFOREVER.md)
and [iPhone use](IPHONE.md) cover the launcher's options.

## Every week: renew the free signature

A free Apple ID's signature lasts **7 days**. Before it runs out, connect the phone and run step 3
again:

```sh
cd ~/wolkara/wolkaraforever && git pull
curl -fLO --output-dir ~/wolkara https://github.com/TecN01R/wolkaraforever/releases/latest/download/wolkaraforever-duo-unsigned.ipa
duo/install.sh ~/wolkara/wolkaraforever-duo-unsigned.ipa
```

The game, your settings and the pairing all stay. Don't delete the app: that deletes the game data.
If the signature has already run out, the app just won't open until you renew it.

## Playing on mobile data (5G / 4G)

LocalDevVPN only works on Wi-Fi (an iOS restriction). On mobile data:

1. Connect LocalDevVPN, then turn on **Airplane Mode**.
2. Open Tolkara. It prepares JIT within a few seconds; the update check fails for now.
3. Turn **Airplane Mode** off and tap **Retry**: the update check runs over mobile data.
4. Tap **Play**.

This flow is new in the latest build and **not yet tested on a device**.

## When something goes wrong

| What you see | What to do |
| --- | --- |
| `install: the phone is not reachable` | Use a data USB cable, unlock the phone, tap **Trust**. Check with `pymobiledevice3 usbmux list`. |
| The AppImage fails with a `libfuse.so.2` error | Install FUSE 2 (`sudo apt install libfuse2t64` on Ubuntu 24.04+), or run it with `APPIMAGE_EXTRACT_AND_RUN=1`. |
| `increased-memory-limit NOT in the profile` | You signed with stock xtool. Use `xtool-duo` from step 1, then run step 3 again. |
| **JIT Not Enabled** when you tap Play | Connect LocalDevVPN and try again. If it says the pairing is missing, run step 5. |
| JIT stops at "Reaching the device" | LocalDevVPN is off, or you're on mobile data (see above). |
| The app doesn't open after a few days | The 7-day signature ran out. Do the weekly renewal. |
| Login refused with `BLZ51900003` | See [iPhone use](IPHONE.md#login-is-refused-blz51900003). |
| Anything else | The app's log is under **Settings → Diagnostics and logs** in the launcher ([Send us a log](SENDING_LOGS.md)). Lines tagged `[jit]` cover JIT. |

## Questions people ask

**Can I play WoW Forever on iPhone without a Mac?** Yes. This guide signs and installs from Linux.

**Do I need a paid Apple Developer account ($99/year)?** No, a free Apple ID works. You renew
the signature every 7 days (one command).

**Do I need StikDebug, SideStore, AltStore or LiveContainer?** No. The app carries its own JIT
helper (StikJIT, embedded). Only LocalDevVPN is needed.

**Does it need a jailbreak, streaming or a PC while I play?** No. The PC is only for installing
and the weekly renewal.

**Can I use Windows?** Possibly, through WSL2 with USB passthrough
([xtool's notes](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md)).
Untested; please report back.

**Is the game modified?** No. WolkaraForever runs the unmodified game client. It does not touch
its executable, login or anti-cheat. It ships no game files.

**Where do the builds come from?** Each release is built by this repository's
[GitHub Actions](../.github/workflows/duo-ipa.yml) from the published source, unsigned, with a
SHA-256 checksum. You sign it yourself with your own Apple ID.

## How it works (short version)

- The app is upstream WolkaraForever's **External JIT** build, plus a small app extension
  (`WolkaraJITHelper`). The extension embeds [StikJIT](https://github.com/StikDebug/StikJIT) 2.0.1
  (MPL-2.0, unmodified).
- When you tap Play, the extension attaches to the app as a debugger through LocalDevVPN. It
  prepares executable memory and detaches, and then the game starts. This is the same protocol
  StikDebug uses, built into the app.
- The free account's limits still apply: 3 sideloaded apps at a time (the extension doesn't
  count), and 10 new app IDs per 7 days (this app uses 2).

More detail is in [duo/README.md](../duo/README.md).
