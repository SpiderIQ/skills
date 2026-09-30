# Voiceover, ducked music, loudness and burned captions

Optional additions to a Path A stitch. The voice, music and captions are URLs or lists you supply:
SpiderVideo does **not** generate speech (no text-to-speech here — make the voice with
generate-media first) and does **not** transcribe it. Loudness normalisation is a switch.

## The three contracts

| Field | Default | What it does | What it does NOT do |
|---|---|---|---|
| `voiceUrl` + `voiceVolume` | none, 1.0 | adds the voice as its own track from frame 0, mixed over the music | delay it, trim it, or generate it |
| `duckMusic` | **false** | lowers the music **12 dB** while the voice speaks: it starts 120 ms before a word, holds 150 ms after it, then recovers over 450 ms; pauses under 350 ms stay ducked | anything at all unless you set it to `true` |
| `captions` | none | burns word-by-word captions, the current word highlighted | listen to the audio — it draws exactly the timings you send |

- A `voiceUrl` that 404s, or a file with no audio stream, **fails the job** (after 3 attempts). It is
  never silently dropped.
- `voiceUrl` must be http(s) — anything else is refused with 422 at submit.
- `duckMusic: true` without **both** `musicUrl` and `voiceUrl` → **422**. Music + voice without it →
  the music plays at one flat level under the speech, and nothing warns you.
- The voice starts at 0.0 s of the output. To start narration later, put the silence in the file.
- A voice longer than the video is cut at the last frame; the result's `data.warnings[]` says so.
- **What counts as speech** for the duck: 10 ms windows louder than 40 dB below the voice's peak
  (never quieter than −55 dBFS), with runs shorter than 100 ms ignored. Quiet word endings count as
  speech, so the music does not start to recover inside a word.

## Loudness (`loudnessTarget`)

Rendered mixes come out wherever the inputs put them (a measured render: −18.9 LUFS). Set
`loudnessTarget` (LUFS, **−30 to −10**; −14 is the usual streaming target) to normalise the
finished file with EBU R128 two-pass `loudnorm`:

- The true peak stays at or under **−1 dBTP**, measured on the encoded file you receive.
- The picture is copied untouched.
- Omit the field and the file is exactly what it was.
- The result carries what happened: `data.loudness` =
  `{targetLufs, truePeakCeilingDbtp, mode, before: {integratedLufs, truePeakDbtp, rangeLu}, after: {…}}`.

⚠️ **Read `mode`.**
- `linear` is one constant gain; the ducking is untouched.
- `dynamic` means the target could not be reached under the peak ceiling with one gain, so the
  level was ridden across the whole mix. That nudges the ducked music too. Measured on a real
  render at −14: the music moved 1.6 dB inside speech, against the 12 dB duck. It is audible only
  on close listening.
- If the ducking must stay exactly as rendered, pick a target one gain can reach:
  `before.truePeakDbtp + (target − before.integratedLufs)` must stay under about −1.2 dBTP. On the
  measured render (−18.9 LUFS, peak −1.8) that meant nothing louder than about −18.5. Confirm
  `mode: linear` in the result.

`after.integratedLufs` lands within about ±1 LU of the target (measured: −14.98 for −14).

## Caption format

Each token: `{"text": "Hello", "startMs": 500, "endMs": 900}`, times in milliseconds from the start
of the **output** video. 1–20,000 tokens; `text` 1–200 characters; `endMs` ≥ `startMs` (else 422).
Optional: `pageBreakAfter: true` forces a new caption page after that token; `timestampMs` and
`confidence` are accepted and ignored.

**WRONG** — words run together, because the format is whitespace-sensitive and these tokens mix
conventions:

```json
[{"text": "Welcome", "startMs": 500, "endMs": 900}, {"text": " to", "startMs": 950, "endMs": 1100},
 {"text": "spring", "startMs": 1150, "endMs": 1600}]
```

`" to"` starts with a space, so the list is read in the leading-space convention, and `"spring"`
(no space) is glued to the word before it: **"Welcome tospring"**.

**RIGHT** — either every word bare (the list is then spaced one word per entry):

```json
[{"text": "Welcome", "startMs": 500, "endMs": 900}, {"text": "to", "startMs": 950, "endMs": 1100},
 {"text": "spring", "startMs": 1150, "endMs": 1600}]
```

or every word after the first carrying its leading space, as speech-recognition output usually does.

How pages form (fixed; no styling fields exist):

- words whose starts fall within **1.2 s** share a page; a pause of **600 ms** or more starts a new page;
- a page is on screen from its first word's `startMs` to its last word's `endMs` — never through a pause;
- white bold text, bottom-centred, the active word yellow (`#FFD60A`), sized at 6.5% of the short side;
- tokens past the last frame are not drawn, and `data.warnings[]` says so.

## Timing captions correctly

Captions are only as right as the timings. Two sources, neither verified by the renderer:

1. **From a transcription of the exact voice file you will send** (word-level timestamps). Best. A
   transcript of a different take, or of the script, is not the same timing.
2. **Hand-timed** — only for a few words, and check them against the waveform.

⚠️ **The rendered audio lands ~43 ms after the composition timeline** (measured: a voice starting
at 0.500 s in its file starts at 0.542 s in the output; a whole-file cross-correlation gives exactly
2048 samples at 48 kHz = 42.67 ms, i.e. two AAC frames of encoder delay). Captions follow the
timeline, so they appear about that much **before** the heard word. Ducking is applied inside the
render and stays aligned with the voice as heard. At about one video frame (33 ms) this is rarely
visible; do not "fix" it by shifting every token unless you have measured your own output.

## Gotchas

- The duck is a fixed depth, not a compressor: every word gets the same −12 dB, so music does not
  "pump" between syllables (a measured pump of 0.3 dB inside speech). A voice with long pauses
  lets the music swell back between phrases — that is the 450 ms release working, not a failure.
- `musicVolume` is the level **outside** speech; the duck is 12 dB below it.
- Captions sit in the bottom 14% band. Scenes with their own on-screen text there will collide.

## Verify

```bash
python3 scripts/verify-video.py preflight request.json          # voice reachable, has audio, fits the video
python3 scripts/verify-video.py render "$URL" --request request.json   # audio present and not silent
```

The verifier proves the track exists and is audible. It does **not** prove the duck depth or the
caption timing — see `verify-the-output.md` → *Measuring ducking* and *Checking captions*. Say so in
your report if you did not do those by hand.
