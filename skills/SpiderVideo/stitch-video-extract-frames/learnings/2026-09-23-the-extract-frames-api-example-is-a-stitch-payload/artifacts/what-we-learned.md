# The extract-frames API example is the wrong payload

The API reference shows this under `POST /jobs/spiderVideo/extract-frames/submit`:

```json
{"payload": {"projectName": "my-video", "aspectRatio": "9:16",
             "scenes": [{"videoUrl": "https://example.com/scene1.mp4", "durationInSeconds": 5}], …}}
```

That is the **stitch** payload. The frames route answers it with **422**, because it requires:

```json
{"payload": {"action": "extract_frames",
             "video_url": "https://media.spideriq.ai/client-cli-abc123/source/hero.mp4",
             "strategy": "target_frames", "target_frames": 120}}
```

The wrong example is in the API's own OpenAPI spec, not only on the docs page, so any tool that
generates a sample from the spec inherits it. Until it is fixed, take the frames payload from
`references/extract-frames.md`, not from the reference page.
