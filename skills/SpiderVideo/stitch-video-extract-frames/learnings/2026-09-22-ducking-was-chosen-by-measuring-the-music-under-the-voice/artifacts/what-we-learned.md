# Ducking is a fixed -12 dB — measure it with a tone the voice cannot make

**The behaviour.** With `duckMusic: true` the music drops 12 dB while the voice speaks and comes back
in the pauses (it starts dropping 120 ms before a word, recovers over 450 ms, and stays down across
pauses shorter than 350 ms). Every word gets the same depth.

**Why fixed.** Two designs were compared on identical inputs. The fixed envelope ducked 8 words
within 0.1 dB of each other. A compressor-style duck varied by 4-5.5 dB between words and swung
15-20 dB inside speech — the "pumping" you hear on cheap radio edits.

**How to check it yourself.** You cannot read the music level under speech on a real song. Render
twice (duck on, duck off) with an 11 kHz sine as the music, isolate it with a stack of
`highpass=9500` filters, and compare its level during a word and during a pause. Expect about 12 dB
of difference with ducking on and none with it off. A 15 kHz tone does not work: the AAC encoder's
low-pass removes it.

**Live numbers:** -56.2 dB under speech, -44.0 dB in the pause (12.2 dB); the control stayed flat at
-44.0 dB, and the picture was byte-identical between the two renders.
