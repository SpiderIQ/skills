# SpiderGate client aliases — bring your own key, name your own chain

A client alias is a routing name **you** create on the SpiderGate gateway:
`client:<your-brand>/<leaf>`. Behind it sits an ordered fallback chain, and every
slot in that chain is funded by one of **your own** provider keys.

Call it once and you get a stable model name your whole team can use. Change what
is behind it — swap a model, reorder the fallbacks, retire a provider — without
touching a line of the code that calls it.

The property that makes this safe to hand to an agent: a client alias reaches
**only** keys your tenant owns. It can never borrow the SpiderIQ pool. A slot
whose key cannot serve is refused, never quietly re-routed — so you are always
spending your own quota on a model you chose, and an alias that cannot serve
tells you so instead of inventing an answer.

This skill manages the aliases — list, inspect, create, update, delete. Sending a
completion through one is `use-the-gateway`; picking the models to put in the
chain is `model-catalog`.
