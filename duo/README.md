# WolkaraForever on iPhone Duo with a free Apple ID

This fork builds the External JIT app with **Built-in JIT**: the app enables JIT for itself
when you press Play, through a bundled StikJIT helper extension. No JIT-enabler app is
installed. The only other app on the phone is **LocalDevVPN** (App Store), which must be
connected.

## One-time setup

1. **Build tools.** Run `duo/build_xtool.sh` to build `../tools/xtool-duo`. This is
   xtool plus a patch that requests the increased memory limit on a free team.
2. **App.** Run `duo/fetch_ipa.sh`, then `duo/install.sh`. This installs over Wi-Fi through
   netmuxd and does not launch the app.
3. **LocalDevVPN.** Install it from the App Store and connect it.
4. **Pairing file.**
   - On this computer, open idevice_pair (Linux AppImage).
   - Pick the phone, choose **Remote pairing**, then **Create**. Keep the phone unlocked.
   - Click **Save to file…**.
   - Then run `duo/push_pairing.sh <file>`.
   - The file goes into the app's private `Library/StikJIT/`, never into Documents and never
     into git.

## Every week

Run `duo/install.sh` again before the 7-day free signature expires. The app, the game and the
pairing file stay.

## Every launch

1. Connect LocalDevVPN. Use Wi-Fi, or turn cellular data on, connect, then enable Airplane Mode.
2. Press **Play**.

The app shows its JIT steps:
- reaching the device;
- the developer disk image, downloaded once and mounted once per reboot;
- preparing executable memory.

The game then starts as before. A failure says which step failed. The log is `Documents/` →
Settings → Diagnostics and logs.

## Third-party code

The JIT helper embeds [StikJIT](https://github.com/StikDebug/StikJIT) 2.0.1, under the
Mozilla Public License 2.0, unmodified. CI downloads it from its release and pins it by
checksum (`.github/workflows/duo-ipa.yml`). Its source is at that repository.
