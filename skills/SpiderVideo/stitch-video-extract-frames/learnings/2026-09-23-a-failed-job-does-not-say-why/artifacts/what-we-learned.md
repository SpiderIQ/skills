# A failed job never says why

Every failed SpiderVideo job returns the same `error_message`:

> This job failed. The technical detail is internal, and has been recorded for support — quote this
> job id if you need help with it.

We checked 13 different real failure causes; all 13 read exactly like that. Error text shown to
clients is allow-listed, and none of SpiderVideo's failure messages are on the list.

What that changes:

- **Do not parse `error_message`** for a cause. There is none in it.
- **Do not retry the same request.** Nearly every SpiderVideo failure is caused by the input (a URL,
  a file, a missing storage bucket) and fails identically every time — it also retried three times
  on its own already.
- **Diagnose from the input.** `python3 scripts/verify-video.py preflight request.json` opens every
  scene, music and voice URL and says which one breaks. For frames, `curl -sI <video_url>` shows the
  status, content type and size the source rules check.
- If the input checks out, quote the `job_id` to support; the real reason is recorded.
