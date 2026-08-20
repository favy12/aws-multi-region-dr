# RTO and RPO

Recovery objectives are commitments, not aspirations. Each number below has a measurement behind it.

---

## The numbers

| Objective | Target | Measured by |
| --- | --- | --- |
| **RTO** — time to restore service | 30 min | Wall-clock in the quarterly game day |
| **RPO** — acceptable data loss | 5 min | `ReplicaLag` alarm, threshold 300s |
| Detection | ~90 s | `failure_threshold` × `request_interval` |
| DNS propagation | 60–180 s | Record TTL |
| Database promotion | 5–10 min | Observed during game days |

---

## RTO breakdown

| Phase | Budget | Notes |
| --- | --- | --- |
| Detection | 2 min | Automatic; health checks trip at ~90s |
| Human decision | 5 min | The decision gate in the failover runbook |
| Stop writes | 3 min | Skipped when the primary is already gone |
| Promote replica | 10 min | The dominant term, and not compressible |
| Scale standby app | 5 min | Warm standby: images cached, nodes running |
| Verify | 5 min | Checklist in the runbook |
| **Total** | **30 min** | |

Promotion is the floor. Anything under about 20 minutes needs active-active, which is a different architecture and a different budget.

---

## RPO in practice

RPO is bounded by replica lag at the moment the primary is lost — not by the objective. Under normal load lag is seconds; under heavy write load or network stress it can grow.

This is why the `ReplicaLag` alarm exists, and why step 1 of the failover runbook records the current lag *before* promoting. That figure is the actual data loss for the incident, and it belongs in the post-incident review.

`treat_missing_data = "breaching"` on that alarm is deliberate: no data from a replication metric usually means replication has stopped.

### Per-data-type RPO

| Data | RPO | Mechanism |
| --- | --- | --- |
| Relational | seconds to 5 min | Async streaming replication |
| Objects | ≤ 15 min | S3 RTC |
| Backups | up to 24 h | Daily schedule, cross-region copy |
| In-flight requests | lost | Not replicated; the client must retry |

That last row is the one most often forgotten. Requests in flight at the moment of failure are gone. Clients need idempotency and retry, or the failover is invisible in the infrastructure and very visible to users.

---

## What is not covered

**Correlated failure.** Multi-region protects against a region. It does not protect against a bad schema migration that replicates in seconds, or a credential leak with account-wide scope. That is what backups with a vault lock are for — the only layer here that survives an actor with valid credentials.

**Control-plane dependency.** A severe enough IAM or Route53 disruption affects both regions. Rare, and out of scope for this design.

**Application state.** Sessions, caches, and queue contents do not replicate. If the application cannot tolerate losing them, the failover will surface that in the game day rather than in the incident.

---

## Reviewing these numbers

Revisit when:

- The business states a different tolerance — objectives are a product decision, not an infrastructure one
- A game day misses the target twice running
- Data volume grows enough to change promotion or sync time
- The architecture changes in a way that touches the failover path

An RTO that has not been tested in a quarter is a guess. The game-day record in [game-day.md](../runbooks/game-day.md) is what turns it back into a number.
