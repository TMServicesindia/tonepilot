# Installing TonePilot on your iPhone 15

Apple only lets an app onto an iPhone if it is **signed**. That decides what's possible:

| Route | Cost | "Tap a link to install"? | Needs a computer? | Lasts |
|---|---|---|---|---|
| **A1. SideStore** (recommended free route) | Free | Almost: after a one-time PC setup, open the `.ipa` in SideStore on the iPhone | Once, for setup | Refreshes itself every 7 days on the phone (Wi-Fi + LocalDevVPN) |
| A2. Sideloadly | Free | No: one USB install from a PC | Windows PC or Mac, every 7 days | 7 days, then re-install (one click) |
| **B. TestFlight** | Apple Developer Program, US$99/year | **Yes**: an invite link opens TestFlight and installs | No (after the one-time setup) | 90 days per build; new builds arrive automatically |
| C. Xcode on a Mac | Free | No | Mac | 7 days with a free Apple ID |

There is **no legitimate free service** that turns an app into a link that installs directly on an iPhone. Sites offering "free signing" use shared enterprise certificates that Apple revokes. They break apps without warning and are a security risk, so TonePilot doesn't recommend them.

## A. Free: build in the cloud, install with Sideloadly

### 1. Build the app on a free cloud Mac (GitHub Actions)
1. Create a free account at <https://github.com> and a **new repository** (e.g. `tonepilot`).
   * **Public** repos get unlimited free Mac build minutes.
   * Private repos are free too, but Mac minutes count 10× against the 2,000 free minutes per month (≈200 Mac minutes; one build takes about 10–15).
2. Upload this project to it (GitHub Desktop or `git push`).
3. Open the repo's **Actions** tab. The workflow **Build iPhone app** runs automatically and:
   * runs all core tests on macOS,
   * bundles the GeneralUser GS sounds,
   * compiles the app for iPhone,
   * produces **TonePilot.ipa**.
4. When it's green, open the run and download **TonePilot-ipa** under *Artifacts*. You can also push a tag like `v0.3.0`, and the `.ipa` will be attached to a **Release** with a permanent download link.

### 2a. Put it on the iPhone 15 with SideStore (free Apple ID, refreshes on the phone)
[SideStore](https://github.com/SideStore/SideStore) installs apps with your Apple ID and keeps them refreshed from the iPhone itself.
1. **One-time setup (needs a computer, ~15 min):**
   * On the iPhone, set a passcode and turn on **Settings › Privacy & Security › Developer Mode**.
   * Install **LocalDevVPN** from the App Store on the iPhone.
   * On a Windows PC or Mac, install iTunes (Windows: from Apple's website) and **iloader** from its official source: <https://github.com/nab138/iloader> (or iloader.app).
   * Connect the iPhone by USB and use iloader to install SideStore. iloader also places the pairing file SideStore needs.
   * On the iPhone, trust your Apple ID under **Settings › General › VPN & Device Management**.
2. **Install TonePilot (no computer):**
   * On the iPhone, open the TonePilot release page and download **TonePilot.ipa**.
   * Connect to Wi-Fi and turn on LocalDevVPN.
   * In SideStore, tap **My Apps › +** and choose the `.ipa`. Sign in with your Apple ID when asked.
3. **Every week:** open SideStore with LocalDevVPN on and Wi-Fi connected. It refreshes TonePilot before its 7-day signature runs out, and your songs and tones are kept.

Free Apple ID limit: 3 sideloaded apps at once, and SideStore itself counts as one. Current steps: <https://docs.sidestore.io>.

### 2b. Or with Sideloadly (USB from a computer each time)
1. On a Windows PC or Mac, install **Sideloadly** from <https://sideloadly.io>. On Windows, also install iTunes and iCloud from Apple's website, not the Microsoft Store versions.
2. Connect the iPhone 15 with a USB-C cable and tap **Trust** on the phone.
3. Drag `TonePilot.ipa` into Sideloadly, enter your Apple ID (a free one works), and click **Start**.
4. On the iPhone:
   * **Settings › Privacy & Security › Developer Mode** → On (the phone restarts).
   * **Settings › General › VPN & Device Management** → trust your Apple ID.
5. Open TonePilot.

**Free Apple ID limits:** the app stops opening after 7 days. Re-install it with Sideloadly (your library and tones are kept), and you can have up to 3 sideloaded apps.

## B. Paid: a real install link (TestFlight)
1. Join the Apple Developer Program (US$99/year) at <https://developer.apple.com/programs/>.
2. In App Store Connect, create the app (bundle id e.g. `com.yourname.tonepilot`) and set up TestFlight.
3. Add these secrets to the GitHub repo: an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`) and your Team ID. The workflow can then sign and upload each build to TestFlight (ask Claude to add the upload step).
4. Create a **public TestFlight link** and open it on the iPhone 15. It installs through the TestFlight app, and new builds update automatically.

## After installing
* **Settings › SoundFonts** should show `GeneralUser-GS.sf2` (bundled).
* Connect the Casio as described in the app's **Settings › Connect your Casio**, then follow [HARDWARE_TEST_CHECKLIST.md](HARDWARE_TEST_CHECKLIST.md).
