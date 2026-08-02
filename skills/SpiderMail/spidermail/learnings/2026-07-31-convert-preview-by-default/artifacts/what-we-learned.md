# `markdown: null` is not a failure — you asked for a preview

*Starting point, not ground truth — verify against current behaviour.*

## The surprise

A completed conversion can come back looking empty:

```json
{
  "markdown": null,
  "preview": "# SAFETY DATA SHEET\n\nSECTION 1: Identification…",
  "pages": 12,
  "source_format": "pdf",
  "truncated": true
}
```

Nothing failed. `full_text` defaults to **false**, so you were given the first
1500 characters in `preview` and `markdown` was never populated.

## Why it is that way

Most conversions exist to answer a cheap question — *what kind of document is
this?*, *which vendor sent it?*, *is this the invoice or the packing list?* —
and the answer is in the first paragraph. Shipping 400 KB of markdown to answer
it is waste that the caller pays for on every document.

So the default is the cheap answer, and the whole body is opt-in. (Same rule the
mail surface applies to attachments: full text is never sent to an agent
unrequested.)

## `truncated: true` has TWO causes — and they need opposite responses

This is the part that produces retry loops:

| `truncated` | `storage_key` | What happened | What to do |
|---|---|---|---|
| `true` | `null` | You asked for a preview | Re-submit with `full_text: true` |
| `true` | set | Body exceeded the 1 MB inline limit; the rest is on the CDN | **Follow `storage_key`.** Re-submitting truncates identically. |
| `false` | `null` | You have the whole thing | Nothing |

The failure mode is reading `truncated: true` as "the document got cut off" and
re-submitting the same request. In the second row that loops forever — the limit
is on what fits *inline*, not on what was extracted.

## The rule

1. Convert with the default (preview) when you are **classifying**.
2. Set `full_text: true` when you are **reading**.
3. On `truncated: true`, look at `storage_key` before you retry anything.

## Related

- **Check `security.safe` before feeding any of this to a model.** Extracted
  document text is a prompt-injection vector; the scanner's verdict rides along
  on the result and the text is returned unmodified either way.
- `source_format` reports what the **magic bytes** said, not what you declared.
  A `.pdf` that is really a PNG comes back as `image`.
