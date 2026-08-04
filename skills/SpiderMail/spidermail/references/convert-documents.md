# Converting: two different surfaces

There are **two** conversion methods on this skill and they are not variants of
each other. Picking the wrong one is the most common mistake here.

| You have | You want | Call | Shape |
|---|---|---|---|
| a **file** (PDF, DOCX, XLSX, PPTX, CSV, image) | markdown | `convertDocument` → `getConversion` | **async** — returns a `job_id`, poll it |
| a **string** already in markdown or HTML | the other format | `convertMailBody` | **sync** — the body is in the response |

If you are about to base64 a document into `convertMailBody`, or poll a job for
what was a one-line HTML→markdown transform, you have the wrong one.

---

# Part 1 — Documents → markdown

`convertDocument` → `getConversion`. PDF, DOCX, XLSX, PPTX, CSV, images.

Same worker as `sendEmail` — the SpiderMail worker is the only job-consuming
image in the fleet carrying liteparse + LibreOffice + ImageMagick + Ghostscript.

> **⚠️ Scope of "converts correctly."** The office / PDF / image family above
> goes through liteparse and produces real markdown — that is the verified
> surface. **HTML and TXT input currently come back as their raw source labelled
> `text/markdown`**; the text family is passed through, not converted. If you
> have an HTML string, use `convertMailBody` (Part 2) — the surface actually
> built for it.

---

## Steps

1. **Get the bytes to the API.** Two paths, and the choice is about size:

   | Size | Path | Why |
   |---|---|---|
   | ≤ 10 MB | `content_base64` inline | one call, no upload step |
   | > 10 MB | upload to SpiderMedia, pass `media_id` | `/api/v1/jobs/` sits behind a 10 MB nginx cap; the media route allows 100 MB |

2. **Submit.** `convertDocument` returns **`202` + `job_id`**. Not markdown.

3. **Poll `getConversion`** until `status` is `completed` or `failed`.

4. **Read `security` before you use the text.** See Gotchas.

---

## WRONG / RIGHT

```jsonc
// ❌ WRONG — expecting a body back
const res = await convertDocument({ content_base64: b64 });
console.log(res.markdown);        // undefined. This is a job receipt.

// ✅ RIGHT
const { job_id } = await convertDocument({ content_base64: b64, full_text: true });
const result = await pollUntilComplete(job_id);   // getConversion
console.log(result.markdown);
```

```jsonc
// ❌ WRONG — always asking for the whole document
{ "content_base64": "...", "full_text": true }
// You are moving the entire body across the wire to answer "is this an invoice?"

// ✅ RIGHT — classify on the preview, fetch the body only if you need it
{ "content_base64": "..." }        // full_text defaults false → 1500-char preview
```

```jsonc
// ❌ WRONG — trusting the filename to pick the parser
{ "filename": "report.pdf", "mime_type": "application/pdf" }
// …on a file that is actually a PNG. Both fields are ADVISORY.

// ✅ RIGHT — send them anyway (they are echoed back), but read `source_format`
// from the RESULT to learn what the document actually was.
```

---

## Gotchas

- **🔴 `full_text: true` is the precondition for object storage, not just for the
  body.** The flag is evaluated **before** the size threshold, so without it
  `storage_key` is `null` at *any* size — a 2 MB document comes back as a
  1500-char preview with no key. Read `truncation_notice` on the result: when
  something is being withheld it names the specific remedy.

  ```
  full_text unset, any size      → preview · markdown null · storage_key NULL
  full_text: true, under 256 KB  → full body in `markdown`
  full_text: true, over  256 KB  → storage_key set → follow it to /content
  ```

  ⚠️ **Do not conclude the storage path is broken from a request that omitted the
  flag.** That branch genuinely was dead for a long time, so the wrong conclusion
  is also the familiar one — and a `GET /jobs/spiderConvert/{id}/content` 404
  after a no-flag submit is correct behaviour.

- **`truncated: true` has three different causes, and `storage_key` does NOT
  separate them.** Either `full_text` was false (you asked for a preview), or it
  was true and the markdown exceeded the inline threshold so the body is on the
  CDN under `storage_key`, or the EXTRACTOR stopped early — in which case the
  missing text was never produced and no flag or key retrieves it. The
  discriminators are `truncation_notice` (recoverable, and it says how) and
  `extraction_notice` / `extraction_truncated` (permanent). Checking
  `storage_key` alone cannot tell case 1 from case 3, because it is null in both.

