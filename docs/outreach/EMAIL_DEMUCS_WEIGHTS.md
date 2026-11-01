# Email draft — Demucs weights permission (for the owner's review; NOT sent)

**To:** Alexandre Défossez (Demucs author, via the contact listed on github.com/adefossez/demucs), and
Meta AI / FAIR open-source licensing (the original repository was facebookresearch/demucs)
**Subject:** Licence question: using pretrained Demucs (htdemucs, htdemucs_6s) weights in a commercial music app

Dear Alexandre and the Meta open-source team,

I'm [Owner's name], the developer of TonePilot, a music-practice app for iPhone and Android. It helps
keyboard players learn and play along with songs. It runs entirely on the device: no cloud processing and no
redistribution of any separated audio.

TonePilot uses Demucs (MIT-licensed code) to separate a user's own song files into parts on their phone.
We use the pretrained **htdemucs** and **htdemucs_6s** weights, converted to Core ML and run with
demucs.cpp. The weights are downloaded inside the app.

The Demucs README says the licence of the pretrained weights is "not clear". It also says htdemucs was
trained with MUSDB18-HQ (non-commercial) plus internal data, and that the 6-source model is likely CC
BY-NC. So that we respect your terms before any commercial release, could you tell us:

1. Under which licence the htdemucs and htdemucs_6s weights may be used, and whether commercial use inside
   an app (on-device inference, weights distributed as a download) is permitted;
2. If not, whether a written permission for this use is possible, and under what conditions; and
3. Whether any other Demucs checkpoint is cleared for commercial use.

We will keep the attribution you prefer, and we'll use the weights only for non-commercial personal
builds until we hear from you.

Thank you for Demucs. It is a remarkable piece of work.

Kind regards,
[Owner's name]
[Company / app name], [email], [country]
