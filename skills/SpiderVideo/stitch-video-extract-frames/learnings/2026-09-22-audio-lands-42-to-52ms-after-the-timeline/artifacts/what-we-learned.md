# The audio lands ~42-52 ms after the picture timeline

A voice that starts at 0.500 s in its own file starts at **0.542 s** in the rendered mp4; a later
phrase moved from 5.002 s to 5.054 s. Both streams report a start time of 0, so nothing in the file
metadata shows the offset — only measuring an onset against the source does.

What it means for you:

- **Ducking** is computed inside the render and moves with the voice, so it stays aligned with what
  a viewer hears.
- **Captions** are placed on the picture timeline, so each word appears about 42-52 ms (one to one and
  a half frames at 30 fps) before it is heard. Most viewers will not notice.
- **Do not "correct" your caption timings by a fixed amount** unless you have measured your own render.

**Measured more precisely (2026-09-28):** cross-correlating a whole voice file against a render gives
exactly **2048 samples at 48 kHz (42.67 ms)** — the size of two AAC audio frames, which is what an
encoder's start-up delay looks like when the file does not tell players to skip it. It is still
not fixed on our side.