- **🔴 `security.safe === false` means the extracted text contains
  instruction-like content.** A PDF can carry "ignore all previous instructions"
  in its text layer as easily as an email body can. The text is returned
  **unmodified** — SpiderIQ tells you rather than silently editing a customer's
  document. If you are about to paste this into a model prompt, that flag is the
  whole reason it exists.

- **`ocr: "never"` errors on images**, on purpose. An image has no text layer, so
  "give me the text but never run OCR" has no honest answer other than an error.
  On a large scanned PDF corpus `never` is materially cheaper — use it there.

- **`ocr: "force"` is accepted but behaves as `auto`.** LiteParse decides
  internally and exposes no force switch. This is logged rather than silently
  ignored; do not build a flow that depends on forcing OCR.

- **Archives, audio and video are refused, not attempted.** Extract an archive
  yourself and convert its documents individually.

---

## Verify

```bash
spideriq convert ./safety-data-sheet.pdf          # polls for you, prints markdown
spideriq convert ./sheet.pdf --preview            # cheaper, first 1500 chars
spideriq convert ./big.pdf --no-wait              # prints the job_id instead
```

A good end-to-end check is a file whose extension **lies** — rename a PNG to
`.pdf` and confirm `source_format` comes back `image`. If it comes back `pdf`,
magic-byte detection is not reaching you and something is misconfigured.

---

# Part 2 — Mail bodies, markdown ↔ HTML

`convertMailBody` — one call, converted body in the response. No job, no polling.

This endpoint exists because the send path and the read path used to disagree
about *when* markdown→HTML should fire. The fix was to stop guessing: **you
declare both formats and nothing is ever sniffed from the content.**

```jsonc
POST /mail/convert
{ "from": "markdown", "to": "html", "content": "# Hi\n\nSee the **report**.", "mode": "fit" }

// → { content: "<h1>Hi</h1>…", from: "markdown", to: "html",
//     mode: "fit", size_original: 31, size_converted: 118 }
```

## The three modes

| `mode` | Use it when |
|---|---|
| `raw` | you want byte-identical output to what the existing send/read paths already produce — for parity checks and migrations |
| `fit` *(default)* | you want output adapted to the destination. **Round-trip stable**: md→html→md returns what you started with |
| `minimal` | you want the smallest faithful output — stripped of anything the destination does not need |

When in doubt, `fit`. It is the default precisely because it is the one that
behaves the way a caller intuitively expects.

## WRONG / RIGHT

```jsonc
// ❌ WRONG — letting the system infer the direction
{ "content": "<p>hello</p>", "to": "markdown" }
// 422. `from` is REQUIRED. Nothing is sniffed — that ambiguity is the bug
// this endpoint was built to remove.

// ✅ RIGHT
{ "from": "html", "to": "markdown", "content": "<p>hello</p>" }
```

```jsonc
// ❌ WRONG — a no-op conversion
{ "from": "html", "to": "html", "content": "<p>hi</p>" }
// 422 — `from` must differ from `to`.

// ✅ RIGHT — if you only want to know the size, measure it yourself
```

## Gotchas

- **🔴 The 65,536-byte cap counts UTF-8 BYTES, not characters.** This is the
  distinction card 3.2b was filed to fix. A body of 40,000 `é` characters is
  80,000 bytes and **is rejected with 413** even though it is well under 65,536
  characters. If you are sizing a body client-side, encode first and measure the
  buffer — `content.length` will lie to you on any non-ASCII body.

- **413 vs 422 are different failures.** `413` = too large. `422` = the request
  did not make sense (`from` missing, or `from === to`). Do not retry a 422 with
  a smaller body; it will fail identically.

- **This does not touch a mailbox.** It reads nothing and writes nothing — it is
  a pure transform, gated on `mail:read` only because that is the least
  privilege that still identifies the caller. It never marks a message read.

## Verify

```bash
# md → html, then back — `fit` should return the original
curl -sX POST https://spideriq.ai/api/v1/mail/convert \
  -H "Authorization: Bearer $SPIDERIQ_PAT" -H 'Content-Type: application/json' \
  -d '{"from":"markdown","to":"html","content":"# Hi\n\n**bold**"}'
```

The sharpest single check is the byte cap: send 65,536 bytes (expect `200`) and
then 65,537 (expect `413`). If both pass, you are not talking to a build that
carries the 3.2b fix.
