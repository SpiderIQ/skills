# Only http(s) URLs are fetched

The renderer downloads every scene, music track and voice itself, and it only fetches `http://` and
`https://` URLs. Anything else — `file:///…`, `s3://…`, a relative path — is refused at download time
and the job fails.

The catch is **where** it is refused:

| Field | Checked at submit? | A non-http(s) value |
|---|---|---|
| `voiceUrl` | yes | 422 immediately |
| `scenes[].videoUrl` | no | 201, then the job fails minutes later |
| `musicUrl` | no | 201, then the job fails minutes later |

And the failed job will not tell you why (the reason is withheld from client results). So:

- Host every asset and send its https URL.
- Run `python3 scripts/verify-video.py preflight request.json` before submitting — it opens every
  URL the renderer will open and FAILs the ones that will not work.
