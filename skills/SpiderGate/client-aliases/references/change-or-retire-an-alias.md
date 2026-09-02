# Change or retire an alias without breaking callers

## Steps

1. **`getClientAlias(<leaf>)` first, always** — you need the current slot list
   before you can send a correct one.
2. Decide: park it (reversible) or delete it (permanent).
3. Apply the change.
4. Read it back.

## The one that bites: `slots` replaces

`slots` on update **overwrites the entire ordered chain**. It is not a merge and
not an append. There is no partial-slot syntax.

| You want to | Send |
|---|---|
| add a slot | the full existing list **plus** the new entry |
| remove a slot | the full existing list **minus** that entry |
| reorder | the full list in the new order |
| leave slots alone | omit `slots` entirely — do not send `[]` |

**Sending `slots: []` is not "leave them alone"** — an empty chain is refused
(1–16 entries), so you get an error rather than silence. Omitting the field is
the way to leave them untouched.

## Park vs delete

| | `updateClientAlias { enabled: false }` | `deleteClientAlias` |
|---|---|---|
| the chain | kept | destroyed |
| reversible | yes — flip `enabled` back | no |
| callers naming it | refused | refused |
| use when | you might want it back, or you are isolating a fault | it is genuinely finished |

**Prefer parking.** The observable behaviour for a caller is identical — both are
refused — so deleting buys nothing except the loss of the chain you would have
to rebuild by hand.

Note what does NOT happen on either: a request naming a parked or deleted alias
is **refused**. It does not fall back to a `spideriq/*` alias and it does not
reach our pool. Callers must be updated; nothing degrades gracefully on their
behalf, on purpose.

## Gotchas

- Writes need the `admin` role; reads need `member`. A `403` on update or delete
  is a role answer — report it rather than retrying.
- `description: null` clears the description; omitting the field leaves it.
- Deleting then recreating the same leaf gives you the same public name but a
  new row — nothing carries over.

## Verify

```
getClientAlias(<leaf>)   → the chain is exactly what you sent, in order
listClientAliases()      → after a delete, the leaf is absent
```
