# Game day: quarterly failover exercise

A DR plan that has never been executed is a hypothesis. This is how it gets tested.

**Cadence:** quarterly, and after any change to the failover path.
**Duration:** 2 hours including the debrief.
**Environment:** staging, with the same topology as production.

---

## Why staging and not production

Production game days are the gold standard and most teams are not ready for them. The honest progression:

1. **Tabletop** — walk the runbook aloud, no commands. Catches missing steps and unknown owners.
2. **Staging failover** — full execution against a production-shaped staging stack. This is the default.
3. **Production failover** — a real one during a maintenance window, once staging has been clean twice running.

Skipping to 3 usually produces an incident, which teaches the wrong lesson: that game days are dangerous, rather than that the plan was untested.

---

## Roles

| Role | Responsibility |
| --- | --- |
| Incident commander | Calls each step, owns the abort decision |
| Operator | Runs the commands, reads results aloud |
| Scribe | Timestamps every step, records what surprised people |
| Observer | Watches dashboards; does not help |

The observer not helping is the point. If the runbook only works because someone knew a thing that isn't written down, this is where that surfaces.

---

## Pre-flight

- [ ] Staging mirrors production topology
- [ ] Replication is healthy and lag is normal
- [ ] Everyone has console and CLI access to **both** regions (verify — do not assume)
- [ ] Announce the window; nobody should be debugging a "real" staging outage
- [ ] Baseline metrics captured

---

## Execution

Run [failover.md](failover.md) exactly as written. **Do not improvise.**

When a step is wrong or missing, the operator says so, the scribe records it, and the commander decides whether to work around it. The workaround is the finding. Silently doing the right thing instead of the written thing wastes the exercise.

Record the wall-clock time for each step:

| Step | Target | Actual | Notes |
| --- | --- | --- | --- |
| 1. Confirm scope | 2 min | | |
| 2. Stop writes | 3 min | | |
| 3. Promote replica | 10 min | | |
| 4. Start standby app | 5 min | | |
| 5. DNS shift | 3 min | | |
| 6. Verify | 5 min | | |
| **Total** | **30 min** | | |

---

## Injected failures

Pick one per game day. Do not announce which.

- **Stale credentials** — the standby's database secret was rotated in the primary only
- **Undersized standby** — scale the standby node group to half; does anyone notice before user impact?
- **Missing runbook owner** — the person who normally runs failover is "unavailable"
- **Replica lag** — generate write load so promotion happens with visible data loss; is it measured and recorded?
- **Partial failure** — the app is healthy but the deep health check fails; does anyone check whether failover was warranted?

---

## Abort criteria

Stop and restore if:

- Real production impact appears
- Data loss beyond what the exercise scoped for
- A step fails in a way nobody present understands

Aborting is a successful game day. It found something.

---

## Debrief — within 24 hours

Three questions:

1. **What took longer than expected?** Time, not opinion.
2. **What was not in the runbook?** Every improvisation becomes a runbook edit.
3. **What would have gone differently at 3am, with one tired person?**

Every finding gets an owner and a date. Findings without owners are notes, and notes do not fix DR.

---

## Record

| Date | Type | RTO achieved | Findings | Owner |
| --- | --- | --- | --- | --- |
| | | | | |

Keep this table in the repo. "When did we last test failover?" should be answerable in one look — and if the answer is more than a quarter ago, the RTO number in the README is a guess.
