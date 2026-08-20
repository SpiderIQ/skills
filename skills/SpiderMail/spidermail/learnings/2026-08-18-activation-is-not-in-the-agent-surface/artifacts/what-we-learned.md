# There is no `sendActivateCampaign` — and that is the enforcement

## What happened

Phase 4 gave agents a complete campaign authoring surface: create the sequence
shell, add steps, write A/B arms, attach sending mailboxes, render every step
server-side. Sixteen methods. One verb is missing on purpose.

`sendActivateCampaign` does not exist on the skill, `send_activate_campaign`
does not exist on the MCP surface, and `spideriq send campaign activate` exists
only to print where the act belongs.

## Why the route, not just the missing tool

Shipping no tool would have looked like enforcement and been nothing of the
kind. The dashboard API is reachable with a client PAT — the same credential the
agent surface uses — so an agent that wanted a campaign armed could simply POST
the route itself. The gate had to be on the route:

```python
_tenant_arm = require_tenant_scoped_access(min_role="admin", allow_api_client=False)
```

The missing tool is the second half of a rule the server already enforces. This
is the same argument, and the same shape, as the paste-consent write routes one
file over: *a parameter cannot authorise the call it rides on*, and neither can
a token authorise a decision that belongs to a person.

## The asymmetry is the point

`sendPauseCampaign` and `sendStopCampaign` **are** on the agent surface.

An agent may always stop mail and may never start it. That is not a compromise
between the two — it is what makes the restriction safe to live with. A safety
verb an agent cannot reach is a safety verb nobody uses at 3am, when the person
who could reach it is asleep and a sequence is mailing the wrong list.

## The failure this actually prevents

Not a bad send. A **wrong report**.

The realistic accident is not an agent maliciously arming a campaign; it is an
agent composing a careful five-touch sequence, attaching a source, and telling
its user *"your campaign is live."* It is a draft. It will stay a draft. Nobody
finds out until someone asks why there have been no replies — and by then the
window the campaign was built for has passed.

So the discipline is verbal as much as technical:

> **Say "ready to activate", never "running" or "live".** Name where: Mail →
> Campaigns → open it → Activate. And name anything still outstanding.

## What to check before you say it

The route refuses three states by name, and each is fixable by the agent —
which is why they are worth checking before handing over rather than after:

| Refusal | Means | You fix it with |
|---|---|---|
| `no_steps` | no email step — arming it would send nothing | `sendAddStep` |
| `step_without_variant` | a step has no copy; it resolves to nothing at send time | `sendAddVariant` |
| `no_sources` | no attached mailbox, so no way out | `sendAttachSource` |

Plus the two that `sendPreviewStep` alone reveals, both silent on a live send:
merge tags that will render empty, and a workspace with no postal address
recorded (which makes the send refuse at queue time, days later).

## Generalisation

When a capability is withheld from an agent, put the gate where the capability
lives and let the missing tool be the *documentation* of it. A missing tool with
an open route is a convention; a closed route with a missing tool is a control.

And when the withheld act is the last step of a flow the agent otherwise owns
end to end, the agent's real job becomes handing over accurately: what is ready,
what is not, and exactly where the human goes.
