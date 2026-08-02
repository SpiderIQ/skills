# `status` has five values, and bulk rows can be errors

**Starting point, not ground truth — verify against current code.**

## The surprise

The docs headline four statuses — `valid` / `invalid` / `risky` / `unknown`. Code
that only handles those four mis-reads two real, common shapes.

## 1. `skipped` — the FuzzIQ cached verdict

With `fuzziq_enabled: true`, an address already verified for your tenant is **not
re-probed**. Instead:

- **Single:** `results[0].status == "skipped"` with `reason: "already_verified"`.
- **Whole batch already known:** `results: []` (empty) with `summary.skipped` set
  and `reason: "all_already_verified"`.

Both are **successes**. An empty `results[]` here is "nothing new to verify", not
a failure — don't alarm. Reuse the prior verdict for a `skipped` row.

## 2. Per-email errors in a batch

If one address throws mid-probe, the batch doesn't fail — that row comes back as:

```yaml
email: broken@example
status: unknown
sub_status: "error: <the real message>"
score: 0
flags: { is_valid_syntax: true, is_deliverable: false }   # only two flags
```

Treat it like any other `unknown`: re-verify; don't fold it into `invalid`.

## 3. `sub_status` is first-match-wins

`sub_status` is decided top-down and returns the **first** matching condition, in
this fixed order:

```
catch_all > disposable > role_account > disabled > full_inbox
  > smtp_unreachable > deliverable > mailbox_not_found > ""
```

So a catch-all **role** account reads `sub_status: catch_all`, and you'd wrongly
conclude "not a role account" if you read `sub_status` alone. The `flags` block is
a set of **independent** booleans — read `flags.is_role_account` /
`flags.is_disposable` / `flags.is_catch_all` to detect each property, and use
`sub_status` only as the headline reason.

## Rule of thumb

Handle five statuses, not four (`skipped` is normal with dedup on). Empty
`results[]` + `summary.skipped` is a success. A `sub_status` starting `error:` is
a soft per-email failure → re-verify. Detect role/disposable/catch-all from the
independent `flags`, never from `sub_status` alone.
