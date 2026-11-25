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

The app sets up JIT by itself whenever it comes to the foreground, while LocalDevVPN is
connected. Steps:
- reaching the device;
- the developer disk image, downloaded once and mounted once per reboot;
- preparing executable memory.

JIT then lasts until the app closes, so **Play** starts the game straight away. If the app
could not prepare JIT ahead of time, Play runs those steps itself and shows them.

**On Wi-Fi:** keep LocalDevVPN connected, open the app, and press Play.

**On cellular (5G).** LocalDevVPN cannot reach the device over cellular (an iOS restriction),
and the launcher needs the network for its update check before it offers Play:
1. Turn mobile data on, connect LocalDevVPN, then turn on **Airplane Mode**.
2. Open the app. JIT is prepared within a few seconds. The update check fails for now; that is
   expected.
3. Turn **Airplane Mode** off. Tap **Retry**: the update check runs over cellular, and Play appears.
4. Press **Play**.

A failure says which step failed. The log is under Settings → Diagnostics and logs
(`Documents/wolkaraforever.log`, lines tagged `[jit]`).

## Third-party code

The JIT helper embeds [StikJIT](https://github.com/StikDebug/StikJIT) 2.0.1, under the
Mozilla Public License 2.0, unmodified. CI downloads it from its release and pins it by
checksum (`.github/workflows/duo-ipa.yml`). Its source is at that repository.
