# Installing TonePilot on your iPhone 15

Apple only lets an app onto an iPhone if it is **signed**. That decides what's possible:

| Route | Cost | "Tap a link to install"? | Needs a computer? | Lasts |
|---|---|---|---|---|
| **A. GitHub Actions + Sideloadly** (recommended free route) | Free | No: one USB install from a PC | Windows PC or Mac, only to install | 7 days, then re-install (one click) |
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
   * produces **TonePilot-unsigned.ipa**.
4. When it's green, open the run and download **TonePilot-ipa** under *Artifacts*. You can also push a tag like `v0.3.0`, and the `.ipa` will be attached to a **Release** with a permanent download link.

### 2. Put it on the iPhone 15 (free Apple ID)
1. On a Windows PC or Mac, install **Sideloadly** from <https://sideloadly.io>. On Windows, also install iTunes and iCloud from Apple's website, not the Microsoft Store versions.
2. Connect the iPhone 15 with a USB-C cable and tap **Trust** on the phone.
3. Drag `TonePilot-unsigned.ipa` into Sideloadly, enter your Apple ID (a free one works), and click **Start**.
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
