# The filter is accepted at exactly one endpoint — and a foreign id is 404, never 403

## The rule

A filter AST is accepted **only** by `POST .../selections`, where it is
validated, canonicalised and stored. The submit carries the `selection_id` alone,
and there is no field on it through which a predicate could travel.

```
POST /selections   { source_kind, stages, filter }   → selection_id
POST /submit       { source: { selection: { selection_id } } }     ← no filter
```

## Why, precisely

A body that could carry a predicate is a body that could carry **another
tenant's** predicate. If the submit accepted one, the only thing standing between
it and their rows would be application code remembering to apply a scope — and
"remembering" is not a security property.

An id resolved inside `WHERE client_id = <caller>` has no such seam. The schema
comes from the authenticated session; there is no AST node through which a
schema, table or column can be named at all.

## 🔴 The STATUS carries as much weight as the scoping

A `selection_id` belonging to another tenant must be **indistinguishable** from
one that never existed. A 403 — or any answer that fires only for a *real* id
owned by someone else — turns the submit route into an existence oracle over
another tenant's selections. Hence: **404, never 403.**

## Where this went wrong, and how

Three docstrings and the OpenAPI promised exactly that from I.1 onward:

> *"A selection_id belonging to another tenant resolves to a 404, never a 403 —
> a 403 would confirm the id exists."*

The shipped code returned **422**. `execute_submission` re-wrapped
`SelectionNotFoundError` into the generic `BulkRequestError`, which every door
renders as "your request is malformed" — so the one status the safety argument
turns on was the one status we did not return.

Corrected in I.4 (card BLS-42): the exception now propagates and all three
handlers (both submit doors plus `/estimate`) translate it to 404. The error
**code** is unchanged, so a client branching on `SELECTION_NOT_FOUND` keeps
working.

The general shape is worth keeping: **a documented status is a contract, and an
exception re-wrapped one layer down silently voids it.** The docstrings were
right and had been right for weeks; nothing compared them to the response.

## See also

- `recipes/run-internal.md`
- design §2.2 (a snapshot is an upload) and §6.4 (safety — an AST, never a string)
