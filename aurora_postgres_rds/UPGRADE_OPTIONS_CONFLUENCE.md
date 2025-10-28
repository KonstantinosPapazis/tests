# Aurora PostgreSQL Major Version Upgrade Guide
## Version 13.20 → 16.8

**Document Version:** 1.0  
**Last Updated:** October 2025  
**Target Audience:** DevOps, Platform Engineers, DBAs

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Prerequisites](#prerequisites)
3. [Option 1: Blue/Green Deployment (Recommended for Production)](#option-1-bluegreen-deployment)
4. [Option 2: Direct In-Place Upgrade (For Dev/Test)](#option-2-direct-in-place-upgrade)
5. [Comparison Matrix](#comparison-matrix)
6. [Decision Guide](#decision-guide)
7. [Post-Upgrade Tasks](#post-upgrade-tasks)
8. [Troubleshooting](#troubleshooting)

---

## Executive Summary

This document outlines two approaches for upgrading Aurora PostgreSQL from version 13.20 to 16.8 when using Terragrunt for infrastructure management.

### Quick Comparison

| Approach | Downtime | Rollback Time | Data Loss Risk | Complexity | Best For |
|----------|----------|---------------|----------------|------------|----------|
| **Blue/Green** | 15-30 sec | 15-30 sec | None | High | Production |
| **Direct Upgrade** | 30-60 min | 15-30 min | Possible | Low | Dev/Test |

---

## Prerequisites

### All Approaches Require

✅ **Parameter Group Check (Blue/Green Only)**

⚠️ **IMPORTANT:** If planning to use Blue/Green deployment, verify your current cluster is **NOT using a default parameter group**.

```bash
# Check current parameter group
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].DBClusterParameterGroup' \
  --output text
```

**If output is `default.aurora-postgresql13` or similar:**
- ❌ Blue/Green will **NOT work** with default parameter groups
- ✅ You must migrate to a custom parameter group **before** attempting Blue/Green
- ✅ See troubleshooting section for migration steps

**If output is a custom name (e.g., `myapp-pg13-params`):**
- ✅ You can proceed with Blue/Green deployment

💡 **Why?** AWS default parameter groups are read-only and managed by AWS. Blue/Green deployments require custom parameter groups to ensure you control the configuration during upgrades.

✅ **Backup Verification**
```bash
# Verify automated backups are enabled
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].[BackupRetentionPeriod,PreferredBackupWindow]'
```

✅ **AWS CLI Configuration**
```bash
# Verify AWS CLI is configured
aws sts get-caller-identity

# Verify access to your cluster
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name
```

✅ **Terragrunt Version**
- Terragrunt >= 0.48.0
- Terraform >= 1.5.0

✅ **Communication Plan**
- Stakeholder notification
- Maintenance window scheduling
- Rollback plan documented

---

## Option 1: Blue/Green Deployment

**Recommended for: Production environments**

### Overview

Blue/Green deployment creates an exact copy of your cluster running PostgreSQL 16.8, allowing you to test thoroughly before switching production traffic.

### Advantages
- ✅ Minimal downtime (15-30 seconds)
- ✅ Test with production data before going live
- ✅ Instant rollback capability
- ✅ No data loss risk
- ✅ Old cluster preserved for 24 hours

### Disadvantages
- ⚠️ More complex setup
- ⚠️ Temporary cost increase (2x clusters during testing)
- ⚠️ Requires temporary capacity increase
- ⚠️ **Cannot use default parameter groups** (must create custom)

---

### Phase 1: Preparation

#### Step 1.1: Scale Serverless Capacity

**Important:** Blue/Green deployment requires minimum capacity >= 1.0 ACU due to running two clusters simultaneously.

```bash
# Current configuration in terragrunt.hcl
inputs = {
  serverless_min_capacity = 0.5
  serverless_max_capacity = 4
  engine_version = "13.20"
}
```

**Scale up the running cluster (no downtime):**

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier your-cluster-name \
  --serverless-v2-scaling-configuration MinCapacity=1.0,MaxCapacity=4 \
  --apply-immediately \
  --region us-west-2

# Wait for modification to complete
aws rds wait db-cluster-available \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2
```

⏱️ **Duration:** 1-2 minutes  
🔌 **Downtime:** None  
💡 **Note:** This is an online operation with no connection interruption

#### Step 1.2: Create Final Pre-Upgrade Snapshot

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier your-cluster-before-pg16-${TIMESTAMP} \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2

# Wait for snapshot completion
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier your-cluster-before-pg16-${TIMESTAMP} \
  --region us-west-2
```

⏱️ **Duration:** 5-15 minutes

#### Step 1.3: Create PostgreSQL 16 Parameter Group

⚠️ **CRITICAL REQUIREMENT:** Blue/Green deployments **DO NOT support default parameter groups**. You must create a **custom parameter group** even if you want to use default values.

**Why?** Default parameter groups (e.g., `default.aurora-postgresql16`) are AWS-managed and read-only. Blue/Green deployments require you to specify a custom parameter group to ensure you have control over configuration during the upgrade.

Since your Terragrunt module manages parameters internally, create the v16 parameter group manually:

```bash
# Create cluster parameter group
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name your-cluster-pg16-cluster \
  --db-parameter-group-family aurora-postgresql16 \
  --description "PostgreSQL 16 cluster parameters" \
  --region us-west-2

# Apply your custom parameters (example: max_connections)
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name your-cluster-pg16-cluster \
  --parameters "ParameterName=max_connections,ParameterValue=20,ApplyMethod=pending-reboot" \
  --region us-west-2
```

💡 **Note:** Adjust parameters to match your current configuration

---

### Phase 2: Create Blue/Green Deployment

#### Step 2.1: Initiate Blue/Green Deployment

```bash
# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create deployment
aws rds create-blue-green-deployment \
  --blue-green-deployment-name your-cluster-to-pg16-$(date +%Y%m%d) \
  --source-arn arn:aws:rds:us-west-2:${AWS_ACCOUNT_ID}:cluster:your-cluster-name \
  --target-engine-version 16.8 \
  --target-db-cluster-parameter-group-name your-cluster-pg16-cluster \
  --region us-west-2 \
  --tags Key=Environment,Value=production Key=Purpose,Value=MajorUpgrade
```

**Save the deployment ID from the output:**
```json
{
  "BlueGreenDeploymentIdentifier": "bgd-abc123xyz456"
}
```

#### Step 2.2: Monitor Deployment Creation

```bash
# Check status
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier bgd-abc123xyz456 \
  --region us-west-2 \
  --query 'BlueGreenDeployments[0].Status'

# Wait for "AVAILABLE" status
```

⏱️ **Duration:** 15-25 minutes  
💡 **What's happening:** AWS creates a complete copy of your cluster on PostgreSQL 16.8

#### Step 2.3: Get Green Cluster Endpoint

```bash
# Get green cluster ID
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier bgd-abc123xyz456 \
  --region us-west-2 \
  --query 'BlueGreenDeployments[0].Target'

# Get green endpoint
aws rds describe-db-clusters \
  --db-cluster-identifier your-green-cluster-id \
  --region us-west-2 \
  --query 'DBClusters[0].Endpoint'
```

**Example output:**
```
your-cluster-green-abc123.cluster-xyz.us-west-2.rds.amazonaws.com
```

---

### Phase 3: Testing

#### Step 3.1: Verify PostgreSQL Version

```bash
# Connect to green cluster and verify
psql "postgresql://username@green-endpoint:5432/database?sslmode=require" \
  -c "SELECT version();"
```

Expected output should show PostgreSQL 16.8.

#### Step 3.2: Run Application Tests

1. **Update application configuration** temporarily to point to green endpoint
2. **Run full test suite** against green environment
3. **Verify critical workflows** function correctly
4. **Compare query performance** with production

⏱️ **Recommended testing duration:** 2-4 hours minimum

#### Step 3.3: Validation Checklist

```markdown
- [ ] Database connection successful
- [ ] All extensions loaded correctly
- [ ] Application CRUD operations work
- [ ] Stored procedures execute without errors
- [ ] Query performance acceptable or improved
- [ ] Replication lag within acceptable range
- [ ] Monitoring dashboards functional
```

---

### Phase 4: Switchover to Production

#### Step 4.1: Pre-Switchover Checklist

```markdown
- [ ] All tests passed successfully
- [ ] Stakeholders notified
- [ ] Rollback procedure reviewed
- [ ] Monitoring dashboards prepared
- [ ] Support team on standby
- [ ] Application ready for brief connection interruption
```

#### Step 4.2: Execute Switchover

⚠️ **Warning:** This causes 15-30 seconds of downtime

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier bgd-abc123xyz456 \
  --switchover-timeout 300 \
  --region us-west-2
```

#### Step 4.3: Monitor Switchover

```bash
# Check switchover status
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier bgd-abc123xyz456 \
  --region us-west-2 \
  --query 'BlueGreenDeployments[0].Status'

# Wait for "SWITCHOVER_COMPLETED"
```

⏱️ **Duration:** 15-30 seconds  
🔌 **Downtime:** 15-30 seconds (DNS switchover)

#### Step 4.4: Verify Switchover

```bash
# Verify production cluster is now running v16.8
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2 \
  --query 'DBClusters[0].EngineVersion'
```

Expected output: `16.8`

---

### Phase 5: Post-Switchover

#### Step 5.1: Monitor Production (First 2 Hours)

**Immediate checks:**
- Application error rates
- Database connection counts
- Query latency
- CloudWatch alarms
- User-reported issues

**CloudWatch metrics to monitor:**
```bash
# CPU Utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=your-cluster-name \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-west-2
```

#### Step 5.2: Scale Back Capacity (Optional)

After 24-48 hours of successful operation, you can scale back to 0.5 ACU if desired:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier your-cluster-name \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=4 \
  --apply-immediately \
  --region us-west-2
```

#### Step 5.3: Update Terragrunt Configuration

**After 24-48 hours of validation**, update your `terragrunt.hcl`:

```hcl
inputs = {
  engine_version = "16.8"              # ← Changed from "13.20"
  serverless_min_capacity = 0.5        # ← Can scale back down
  serverless_max_capacity = 4
  
  # Rest of configuration unchanged
  allowed_security_groups = [ ... ]
  parameter_group = [
    max_connections = 20
  ]
  kms_key_id = "..."
  tags = { ... }
}
```

**Verify Terragrunt state:**
```bash
cd /path/to/terragrunt/config
terragrunt plan
```

Expected: Should show no changes or minimal parameter adjustments

#### Step 5.4: Clean Up Blue/Green Deployment

After 24-48 hours of successful operation:

```bash
# Delete the old Blue/Green deployment (removes old v13 cluster)
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier bgd-abc123xyz456 \
  --delete-target \
  --region us-west-2
```

⚠️ **Important:** After this, you cannot instantly rollback. Only do this after thorough validation.

---

### Rollback Procedure (If Needed)

#### Immediate Rollback (Within 24 Hours of Switchover)

If critical issues are discovered:

```bash
# Switch back to v13.20 cluster
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier bgd-abc123xyz456 \
  --switchover-timeout 300 \
  --region us-west-2
```

⏱️ **Rollback time:** 15-30 seconds  
📊 **Data loss:** None (reverts to pre-switchover state)

#### Late Rollback (After 24 Hours)

If Blue/Green deployment already deleted:

```bash
# Restore from snapshot
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier your-cluster-name-restored \
  --snapshot-identifier your-cluster-before-pg16-20241028 \
  --engine aurora-postgresql \
  --engine-version 13.20 \
  --region us-west-2

# Update application to point to restored cluster
```

⏱️ **Rollback time:** 15-30 minutes  
📊 **Data loss:** Changes made after snapshot

---

## Option 2: Direct In-Place Upgrade

**Recommended for: Development and staging environments**

### Overview

Direct in-place upgrade modifies your existing cluster to PostgreSQL 16.8 by updating the Terragrunt configuration and applying the change.

### Advantages
- ✅ Simpler process
- ✅ Lower cost (no second cluster)
- ✅ No capacity scaling required
- ✅ Fewer steps

### Disadvantages
- ⚠️ 30-60 minutes downtime
- ⚠️ No testing before production
- ⚠️ Slower rollback
- ⚠️ Potential data loss in rollback

---

### Phase 1: Preparation

#### Step 1.1: Create Manual Snapshot

```bash
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier your-cluster-before-pg16-${TIMESTAMP} \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2

# Wait for snapshot completion
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier your-cluster-before-pg16-${TIMESTAMP} \
  --region us-west-2
```

⏱️ **Duration:** 5-15 minutes  
💡 **Critical:** This is your only safety net for rollback

#### Step 1.2: Verify Snapshot

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier your-cluster-before-pg16-${TIMESTAMP} \
  --region us-west-2 \
  --query 'DBClusterSnapshots[0].[Status,SnapshotCreateTime,AllocatedStorage]'
```

Ensure status is `available`.

---

### Phase 2: Update Configuration

#### Step 2.1: Modify terragrunt.hcl

**Current configuration:**
```hcl
inputs = {
  serverless_min_capacity = 0.5
  serverless_max_capacity = 4
  engine_version = "13.20"          # ← Current version
  
  allowed_security_groups = [ ... ]
  parameter_group = [
    max_connections = 20
  ]
  kms_key_id = "..."
  tags = { ... }
}
```

**Updated configuration:**
```hcl
inputs = {
  serverless_min_capacity = 0.5     # ← No change needed
  serverless_max_capacity = 4       # ← No change needed
  engine_version = "16.8"           # ← Changed to target version
  
  allowed_security_groups = [ ... ] # ← No changes
  parameter_group = [
    max_connections = 20             # ← No changes
  ]
  kms_key_id = "..."                # ← No changes
  tags = { ... }                    # ← No changes
}
```

💡 **Note:** Only `engine_version` needs to change

---

### Phase 3: Apply Upgrade

#### Step 3.1: Review Terraform Plan

```bash
cd /path/to/terragrunt/config

terragrunt plan
```

**Expected changes:**
```
~ engine_version: "13.20" -> "16.8"
~ db_cluster_parameter_group_name: "xxx-pg13" -> "xxx-pg16" (if module manages this)

Plan: 0 to add, 1 to change, 0 to destroy
```

#### Step 3.2: Apply Upgrade

⚠️ **Warning:** This causes 30-60 minutes of downtime

```bash
# Schedule during maintenance window
# Notify all stakeholders before proceeding

terragrunt apply
```

**What happens:**
1. Terraform modifies the cluster to use engine version 16.8
2. AWS performs the major version upgrade
3. Cluster restarts with new version
4. Instances become available

⏱️ **Duration:** 30-60 minutes  
🔌 **Downtime:** Entire duration (30-60 minutes)  
💡 **Monitoring:** Track progress in AWS Console or via CLI

#### Step 3.3: Monitor Upgrade Progress

```bash
# Check cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2 \
  --query 'DBClusters[0].[Status,EngineVersion]'

# Wait for status: "available"
aws rds wait db-cluster-available \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2
```

**Status progression:**
1. `modifying` - Upgrade in progress
2. `upgrading` - PostgreSQL upgrade happening
3. `available` - Upgrade complete

---

### Phase 4: Validation

#### Step 4.1: Verify Upgrade Success

```bash
# Verify version
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2 \
  --query 'DBClusters[0].EngineVersion'
```

Expected: `16.8`

#### Step 4.2: Application Testing

1. **Verify database connectivity**
2. **Test critical application workflows**
3. **Check for errors in application logs**
4. **Monitor query performance**
5. **Verify all features working**

#### Step 4.3: Validation Checklist

```markdown
- [ ] Cluster status is "available"
- [ ] Engine version is 16.8
- [ ] Application can connect
- [ ] Critical queries execute successfully
- [ ] No errors in CloudWatch logs
- [ ] Performance within acceptable range
- [ ] All application features functional
```

---

### Rollback Procedure

#### If Issues Discovered After Upgrade

⚠️ **Warning:** Rollback requires deleting the upgraded cluster and restoring from snapshot

#### Step 1: Delete Upgraded Cluster

```bash
# Delete the v16 cluster
aws rds delete-db-cluster \
  --db-cluster-identifier your-cluster-name \
  --skip-final-snapshot \
  --region us-west-2
```

⏱️ **Duration:** 5-10 minutes

#### Step 2: Restore from Snapshot

```bash
# Restore from v13 snapshot
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier your-cluster-name \
  --snapshot-identifier your-cluster-before-pg16-20241028 \
  --engine aurora-postgresql \
  --engine-version 13.20 \
  --db-cluster-parameter-group-name your-original-pg13-param-group \
  --vpc-security-group-ids sg-xxxxx \
  --db-subnet-group-name your-subnet-group \
  --region us-west-2
```

#### Step 3: Recreate Instances

```bash
aws rds create-db-instance \
  --db-instance-identifier your-cluster-instance-1 \
  --db-cluster-identifier your-cluster-name \
  --engine aurora-postgresql \
  --db-instance-class db.serverless \
  --region us-west-2
```

#### Step 4: Wait for Availability

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier your-cluster-name \
  --region us-west-2
```

#### Step 5: Revert Terragrunt Configuration

```hcl
inputs = {
  engine_version = "13.20"  # ← Revert to v13
  # ... rest unchanged
}
```

```bash
# Verify Terragrunt state matches
terragrunt plan
# Should show no changes
```

⏱️ **Total rollback time:** 15-30 minutes  
📊 **Data loss:** All changes made after snapshot was taken

---

## Comparison Matrix

### Detailed Comparison

| Factor | Blue/Green Deployment | Direct In-Place Upgrade |
|--------|----------------------|------------------------|
| **Setup Complexity** | High (multiple steps) | Low (simple config change) |
| **Pre-upgrade Testing** | Yes (full production data) | No |
| **Downtime** | 15-30 seconds | 30-60 minutes |
| **Cost During Upgrade** | ~2x (two clusters) | 1x (single cluster) |
| **Min Capacity Requirement** | >= 1.0 ACU temporarily | No change (0.5 ACU fine) |
| **Rollback Speed** | 15-30 seconds | 15-30 minutes |
| **Rollback Data Loss** | None | Possible (since snapshot) |
| **Risk Level** | Low | Medium-High |
| **Terraform Changes** | After upgrade | Before upgrade |
| **Parameter Group Handling** | Manual creation needed | Module handles automatically |
| **Testing Window** | Unlimited (before switch) | After upgrade only |
| **Production Impact** | Minimal | Significant |
| **Complexity for Rollback** | Simple (one command) | Complex (delete + restore) |

### Cost Analysis

**Blue/Green Deployment:**
```
Base cost: 1x cluster running (normal)
During testing (1-4 hours): 2x cluster cost
After switchover: 1x cluster (can delete old)
Cleanup after 24h: 1x cluster

Additional cost: ~4-48 hours of doubled cluster cost
Example: If cluster costs $10/hour, additional cost = $40-480
```

**Direct Upgrade:**
```
Base cost: 1x cluster running (normal)
During upgrade: 1x cluster (unavailable)
After upgrade: 1x cluster

Additional cost: $0
But: Business cost of 30-60 min downtime
```

### Timeline Comparison

**Blue/Green Deployment:**
```
T+0:00   - Scale capacity (1-2 min, no downtime)
T+0:02   - Create snapshot (5-15 min)
T+0:17   - Create parameter group (2 min)
T+0:19   - Start Blue/Green (15-25 min automated)
T+0:44   - Green ready, begin testing (1-4 hours)
T+4:44   - Switchover (15-30 sec downtime)
T+4:45   - Validation (ongoing)

Total elapsed: ~5 hours
Total downtime: 15-30 seconds
```

**Direct Upgrade:**
```
T+0:00   - Create snapshot (5-15 min)
T+0:15   - Update terragrunt.hcl (2 min)
T+0:17   - Apply upgrade (30-60 min downtime)
T+1:17   - Validation (ongoing)

Total elapsed: ~1.5 hours
Total downtime: 30-60 minutes
```

---

## Decision Guide

### Choose Blue/Green Deployment If:

✅ **Environment is production**
- Downtime must be minimized
- Business impact of downtime is high
- Users/customers are actively using the system

✅ **Testing is required**
- Need to validate application behavior before production
- Want to compare performance before committing
- Risk-averse approach preferred

✅ **Data loss is unacceptable**
- Cannot afford to lose any transactions
- Rollback must preserve all data
- Compliance requirements for data integrity

✅ **Budget allows**
- Can absorb 2-4 hours of doubled infrastructure cost
- Business value exceeds infrastructure cost

**Example scenarios:**
- Customer-facing production databases
- Revenue-generating applications
- Services with strict SLAs
- Compliance-regulated environments

### Choose Direct In-Place Upgrade If:

✅ **Environment is non-production**
- Development clusters
- Staging environments
- Internal testing systems

✅ **Downtime is acceptable**
- After-hours maintenance window available
- Users can be notified and planned around
- No active usage during upgrade window

✅ **Cost optimization is priority**
- Budget-constrained projects
- POC/MVP environments
- Temporary or short-lived clusters

✅ **Simplicity is preferred**
- Fewer steps to manage
- Less complexity in execution
- Smaller team managing upgrade

**Example scenarios:**
- Development environments
- Non-critical staging systems
- Internal tools with flexible availability
- Cost-sensitive projects

### Risk Assessment Questions

Ask yourself:

1. **What is the business cost of 1 hour downtime?**
   - > $1,000: Choose Blue/Green
   - < $100: Direct upgrade acceptable

2. **Can you test before production impact?**
   - Must test first: Blue/Green
   - Can test in production: Direct upgrade

3. **How quickly must you rollback?**
   - < 1 minute: Blue/Green
   - 15-30 minutes acceptable: Direct upgrade

4. **What data can you afford to lose?**
   - None: Blue/Green
   - Last 30-60 minutes: Direct upgrade

5. **What is your team's comfort level?**
   - Prefer safety over simplicity: Blue/Green
   - Comfortable with risk: Direct upgrade

---

## Post-Upgrade Tasks

### Immediate (First 24 Hours)

**Both Approaches:**

1. **Monitor CloudWatch Metrics**
   ```bash
   # Key metrics to watch:
   - CPUUtilization
   - DatabaseConnections
   - ReadLatency / WriteLatency
   - FreeableMemory
   - ServerlessDatabaseCapacity (for Serverless v2)
   ```

2. **Check Application Logs**
   - Look for database connection errors
   - Monitor query performance changes
   - Check for unexpected behavior

3. **Verify Backups**
   ```bash
   aws rds describe-db-cluster-snapshots \
     --db-cluster-identifier your-cluster-name \
     --query 'DBClusterSnapshots[?SnapshotCreateTime>=`2024-01-01`]'
   ```

4. **Test Point-in-Time Recovery**
   - Verify PITR is working
   - Check backup retention settings

### Short-Term (First Week)

1. **Performance Baseline**
   - Compare query performance with v13
   - Document any performance changes
   - Optimize queries if needed

2. **Review PostgreSQL 16 Features**
   - Identify new features to leverage
   - Update application to use improvements
   - Review deprecated features

3. **Update Documentation**
   - Document upgrade process
   - Update runbooks
   - Share lessons learned

4. **Extension Updates**
   ```bash
   # Check for extension updates
   psql -c "SELECT extname, extversion FROM pg_extension;"
   
   # Update extensions if needed
   psql -c "ALTER EXTENSION pg_stat_statements UPDATE;"
   ```

### Long-Term (First Month)

1. **Cost Analysis**
   - Compare costs before/after upgrade
   - Optimize capacity if needed
   - Review CloudWatch metrics trends

2. **Compliance Verification**
   - Ensure audit logs are working
   - Verify encryption settings
   - Check access controls

3. **Disaster Recovery Test**
   - Test snapshot restore
   - Verify point-in-time recovery
   - Document RTO/RPO

---

## Troubleshooting

### Common Issues

#### Issue 1: Blue/Green Deployment Fails to Create

**Error:**
```
InvalidParameterCombination: Cannot use default parameter groups with Blue/Green deployments
```

**Root Cause:** You cannot use AWS default parameter groups (`default.aurora-postgresql13`, `default.aurora-postgresql16`, etc.) with Blue/Green deployments. AWS requires custom parameter groups.

**Solution:**
```bash
# Check if your current cluster is using a default parameter group
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].DBClusterParameterGroup'

# If it returns "default.aurora-postgresql13", you must:
# 1. Create custom v13 parameter group FIRST
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name your-cluster-pg13-custom \
  --db-parameter-group-family aurora-postgresql13 \
  --description "Custom v13 parameters"

# 2. Migrate current cluster to custom group (brief restart)
aws rds modify-db-cluster \
  --db-cluster-identifier your-cluster-name \
  --db-cluster-parameter-group-name your-cluster-pg13-custom \
  --apply-immediately

# 3. Wait for change to complete
aws rds wait db-cluster-available \
  --db-cluster-identifier your-cluster-name

# 4. Now create v16 custom parameter group
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name your-cluster-pg16-cluster \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom v16 parameters"

# 5. Proceed with Blue/Green deployment
```

**Prevention:** Always use custom parameter groups for production databases, not AWS defaults.

#### Issue 2: Minimum Capacity Error

**Error:**
```
InvalidParameterValue: Minimum capacity must be at least 1.0 for Blue/Green deployments
```

**Solution:**
```bash
# Scale up before creating Blue/Green
aws rds modify-db-cluster \
  --db-cluster-identifier your-cluster-name \
  --serverless-v2-scaling-configuration MinCapacity=1.0,MaxCapacity=4 \
  --apply-immediately
```

#### Issue 3: Terragrunt Apply Hangs

**Symptom:** `terragrunt apply` runs for hours without completing

**Solution:**
```bash
# Check cluster status in AWS Console
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].Status'

# If stuck, may need to manually complete in console
# Or contact AWS Support
```

#### Issue 4: Connection Errors After Upgrade

**Symptom:** Application cannot connect to database

**Solution:**
```bash
# 1. Verify cluster is available
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].[Status,Endpoint]'

# 2. Check security groups
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].VpcSecurityGroups'

# 3. Test connection from application server
psql "postgresql://user@endpoint:5432/db" -c "SELECT 1;"
```

#### Issue 5: Performance Degradation After Upgrade

**Symptom:** Queries slower on v16 than v13

**Solution:**
```sql
-- Update table statistics
ANALYZE;

-- Reindex if needed
REINDEX DATABASE your_database;

-- Check for missing indexes
SELECT schemaname, tablename 
FROM pg_tables 
WHERE schemaname NOT IN ('pg_catalog', 'information_schema');

-- Review query plans
EXPLAIN (ANALYZE, BUFFERS) SELECT ... ;
```

---

## Additional Resources

### AWS Documentation
- [Aurora PostgreSQL Upgrades](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_UpgradeDBInstance.PostgreSQL.html)
- [Blue/Green Deployments](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments.html)
- [Aurora Serverless v2](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)

### PostgreSQL Documentation
- [PostgreSQL 16 Release Notes](https://www.postgresql.org/docs/16/release-16.html)
- [PostgreSQL 15 Release Notes](https://www.postgresql.org/docs/15/release-15.html)
- [PostgreSQL 14 Release Notes](https://www.postgresql.org/docs/14/release-14.html)

### Internal Documentation
- Database Architecture Guide
- Disaster Recovery Procedures
- On-Call Runbooks
- Change Management Process

---

## Approval and Sign-off

### Before Proceeding

Ensure you have:
- [ ] Reviewed this document thoroughly
- [ ] Chosen appropriate upgrade method
- [ ] Scheduled maintenance window (if needed)
- [ ] Notified all stakeholders
- [ ] Prepared rollback plan
- [ ] Assigned team members for monitoring
- [ ] Documented expected behavior
- [ ] Backed up critical data

### Recommended Approvals

**For Production Blue/Green Deployment:**
- [ ] Database Administrator
- [ ] Platform Engineering Lead
- [ ] Application Team Lead
- [ ] Operations Manager
- [ ] Change Advisory Board (if applicable)

**For Dev/Test Direct Upgrade:**
- [ ] Team Lead
- [ ] Application Owner

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Oct 2025 | Platform Team | Initial version covering both upgrade approaches |

---

## Questions or Issues?

**Contact:** platform-engineering@yourcompany.com  
**Slack:** #database-support  
**On-Call:** PagerDuty escalation "Database Team"

**For urgent issues during upgrade:**
1. Stop the upgrade process
2. Notify on-call team immediately
3. Document current state
4. Initiate rollback if necessary

