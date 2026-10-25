# Installing TonePilot on an Android phone

Android installs apps straight from a file, with no computer, cable or Apple-style signing.

**Download:** <https://github.com/TMServicesindia/tonepilot/releases/download/android-latest/TonePilot.apk>

1. Open the link on the phone (Chrome or any browser). The file is about 40 MB.
2. Tap the downloaded **TonePilot.apk**. If Android asks, allow **Install unknown apps** for your browser or Files app, then tap **Install**.
3. Open TonePilot. The first launch takes a few seconds while it unpacks the instrument sounds.

Updates use the same link. Installing a newer APK over the old one keeps your songs and tones.

Requirements: Android 9 or newer, a 64-bit (arm64) phone (almost every phone from the last six years).

## Connecting the Casio CT-X870IN

| Connection | Cable | Carries |
|---|---|---|
| Casio **USB TO HOST** → phone | USB-C to USB-B cable, or USB-A to USB-B + a USB-C OTG adapter | Your key presses (MIDI) |
| Phone → Casio **AUDIO IN** | 3.5 mm stereo male-to-male cable | TonePilot's sound |

* **Phone with a 3.5 mm headphone jack:** USB cable in the USB-C port and the audio cable in the headphone jack. No hub needed.
* **Phone without a headphone jack:** a USB-C hub with a USB port and a 3.5 mm jack (or a USB-C audio adapter plugged into the hub).
* Turn the Casio's own volume down (or set Local Control off if your model has it) so you hear only TonePilot.
* Avoid Bluetooth for the sound: it adds a delay you'll feel when playing.

In TonePilot, **Settings › MIDI** shows "Note On" when you press a Casio key, and **Settings › Audio output** shows where the sound is going. If you plug the audio cable in while the app is open and hear nothing, tap **Restart audio**.

## What's in the Android version

Same engine and analysis as the iPhone app (shared Swift code):

* **Library:** import an MP3 or other audio file (or *Open with / Share to TonePilot* from a file manager). Analysis starts automatically.
* **Listen Mode:** play a song in YouTube, YouTube Music, Spotify or JioSaavn, and TonePilot listens through the microphone and builds the arrangement. The audio stays in memory only.
* **Song page:** key, tempo, meter, feel, sections, a tone for every section, and corrections (tempo ÷2/×2, key, meter).
* **Section guide:** the Root → Fifth → Root left-hand pattern, right-hand phrases, chord shapes, what's heard, and a practice loop at 50/75/90/100% speed.
* **Play:**
  * Choose any tone (song tones, My Tones, all instruments) and play it from the Casio keys.
  * A live chord and melody guide.
  * Automatic, assisted or manual tone switching.
  * Bass, drums, metronome and melody guide.
  * Per-layer volume, octave and mute.

Not in the Android version yet: the full Tone Studio editor (envelope, filter, EQ), the sample-instrument creator, and the optional vocal-separation server.
