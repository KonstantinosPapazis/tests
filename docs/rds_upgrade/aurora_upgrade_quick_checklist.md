# Aurora PostgreSQL 13→16 Quick Checklist

**Use this as your day-of-upgrade checklist**

---

## T-1 Week

- [ ] Complete test environment upgrade
- [ ] All application testing passed
- [ ] Drivers updated to compatible versions
- [ ] Stakeholders notified
- [ ] Maintenance window scheduled

## T-24 Hours

- [ ] Final snapshot created
- [ ] Snapshot retention extended
- [ ] Baseline metrics captured
- [ ] Team availability confirmed
- [ ] 24-hour notice sent

## T-1 Hour

- [ ] System health verified (no active incidents)
- [ ] All team members online
- [ ] War room/bridge open
- [ ] Scripts staged and reviewed
- [ ] "Maintenance starting" notification ready

## Go/No-Go Decision

**Proceed ONLY if ALL are YES:**
- [ ] Test environment upgrade successful
- [ ] All critical tests passed
- [ ] No P0/P1 incidents in progress
- [ ] Full team available
- [ ] Rollback plan ready
- [ ] Stakeholders acknowledged

## Upgrade Execution

### Using Blue/Green (Recommended)

- [ ] Create final pre-upgrade snapshot
- [ ] Initiate Blue/Green deployment
- [ ] Wait for Green environment (15-30 min)
- [ ] Record Green endpoint
- [ ] Run smoke tests on Green
- [ ] Validate version: `SELECT version();`
- [ ] Check extensions: `SELECT * FROM pg_extension;`
- [ ] Test application connectivity
- [ ] Review query performance samples
- [ ] **DECISION POINT**: Proceed or Abort?
- [ ] Perform switchover
- [ ] Monitor switchover (2-5 min)
- [ ] Verify production now on 16.9
- [ ] Send completion notification

### Using Direct Upgrade (Not Recommended)

- [ ] Create final pre-upgrade snapshot
- [ ] Initiate upgrade with `modify-db-cluster`
- [ ] Wait for upgrade completion (30-60 min)
- [ ] Verify new version
- [ ] Test connectivity
- [ ] Monitor for issues

## Immediate Validation (First 15 min)

```sql
-- Run these queries:
SELECT version();
SELECT * FROM pg_extension ORDER BY extname;
SELECT COUNT(*) FROM pg_stat_activity;
```

- [ ] Version shows 16.9
- [ ] All extensions loaded
- [ ] Connections working
- [ ] No errors in application logs

## Extended Monitoring (First 2 hours)

- [ ] Application error rates normal
- [ ] Database connections stable
- [ ] Query performance acceptable
- [ ] No CloudWatch alarms
- [ ] CPU/Memory usage normal

## Rollback Triggers

**Initiate rollback if:**
- [ ] Application error rate >10% increase
- [ ] Critical functionality broken
- [ ] Query performance >50% degradation
- [ ] Connection pool exhausted
- [ ] Data integrity issues

## Post-Upgrade (Within 24 hours)

- [ ] Run `ANALYZE VERBOSE;`
- [ ] Update extensions if needed
- [ ] Review slow query log
- [ ] Document any issues
- [ ] Send final status report
- [ ] Schedule retention of old environment

## Day 2-7

- [ ] Continue monitoring metrics
- [ ] Review Performance Insights
- [ ] Gather feedback from teams
- [ ] Delete Blue/Green old environment (after 7 days)
- [ ] Update documentation
- [ ] Post-mortem if needed

---

## Quick Commands Reference

```bash
# Check upgrade path
aws rds describe-db-engine-versions --engine aurora-postgresql --engine-version 13.20 \
  --query 'DBEngineVersions[*].ValidUpgradeTarget[*].EngineVersion' --output table

# Create snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier CLUSTER-pre-pg16-$(date +%Y%m%d-%H%M) \
  --db-cluster-identifier CLUSTER_NAME

# Create Blue/Green
aws rds create-blue-green-deployment \
  --blue-green-deployment-name CLUSTER-pg16-upgrade \
  --source-arn arn:aws:rds:REGION:ACCOUNT:cluster:CLUSTER_NAME \
  --target-engine-version 16.9

# Check Blue/Green status
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier DEPLOYMENT_ID

# Switchover
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier DEPLOYMENT_ID

# Rollback (switch back)
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier DEPLOYMENT_ID
```

---

## Emergency Contacts

**Fill in your team's information:**

- **On-Call Engineer:** ___________________
- **Database Lead:** ___________________
- **Application Owner:** ___________________
- **Escalation Path:** ___________________
- **War Room Link:** ___________________

---

## Key Metrics to Watch

| Metric | Pre-Upgrade | Post-Upgrade | Status |
|--------|-------------|--------------|--------|
| Avg Response Time | _____ ms | _____ ms | _____ |
| Connection Count | _____ | _____ | _____ |
| CPU Usage | _____% | _____% | _____ |
| Error Rate | _____% | _____% | _____ |

---

**Document Version:** 1.0  
**Last Updated:** 2025-10-27

