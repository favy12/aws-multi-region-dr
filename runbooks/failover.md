# Runbook: regional failover

**Objective:** restore service in the standby region.
**RTO:** 30 minutes · **RPO:** 5 minutes (bounded by replica lag)

Read the decision gate before doing anything. Failover is not free — promoting the replica breaks replication permanently, and failing back is a longer, riskier operation than failing over.

---

## Decision gate

Fail over when **all** of these hold:

- The primary is unavailable or degraded beyond the error budget, and
- The cause is regional (AWS status page, multi-AZ impact) rather than a bad deploy, and
- A rollback of the last deploy has been ruled out or attempted, and
- Expected time-to-recovery in the primary exceeds 30 minutes

**Do not fail over for:** a bad deploy (roll back instead), a single-AZ failure (the primary is already multi-AZ), or a database performance problem that would follow you to the replica.

Declare an incident and name an incident commander before step 1. Everything below assumes one person is running it and calling the steps aloud.

---

## 1. Confirm the scope — 2 min

```bash
# Health check status as Route53 sees it
aws route53 get-health-check-status --health-check-id "$HEALTH_CHECK_ID"

# Is the standby actually healthy?
curl -sS -o /dev/null -w '%{http_code}\n' "https://$SECONDARY_FQDN/healthz/deep"

# How far behind is the database right now? This number is your data loss.
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value="$REPLICA_ID" \
  --start-time "$(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Maximum --region "$SECONDARY_REGION"
```

**Write down the replica lag.** It is the amount of data you are about to lose, and it goes in the incident record.

If the standby is not healthy, stop. Failing over to a broken region turns a partial outage into a total one.

---

## 2. Stop writes to the primary — 3 min

Skip only if the primary is already fully unreachable.

The failure mode this prevents is split-brain: the primary recovering while the standby is live, with both taking writes and no way to reconcile them.

```bash
# Scale the primary application to zero
kubectl --context "$PRIMARY_CONTEXT" scale deploy --all --replicas=0 -n "$APP_NAMESPACE"

# Revoke application access to the primary database
aws ec2 revoke-security-group-ingress \
  --group-id "$PRIMARY_DB_SG" --protocol tcp --port 5432 \
  --source-group "$PRIMARY_APP_SG" --region "$PRIMARY_REGION"
```

---

## 3. Promote the database replica — 5 to 10 min

**This is the irreversible step.** After it, the replica is a standalone primary and replication cannot be resumed — failing back means establishing replication in the other direction from scratch.

```bash
aws rds promote-read-replica \
  --db-instance-identifier "$REPLICA_ID" \
  --region "$SECONDARY_REGION"

aws rds wait db-instance-available \
  --db-instance-identifier "$REPLICA_ID" \
  --region "$SECONDARY_REGION"
```

Promotion typically completes in 5–10 minutes. The instance reboots as part of it.

Verify it is writable before continuing:

```bash
psql -h "$REPLICA_ENDPOINT" -U "$DB_USER" -c "SELECT pg_is_in_recovery();"
# must return f — t means promotion has not finished
```

---

## 4. Bring up the standby application — 5 min

```bash
kubectl --context "$SECONDARY_CONTEXT" scale deploy --all \
  --replicas="$PROD_REPLICA_COUNT" -n "$APP_NAMESPACE"

kubectl --context "$SECONDARY_CONTEXT" rollout status deploy/"$APP_NAME" \
  -n "$APP_NAMESPACE" --timeout=5m
```

Confirm the application is pointed at the promoted database, not still at a reader endpoint. This is the single most common failover mistake: everything comes up green and every write fails.

---

## 5. Shift DNS — automatic, 60 to 180 s

Route53 fails over on its own once the primary health check trips: `failure_threshold` × `request_interval` ≈ 90 seconds, plus the record TTL.

Confirm it happened:

```bash
dig +short "$RECORD_NAME"        # should return standby addresses
aws route53 get-health-check-status --health-check-id "$HEALTH_CHECK_ID"
```

If DNS has not moved but the standby is confirmed healthy, force it by disabling the primary health check:

```bash
aws route53 update-health-check --health-check-id "$HEALTH_CHECK_ID" --disabled
```

**Note this in the incident log.** A disabled health check will not re-enable itself, and a forgotten one means no automatic failover next time.

---

## 6. Verify — 5 min

- [ ] `dig $RECORD_NAME` returns standby addresses
- [ ] Synthetic checks green
- [ ] A write transaction succeeds end to end
- [ ] Error rate and latency within normal range
- [ ] Objects readable from the DR bucket
- [ ] Background jobs and cron are running in the standby
- [ ] Replica lag figure from step 1 recorded in the incident

---

## 7. After

- Post the customer-facing update
- Record the data-loss window from step 1
- Re-point the backup plan at the new primary — it is still configured against the failed region
- Schedule the failback review; **do not fail back during the same incident**
- File the post-incident review within 48 hours

---

## Rollback

There is none for step 3. Once promoted, returning to the original region is a failback: a planned operation with its own runbook, its own maintenance window, and replication established in the opposite direction.

See [failback.md](failback.md).
