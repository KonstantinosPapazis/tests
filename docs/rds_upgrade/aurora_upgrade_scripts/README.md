# Aurora PostgreSQL 13.20 → 16.9 Upgrade Scripts

This directory contains scripts and tools to help you safely upgrade Aurora PostgreSQL from version 13.20 to 16.9.

## 📁 Files in This Directory

| File | Purpose | When to Use |
|------|---------|-------------|
| `upgrade_production.sh` | Main upgrade script using Blue/Green deployment | Production upgrade |
| `rollback_procedure.sh` | Rollback script with multiple recovery methods | If upgrade fails |
| `pre_upgrade_validation.sql` | SQL script to inventory and validate database | Before upgrade |
| `post_upgrade_validation.sql` | SQL script to verify upgrade success | After upgrade |

## 🚀 Quick Start

### Prerequisites

1. **AWS CLI installed and configured**
   ```bash
   aws --version
   aws sts get-caller-identity
   ```

2. **PostgreSQL client (psql) installed**
   ```bash
   psql --version
   ```

3. **Proper IAM permissions**
   - RDS: `DescribeDBClusters`, `ModifyDBCluster`, `CreateDBClusterSnapshot`
   - RDS: `CreateBlueGreenDeployment`, `SwitchoverBlueGreenDeployment`
   - CloudWatch: `GetMetricStatistics`

4. **Parameter group for PostgreSQL 16**
   ```bash
   aws rds create-db-cluster-parameter-group \
     --db-cluster-parameter-group-name aurora-postgresql16-params \
     --db-parameter-group-family aurora-postgresql16 \
     --description "Parameter group for PostgreSQL 16"
   ```

### Step-by-Step Upgrade Process

#### Step 1: Pre-Upgrade Validation (1-2 days before)

Run the pre-upgrade validation SQL script:

```bash
# Connect to your database
psql -h your-cluster.cluster-xxxxx.region.rds.amazonaws.com \
     -U your_username \
     -d your_database \
     -f pre_upgrade_validation.sql
```

This creates `pre_upgrade_validation_report.txt`. Review it for:
- ❌ Python 2 PL/Python functions
- ❌ Tables with OIDs
- ❌ Deprecated data types
- ⚠️ Extensions that may need updates

#### Step 2: Customize the Upgrade Script

Edit `upgrade_production.sh` and set your values:

```bash
export AWS_REGION="us-east-1"                    # Your AWS region
export AWS_ACCOUNT_ID="123456789012"             # Your AWS account ID
export CLUSTER_NAME="your-prod-cluster-name"     # Your cluster name
export PG16_PARAMETER_GROUP="aurora-postgresql16-params"  # Your PG16 param group
export INSTANCE_CLASS="db.r6g.xlarge"           # Your instance class
```

Optional: Add Slack/PagerDuty webhooks for notifications.

#### Step 3: Make Scripts Executable

```bash
chmod +x upgrade_production.sh
chmod +x rollback_procedure.sh
```

#### Step 4: Run the Upgrade

```bash
./upgrade_production.sh
```

The script will:
1. ✅ Check prerequisites
2. 📸 Create pre-upgrade snapshot
3. 📊 Capture baseline metrics
4. 🟢 Create Blue/Green deployment
5. ⏳ Wait for Green environment
6. 🧪 Prompt you to validate
7. 🔄 Perform switchover (brief downtime)
8. ✅ Verify success

**Expected Timeline:**
- Green environment creation: 15-30 minutes
- Validation: 15-30 minutes (your testing)
- Switchover: 2-5 minutes (downtime)
- **Total: ~45-60 minutes**

#### Step 5: Post-Upgrade Validation

Immediately after upgrade:

```bash
# Connect to your database
psql -h your-cluster.cluster-xxxxx.region.rds.amazonaws.com \
     -U your_username \
     -d your_database \
     -f post_upgrade_validation.sql
```

Then run:

```sql
-- Update table statistics
ANALYZE VERBOSE;

-- Update extensions
\dx
ALTER EXTENSION pg_stat_statements UPDATE;
-- Repeat for other extensions
```

## 🔄 Rollback Procedures

If you need to rollback, use the rollback script:

```bash
./rollback_procedure.sh
```

The script offers three methods:

### Method 1: Blue/Green Switchback (Fastest)
- **Time:** 2-5 minutes
- **Data Loss:** Changes made during PG 16 runtime
- **When:** Within 24-48 hours of upgrade
- **Requirement:** Blue/Green deployment still exists

### Method 2: Snapshot Restore
- **Time:** 15-30 minutes
- **Data Loss:** Changes since snapshot
- **When:** If Blue/Green not available
- **Requirement:** Pre-upgrade snapshot exists

### Method 3: Point-in-Time Recovery
- **Time:** 20-45 minutes
- **Data Loss:** Changes since restore point
- **When:** Need specific restore time
- **Requirement:** PITR enabled

## 📋 Validation Scripts Details

### Pre-Upgrade Validation SQL Script

Generates a comprehensive report including:
- Current PostgreSQL version
- All databases, schemas, and extensions
- Function and procedure inventory
- Trigger definitions
- Compatibility checks (Python 2, OIDs, deprecated types)
- Index and constraint inventory
- Table statistics
- Performance baseline metrics

**Output:** `pre_upgrade_validation_report.txt`

### Post-Upgrade Validation SQL Script

Verifies upgrade success:
- Confirms PostgreSQL 16.9 version
- Checks all extensions loaded
- Compares object counts with pre-upgrade
- Identifies objects needing ANALYZE
- Tests sample queries
- Validates connections and performance

