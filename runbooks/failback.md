# Runbook: failback to the primary region

Returning to the original region after a failover. Unlike failover, this is **planned** — there is no time pressure, so it gets a maintenance window and a rehearsal.

**Do not run this during the incident that caused the failover.** Wait until the primary region has been stable for at least 24 hours.

---

## Why this is harder than failover

Failover promotes a replica that was already streaming. Failback has no such replica — the original primary is stale by however long you have been running in the standby, and that gap only grows.

You are building replication in the opposite direction from scratch, then cutting over to it.

---

## Pre-conditions

- [ ] Primary region stable ≥ 24 hours, AWS status green
- [ ] Root cause understood and addressed
- [ ] Maintenance window agreed and communicated
- [ ] Current primary (the promoted replica) has a fresh backup
- [ ] Runbook rehearsed in staging since the failover

---

## 1. Rebuild the primary region

The original database is stale and cannot catch up by replication — its timeline diverged at promotion.

```bash
# Delete the stale original. Snapshot first: it is the only record of
# anything written in the gap between last replication and promotion.
aws rds create-db-snapshot \
  --db-instance-identifier "$ORIGINAL_PRIMARY_ID" \
  --db-snapshot-identifier "${ORIGINAL_PRIMARY_ID}-pre-failback" \
  --region "$PRIMARY_REGION"

aws rds delete-db-instance \
  --db-instance-identifier "$ORIGINAL_PRIMARY_ID" \
  --skip-final-snapshot --region "$PRIMARY_REGION"
```

Then create a fresh cross-region replica **in the original region, from the current primary** — the reverse of normal. In Terraform, that means swapping the provider aliases in the `rds_replica` module call and applying.

---

## 2. Wait for the replica to catch up

```bash
watch -n 30 'aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value='"$NEW_REPLICA_ID"' \
  --start-time "$(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Maximum --region '"$PRIMARY_REGION"
```

Do not proceed until lag is consistently under 10 seconds. Initial sync on a large database can take hours — this is why failback needs its own window.

---

## 3. Cut over

Same shape as failover, opposite direction, but with the luxury of scheduling:

1. Announce the window
2. Drain writes in the current primary
3. Confirm lag has reached zero
4. Promote the replica in the original region
5. Move DNS back by re-enabling the primary health check
6. Scale the application up in the original region
7. Verify with the step 6 checklist from [failover.md](failover.md)

---

## 4. Restore DR posture

Failback is not done when traffic moves. It is done when you could fail over again.

- [ ] Re-establish the standby replica in the secondary region
- [ ] Confirm S3 replication is flowing in the correct direction
- [ ] Re-point the backup plan at the restored primary
- [ ] Re-enable the primary Route53 health check if it was manually disabled
- [ ] Confirm all DR alarms are in OK, not INSUFFICIENT_DATA
- [ ] Update the game-day record

**The most common failback failure is stopping at step 3.** Traffic is back where it belongs, everyone moves on, and the environment runs with no working DR until the next disaster reveals it.