**Output:** `post_upgrade_validation_report.txt`

## 🛠️ Customization Guide

### Adding Custom Validations

Edit the SQL scripts to add your specific checks:

```sql
-- Add to pre_upgrade_validation.sql
\echo ''
\echo 'Custom Check: My Application Tables'
SELECT 
    table_name,
    pg_size_pretty(pg_total_relation_size(table_name)) as size
FROM information_schema.tables
WHERE table_schema = 'my_app_schema'
ORDER BY pg_total_relation_size(table_name) DESC;
```

### Adding Notifications

In `upgrade_production.sh`, configure:

```bash
# Slack
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# PagerDuty
export PAGERDUTY_KEY="your_pagerduty_integration_key"
```

The script will automatically send notifications at key points.

### Adjusting Timeouts

Modify wait times in the upgrade script:

```bash
# In wait_for_green() function
local max_wait=3600  # Increase from 1 hour if needed

# In wait_for_switchover() function
local max_wait=600   # Increase from 10 minutes if needed
```

## 🔍 Troubleshooting

### Issue: "Blue/Green deployment failed"

**Possible causes:**
- Insufficient capacity in the region
- Parameter group misconfiguration
- Backup in progress

**Solution:**
```bash
# Check deployment details
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier YOUR_DEPLOYMENT_ID

# Check current cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier YOUR_CLUSTER_NAME
```

### Issue: Extensions fail to load after upgrade

**Solution:**
```sql
-- Check extension availability
SELECT * FROM pg_available_extensions 
WHERE name = 'your_extension';

-- Update extension
ALTER EXTENSION your_extension UPDATE;

-- If not available, check Aurora documentation
-- Some extensions may need different versions for PG 16
```

### Issue: Query performance degraded

**Solution:**
```sql
-- Update statistics
ANALYZE VERBOSE;

-- Check query plans
EXPLAIN (ANALYZE, BUFFERS) your_slow_query;

-- Adjust parallel workers if needed
ALTER DATABASE your_db SET max_parallel_workers_per_gather = 4;
```

### Issue: Connection pool exhausted

**Solution:**
```sql
-- Check current connections
SELECT COUNT(*), state FROM pg_stat_activity GROUP BY state;

-- Identify idle connections
SELECT pid, usename, application_name, state, state_change
FROM pg_stat_activity
WHERE state = 'idle'
  AND NOW() - state_change > INTERVAL '5 minutes';

-- Adjust timeout
ALTER DATABASE your_db SET idle_in_transaction_session_timeout = '5min';
```

## 📊 Monitoring After Upgrade

### CloudWatch Metrics to Watch

```bash
# Database Connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=YOUR_CLUSTER \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# CPU Utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=YOUR_CLUSTER \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# Read/Write Latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReadLatency \
  --dimensions Name=DBClusterIdentifier,Value=YOUR_CLUSTER \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

### Database Health Checks

```sql
-- Every 15 minutes for first 2 hours
SELECT 
    NOW() as check_time,
    COUNT(*) as connection_count,
    COUNT(*) FILTER (WHERE state = 'active') as active_queries,
    COUNT(*) FILTER (WHERE state = 'idle in transaction') as idle_in_transaction
FROM pg_stat_activity
WHERE pid != pg_backend_pid();

-- Check for slow queries
SELECT 
    pid,
    NOW() - query_start as duration,
    state,
    LEFT(query, 100) as query
FROM pg_stat_activity
WHERE state != 'idle'
  AND NOW() - query_start > INTERVAL '30 seconds'
  AND pid != pg_backend_pid()
ORDER BY duration DESC;
```

## 📝 Post-Upgrade Cleanup

After 24-48 hours of stable operation:

### Delete Blue/Green Deployment

```bash
# Delete the old Blue environment
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier YOUR_DEPLOYMENT_ID \
  --delete-target
```

### Delete Old Snapshots (Optional)

```bash
# List old snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier YOUR_CLUSTER \
  --snapshot-type manual

# Delete if no longer needed
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier SNAPSHOT_ID
```

### Archive Logs and Reports

```bash
# Create archive directory
mkdir upgrade_archive_$(date +%Y%m%d)

# Move all logs and reports
mv *.log *.txt *.json upgrade_archive_$(date +%Y%m%d)/

# Compress
tar -czf upgrade_archive_$(date +%Y%m%d).tar.gz upgrade_archive_$(date +%Y%m%d)/
```

## 🆘 Emergency Contacts Template

Add your team's contact information:

```bash
# In upgrade_production.sh, add:
echo "=========================================="
echo "EMERGENCY CONTACTS"
echo "=========================================="
echo "On-Call Engineer: [Name] [Phone/Slack]"
echo "Database Lead: [Name] [Phone/Slack]"
echo "Escalation: [Manager] [Phone/Slack]"
echo "War Room: [Slack/Teams Channel]"
echo "=========================================="
```

## 📚 Additional Resources

- [Main Upgrade Guide](../AURORA_POSTGRESQL_13_TO_16_UPGRADE_GUIDE.md)
- [Quick Checklist](../aurora_upgrade_quick_checklist.md)
- [AWS Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- [PostgreSQL 16 Release Notes](https://www.postgresql.org/docs/16/release-16.html)

## 📄 License and Support

These scripts are provided as-is for reference. Test thoroughly in your environment before using in production.

For questions or issues:
- Review the main upgrade guide
- Check AWS documentation
- Contact your database team

---

**Last Updated:** October 27, 2025  
**Version:** 1.0

