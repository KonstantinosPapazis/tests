# Aurora PostgreSQL 13.20 to 16.9 Upgrade Guide

**Document Version:** 1.0  
**Last Updated:** October 27, 2025  
**Upgrade Path:** Aurora PostgreSQL 13.20 → 16.9  

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Breaking Changes Overview](#breaking-changes-overview)
3. [Pre-Upgrade Assessment](#pre-upgrade-assessment)
4. [Testing Strategy](#testing-strategy)
5. [Step-by-Step Upgrade Process](#step-by-step-upgrade-process)
6. [Rollback Procedures](#rollback-procedures)
7. [Post-Upgrade Validation](#post-upgrade-validation)
8. [Communication Templates](#communication-templates)
9. [Additional Resources](#additional-resources)

---

## Executive Summary

This guide provides a comprehensive, risk-mitigated approach to upgrading Aurora PostgreSQL from version 13.20 to 16.9. This is a **major version upgrade** spanning three PostgreSQL major versions (14, 15, and 16), which requires careful planning and testing.

### Key Facts

- **Upgrade Type:** Major version upgrade (3 versions jump)
- **Expected Downtime:** 15-45 minutes (varies by database size and configuration)
- **Risk Level:** Medium-High (requires thorough testing)
- **Recommended Approach:** Blue/Green Deployment
- **Rollback Strategy:** Snapshot restoration or Blue/Green switchback

---

## Breaking Changes Overview

### PostgreSQL 14 Breaking Changes

#### 1. **Removed Features**
- **Python 2 support in PL/Python removed** - Upgrade to Python 3
  - Impact: Any PL/Python functions using Python 2 will fail
  - Action: Rewrite functions using Python 3 syntax

#### 2. **Behavioral Changes**
- **Changes to `to_timestamp()` and `to_date()` functions**
  - More strict input validation
  - May reject previously accepted invalid dates
  
- **Modified system catalog columns**
  - Some `pg_stat_*` views have new columns
  - Old queries may need adjustment

- **Permission changes**
  - `EXECUTE` privilege now required for trigger functions
  
#### 3. **Performance Changes**
- Query planner improvements may change execution plans
- Some queries may perform differently (better or worse)

**Documentation:** [PostgreSQL 14 Release Notes](https://www.postgresql.org/docs/14/release-14.html)

---

### PostgreSQL 15 Breaking Changes

#### 1. **Removed Features**
- **Exclusive backup mode removed**
  - `pg_start_backup()`/`pg_stop_backup()` exclusive mode deprecated
  - Impact: Custom backup scripts may fail
  - Action: Use non-exclusive backup mode or AWS snapshots

#### 2. **Security Changes**
- **PUBLIC schema permissions revoked by default**
  - Users no longer have CREATE privileges on public schema by default
  - Impact: Applications creating temp objects may fail
  - Action: Explicitly grant necessary permissions
  
```sql
-- If needed, restore old behavior:
GRANT CREATE ON SCHEMA public TO PUBLIC;
```

#### 3. **UNIQUE and PRIMARY KEY Changes**
- Multiple NULL values now handled differently in UNIQUE constraints
- May affect existing constraint behavior

#### 4. **Regular Expression Changes**
- More strict regex parsing
- Some previously accepted patterns may fail

**Documentation:** [PostgreSQL 15 Release Notes](https://www.postgresql.org/docs/15/release-15.html)

---

### PostgreSQL 16 Breaking Changes

#### 1. **Changes to System Functions**
- Various system catalog functions renamed or modified
- Impact: Monitoring queries using old function names will fail
  
#### 2. **Query Planner Changes**
- Significant improvements to parallel query execution
- Hash join improvements
- May change query execution plans

#### 3. **Security Enhancements**
- Additional security restrictions on certain operations
- SCRAM authentication improvements

#### 4. **Extension Changes**
- Some extensions may need updates
- Check compatibility: PostGIS, pg_cron, pgaudit, etc.

**Documentation:** [PostgreSQL 16 Release Notes](https://www.postgresql.org/docs/16/release-16.html)

---

## Pre-Upgrade Assessment

### Phase 1: Environment Discovery

#### 1.1 Document Current State

```bash
# Get cluster information
aws rds describe-db-clusters \
  --db-cluster-identifier YOUR_CLUSTER_NAME \
  --query 'DBClusters[0].[EngineVersion,DBClusterParameterGroup,Engine,DatabaseName]' \
  --output table

# List all instances in the cluster
aws rds describe-db-cluster-members \
  --db-cluster-identifier YOUR_CLUSTER_NAME \
  --output table

# Get current parameter group settings
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name YOUR_PARAM_GROUP \
  --output json > current_parameters.json
```

#### 1.2 Verify Upgrade Path

```bash
# Check valid upgrade targets from 13.20
aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --engine-version 13.20 \
  --query 'DBEngineVersions[*].ValidUpgradeTarget[*].{EngineVersion:EngineVersion,Description:Description}' \
  --output table
```

Expected output should include version 16.9.

#### 1.3 Inventory Database Objects

Connect to your database and run:

```sql
-- Save this output for comparison after upgrade
\o pre_upgrade_inventory.txt

-- 1. List all databases
\l

-- 2. List all schemas
SELECT nspname FROM pg_namespace 
WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema'
ORDER BY nspname;

-- 3. List all extensions and versions
SELECT extname, extversion 
FROM pg_extension 
ORDER BY extname;

-- 4. Count all database objects by type
SELECT 
    n.nspname as schema_name,
    c.relkind as object_type,
    COUNT(*) as count
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
GROUP BY n.nspname, c.relkind
ORDER BY n.nspname, c.relkind;

-- 5. List all stored procedures/functions
SELECT 
    n.nspname as schema_name,
    p.proname as function_name,
    pg_get_function_identity_arguments(p.oid) as arguments,
    l.lanname as language
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname;

-- 6. List all triggers
SELECT 
    n.nspname as schema_name,
    c.relname as table_name,
    t.tgname as trigger_name,
    pg_get_triggerdef(t.oid) as definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND NOT t.tgisinternal
ORDER BY n.nspname, c.relname, t.tgname;

\o
```

### Phase 2: Compatibility Analysis

#### 2.1 Check for Deprecated Features

```sql
-- Check for tables still using OID
SELECT 
    n.nspname,
    c.relname 
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE c.relhasoids 
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');

-- Check for Python 2 functions (if using PL/Python)
SELECT 
    n.nspname,
    p.proname,
    p.prosrc
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
JOIN pg_language l ON p.prolang = l.oid
WHERE l.lanname = 'plpythonu'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');

-- Check for deprecated pg_stat_activity columns usage
-- (Review your monitoring queries)
SELECT 
    pid,
    datname,
    usename,
    application_name,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle'
LIMIT 5;
```

#### 2.2 Extension Compatibility Check

```sql
-- List all extensions with available versions
SELECT 
    e.extname,
    e.extversion as current_version,
    av.version as available_version
FROM pg_extension e
CROSS JOIN LATERAL (
    SELECT version 
    FROM pg_available_extension_versions 
    WHERE name = e.extname 
    ORDER BY version DESC 
    LIMIT 1
) av
ORDER BY e.extname;
```

**Common Extensions to Verify:**
- `pg_stat_statements` - Usually auto-upgraded
- `postgis` - Check compatibility with PG 16
- `pg_trgm` - Should be compatible
- `uuid-ossp` - Should be compatible
- `pgaudit` - Verify version compatibility
- `pg_cron` - Check Aurora compatibility with PG 16

#### 2.3 Application Driver Compatibility

Check your application's PostgreSQL driver versions:

| Language | Driver | Minimum Version for PG 16 |
|----------|--------|---------------------------|
| **Python** | psycopg2 | 2.9+ |
| **Python** | psycopg3 | 3.0+ |
| **Java** | PostgreSQL JDBC | 42.5.0+ |
| **Node.js** | pg | 8.8.0+ |
| **Ruby** | pg gem | 1.4.0+ |
| **.NET** | Npgsql | 7.0+ |
| **Go** | pgx | 5.0+ |
| **PHP** | PDO_PGSQL | PHP 8.0+ |

### Phase 3: Create Pre-Upgrade Checklist

Create this checklist document and share with stakeholders:

```markdown
# Pre-Upgrade Checklist for [DATABASE_NAME]

## Database Owner Information
- **Owner:** [Name/Team]
- **Contact:** [Email/Slack]
- **Application(s):** [List applications using this database]
- **Business Criticality:** [High/Medium/Low]

## Technical Review
- [ ] Current version confirmed: 13.20
- [ ] All extensions inventoried
- [ ] All stored procedures reviewed
- [ ] Custom functions analyzed
- [ ] Triggers documented
- [ ] Monitoring queries tested
- [ ] Backup scripts verified
- [ ] Application driver versions confirmed compatible

## Breaking Changes Impact Assessment
- [ ] No Python 2 PL/Python functions in use
- [ ] No exclusive backup mode scripts
- [ ] PUBLIC schema permissions requirements identified
- [ ] Regular expressions in queries validated
- [ ] System catalog query dependencies reviewed

## Application Compatibility
- [ ] Database drivers updated to compatible versions
- [ ] ORM compatibility verified (if applicable)
- [ ] Connection pooling configuration reviewed
- [ ] Query timeouts and retry logic verified
- [ ] Custom SQL queries reviewed for compatibility

## Testing Plan
- [ ] Test environment created
- [ ] Test data populated
- [ ] Application test suite prepared
- [ ] Performance benchmark baseline captured
- [ ] Rollback procedure documented

## Sign-off
- [ ] Database Owner approved
- [ ] Application Owner approved
- [ ] DevOps/SRE approved
```

---

## Testing Strategy

### Approach 1: Blue/Green Deployment (Recommended)

Blue/Green deployments provide the safest upgrade path with minimal risk.

#### Advantages
- ✅ Zero data loss risk
- ✅ Quick rollback (just switch back)
- ✅ Test with live production data
- ✅ Minimal downtime
- ✅ Side-by-side comparison

#### Step-by-Step Blue/Green Testing

**Step 1: Create Blue/Green Deployment**

```bash
# Create the blue/green deployment
aws rds create-blue-green-deployment \
  --blue-green-deployment-name "${CLUSTER_NAME}-pg16-upgrade-test" \
  --source-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster:${CLUSTER_NAME}" \
  --target-engine-version "16.9" \
  --target-db-parameter-group-name "${PG16_PARAMETER_GROUP}" \
  --tags Key=Purpose,Value=MajorVersionUpgrade Key=Version,Value=16.9

# Check deployment status
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --query 'BlueGreenDeployments[0].[Status,SourceArn,TargetArn]' \
  --output table
```

**Step 2: Wait for Green Environment to be Available**

```bash
# Monitor the green environment creation
aws rds wait db-cluster-available \
  --db-cluster-identifier "${GREEN_CLUSTER_NAME}"
```

**Step 3: Test the Green Environment**

```bash
# Get the green cluster endpoint
GREEN_ENDPOINT=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --query 'BlueGreenDeployments[0].Target' \
  --output text)

echo "Green environment endpoint: ${GREEN_ENDPOINT}"
```

**Step 4: Run Test Suite Against Green Environment**

```bash
# Update your application config to point to green endpoint
export DATABASE_HOST=${GREEN_ENDPOINT}

# Run your test suite
# Example for different frameworks:

# Python/pytest
pytest tests/ --db-host=${GREEN_ENDPOINT}

# Node.js/Jest
DATABASE_URL=postgresql://user:pass@${GREEN_ENDPOINT}/dbname npm test

# Ruby/RSpec
DATABASE_URL=postgresql://user:pass@${GREEN_ENDPOINT}/dbname bundle exec rspec

# Java/Maven
mvn test -Ddb.url=jdbc:postgresql://${GREEN_ENDPOINT}/dbname
```

**Step 5: Performance Testing**

```sql
-- Connect to green environment
-- Run your most critical queries and compare EXPLAIN plans

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT ... ; -- Your critical query

-- Compare with production (blue) results
```

**Step 6: Decision Point**

If tests pass:
```bash
# Promote green to production (switchover)
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --switchover-timeout 300
```

If tests fail:
```bash
# Delete green environment and investigate
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --delete-target
```

### Approach 2: Snapshot Restore Testing

If Blue/Green is not available or preferred:

**Step 1: Create Snapshot**

```bash
# Create manual snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-pre-upgrade-test-$(date +%Y%m%d-%H%M)" \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --tags Key=Purpose,Value=UpgradeTesting

# Wait for snapshot to complete
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${SNAPSHOT_ID}"
```

**Step 2: Restore to Test Cluster**

```bash
# Restore snapshot to new cluster
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier "${CLUSTER_NAME}-test-pg16" \
  --snapshot-identifier "${SNAPSHOT_ID}" \
  --engine aurora-postgresql \
  --engine-version 16.9 \
  --db-cluster-parameter-group-name "${PG16_PARAMETER_GROUP}" \
  --vpc-security-group-ids "${SECURITY_GROUP_IDS}" \
  --db-subnet-group-name "${SUBNET_GROUP}" \
  --tags Key=Environment,Value=Test Key=Purpose,Value=UpgradeTesting

# Create instances in the cluster
aws rds create-db-instance \
  --db-instance-identifier "${CLUSTER_NAME}-test-pg16-instance-1" \
  --db-cluster-identifier "${CLUSTER_NAME}-test-pg16" \
  --engine aurora-postgresql \
  --db-instance-class "${INSTANCE_CLASS}"
```

**Step 3: Test**

Follow the same testing procedure as Blue/Green approach.

**Step 4: Cleanup**

```bash
# Delete test cluster after testing
aws rds delete-db-cluster \
  --db-cluster-identifier "${CLUSTER_NAME}-test-pg16" \
  --skip-final-snapshot
```

### Test Cases to Execute

Create a comprehensive test plan:

```markdown
# Test Plan for PostgreSQL 16.9 Upgrade

## 1. Connection Tests
- [ ] Application can connect to database
- [ ] Connection pooling works correctly
- [ ] SSL/TLS connections work
- [ ] All application users can authenticate

## 2. Functional Tests
- [ ] All CRUD operations work
- [ ] Stored procedures execute successfully
- [ ] Triggers fire correctly
- [ ] Foreign key constraints work
- [ ] Check constraints validate properly

## 3. Data Integrity Tests
- [ ] Row counts match between blue and green
- [ ] Random sample data comparison
- [ ] Checksum validation of critical tables

## 4. Performance Tests
- [ ] Run top 10 slowest queries
- [ ] Compare execution plans
- [ ] Measure query response times
- [ ] Check connection pool performance
- [ ] Monitor resource utilization

## 5. Extension Tests
- [ ] All extensions load correctly
- [ ] Extension functions work
- [ ] PostGIS queries (if applicable)
- [ ] Full-text search (if applicable)

## 6. Backup/Restore Tests
- [ ] Snapshot creation works
- [ ] Point-in-time recovery tested
- [ ] Backup retention working

## 7. Monitoring Tests
- [ ] CloudWatch metrics available
- [ ] Performance Insights working
- [ ] Custom monitoring queries work
- [ ] Alerting thresholds appropriate

## 8. Integration Tests
- [ ] All dependent applications tested
- [ ] API endpoints functional
- [ ] Batch jobs successful
- [ ] Reporting queries work
```

---

## Step-by-Step Upgrade Process

### Pre-Production Upgrade Checklist

Complete these items before starting the production upgrade:

```markdown
## T-Minus Checklist

### 1 Week Before
- [ ] All testing completed successfully
- [ ] Stakeholders notified of upgrade window
- [ ] Rollback plan documented and reviewed
- [ ] Backup retention period extended
- [ ] On-call schedule confirmed
- [ ] Communication plan finalized

### 24 Hours Before
- [ ] Final snapshot taken
- [ ] Snapshot retention locked
- [ ] Database performance baseline captured
- [ ] Application owners confirmed readiness
- [ ] Rollback scripts tested
- [ ] Maintenance window notification sent

### 4 Hours Before
- [ ] Verify no major alerts or incidents
- [ ] Confirm all team members available
- [ ] Pre-upgrade meeting completed
- [ ] Communication channels tested (Slack, PagerDuty, etc.)
- [ ] Rollback decision criteria defined

### 1 Hour Before
- [ ] Final system health check
- [ ] Verify backup completion
- [ ] Stage all scripts and commands
- [ ] Open incident bridge/war room
- [ ] Send "maintenance starting" notification
```

### Production Upgrade Procedure

#### Option 1: Blue/Green Deployment (Recommended for Production)

**Timeline:** ~2-3 hours total (mostly testing)

```bash
#!/bin/bash
# Production Aurora PostgreSQL Upgrade Script
# Version 13.20 -> 16.9

set -e
set -o pipefail

# Configuration
export CLUSTER_NAME="your-prod-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"
export PG16_PARAMETER_GROUP="aurora-postgresql16-params"
export TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Step 1: Create final pre-upgrade snapshot
echo "Step 1: Creating final pre-upgrade snapshot..."
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}" \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --tags Key=UpgradeFrom,Value=13.20 Key=UpgradeTo,Value=16.9 Key=Timestamp,Value=${TIMESTAMP}

# Wait for snapshot
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"

echo "✓ Snapshot created: ${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"

# Step 2: Capture pre-upgrade metrics
echo "Step 2: Capturing pre-upgrade metrics..."
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=${CLUSTER_NAME} \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum \
  > pre_upgrade_connections_${TIMESTAMP}.json

# Step 3: Create Blue/Green deployment
echo "Step 3: Creating Blue/Green deployment..."
DEPLOYMENT_ID=$(aws rds create-blue-green-deployment \
  --blue-green-deployment-name "${CLUSTER_NAME}-pg16-production" \
  --source-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster:${CLUSTER_NAME}" \
  --target-engine-version "16.9" \
  --target-db-parameter-group-name "${PG16_PARAMETER_GROUP}" \
  --tags Key=Environment,Value=Production Key=Upgrade,Value=13-to-16 \
  --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
  --output text)

echo "✓ Blue/Green deployment created: ${DEPLOYMENT_ID}"

# Step 4: Monitor deployment creation
echo "Step 4: Waiting for Green environment to be ready (this may take 15-30 minutes)..."
while true; do
  STATUS=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --query 'BlueGreenDeployments[0].Status' \
    --output text)
  
  echo "Current status: ${STATUS}"
  
  if [ "$STATUS" == "AVAILABLE" ]; then
    echo "✓ Green environment is ready!"
    break
  elif [ "$STATUS" == "FAILED" ]; then
    echo "✗ Deployment failed!"
    exit 1
  fi
  
  sleep 60
done

# Step 5: Get Green endpoint
GREEN_ENDPOINT=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --query 'BlueGreenDeployments[0].Target' \
  --output text)

echo "✓ Green endpoint: ${GREEN_ENDPOINT}"

# Step 6: Validation pause
echo ""
echo "=========================================="
echo "GREEN ENVIRONMENT IS READY FOR VALIDATION"
echo "=========================================="
echo ""
echo "Green Endpoint: ${GREEN_ENDPOINT}"
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo ""
echo "Please perform the following validations:"
echo "1. Run smoke tests against green endpoint"
echo "2. Verify all extensions loaded"
echo "3. Check sample queries"
echo "4. Validate application connectivity"
echo ""
read -p "Type 'PROCEED' to continue with switchover, or 'ABORT' to rollback: " DECISION

if [ "$DECISION" != "PROCEED" ]; then
  echo "Aborting upgrade and cleaning up..."
  aws rds delete-blue-green-deployment \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --delete-target
  echo "✓ Rolled back. Blue environment unchanged."
  exit 1
fi

# Step 7: Perform switchover
echo "Step 7: Performing switchover (this will cause brief downtime)..."
echo "⚠️  Starting switchover in 10 seconds... Press Ctrl+C to abort."
sleep 10

aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --switchover-timeout 300

# Step 8: Monitor switchover
echo "Step 8: Monitoring switchover..."
while true; do
  STATUS=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --query 'BlueGreenDeployments[0].Status' \
    --output text)
  
  echo "Switchover status: ${STATUS}"
  
  if [ "$STATUS" == "SWITCHOVER_COMPLETED" ]; then
    echo "✓ Switchover completed successfully!"
    break
  elif [ "$STATUS" == "SWITCHOVER_FAILED" ]; then
    echo "✗ Switchover failed!"
    exit 1
  fi
  
  sleep 30
done

# Step 9: Verify new version
echo "Step 9: Verifying upgrade..."
NEW_VERSION=$(aws rds describe-db-clusters \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --query 'DBClusters[0].EngineVersion' \
  --output text)

echo "✓ Cluster is now running version: ${NEW_VERSION}"

# Step 10: Post-upgrade checks
echo "Step 10: Running post-upgrade checks..."
echo "Please monitor the following for the next 1-2 hours:"
echo "  - Application error rates"
echo "  - Database connection counts"
echo "  - Query performance"
echo "  - CloudWatch alarms"
echo ""
echo "The old Blue environment will be retained for 24 hours for emergency rollback."
echo "To delete it after validation:"
echo "  aws rds delete-blue-green-deployment --blue-green-deployment-identifier ${DEPLOYMENT_ID} --delete-target"
echo ""
echo "=========================================="
echo "UPGRADE COMPLETED SUCCESSFULLY!"
echo "=========================================="
```

Save this script as `upgrade_aurora_pg_13_to_16.sh` and make it executable:
```bash
chmod +x upgrade_aurora_pg_13_to_16.sh
```

#### Option 2: Direct In-Place Upgrade

⚠️ **Warning:** This approach has more downtime and higher risk. Use Blue/Green when possible.

```bash
#!/bin/bash
# Direct in-place upgrade (higher risk)

set -e

export CLUSTER_NAME="your-prod-cluster"
export TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Step 1: Final snapshot
echo "Creating pre-upgrade snapshot..."
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}" \
  --db-cluster-identifier "${CLUSTER_NAME}"

aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"

# Step 2: Perform upgrade
echo "Starting upgrade (this will cause downtime)..."
aws rds modify-db-cluster \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --engine-version "16.9" \
  --db-cluster-parameter-group-name "aurora-postgresql16-params" \
  --apply-immediately \
  --allow-major-version-upgrade

# Step 3: Wait for upgrade to complete
echo "Waiting for upgrade to complete (this may take 30-60 minutes)..."
aws rds wait db-cluster-available \
  --db-cluster-identifier "${CLUSTER_NAME}"

echo "Upgrade completed!"
```

---

## Rollback Procedures

### Scenario 1: Rollback During Blue/Green Testing

If issues are found before switchover:

```bash
# Simply delete the green environment
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --delete-target

# Your production (blue) environment remains unchanged
```

**Rollback Time:** Immediate (no changes to production)  
**Data Loss:** None

### Scenario 2: Rollback After Blue/Green Switchover

If issues are found after switchover but within retention period:

```bash
# Switch back to the old environment (now the green)
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --switchover-timeout 300
```

**Rollback Time:** 2-5 minutes  
**Data Loss:** Changes made during PG 16 runtime will be lost

### Scenario 3: Restore from Snapshot

If Blue/Green is no longer available:

```bash
# 1. Note current endpoint name
ORIGINAL_ENDPOINT="${CLUSTER_NAME}.cluster-xxxxx.${AWS_REGION}.rds.amazonaws.com"

# 2. Rename current cluster
aws rds modify-db-cluster-identifier \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --new-db-cluster-identifier "${CLUSTER_NAME}-pg16-failed" \
  --apply-immediately

# 3. Restore from snapshot with original name
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --snapshot-identifier "${SNAPSHOT_ID}" \
  --engine aurora-postgresql \
  --engine-version "13.20"

# 4. Create instances
aws rds create-db-instance \
  --db-instance-identifier "${CLUSTER_NAME}-instance-1" \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --engine aurora-postgresql \
  --db-instance-class "${INSTANCE_CLASS}"

# 5. Wait for availability
aws rds wait db-cluster-available \
  --db-cluster-identifier "${CLUSTER_NAME}"
```

**Rollback Time:** 15-30 minutes  
**Data Loss:** All changes since snapshot

### Rollback Decision Criteria

Make rollback decision if:

1. **Application Errors**
   - Error rate increase >10%
   - Critical functionality broken
   - Authentication failures

2. **Performance Degradation**
   - Query response time increase >50%
   - Connection pool exhaustion
   - CPU or memory saturation

3. **Data Integrity Issues**
   - Constraint violations
   - Unexpected NULL values
   - Data corruption detected

4. **Compatibility Issues**
   - Extension failures
   - Stored procedure errors
   - Trigger malfunction

**Decision Timeline:**
- First 1 hour: Monitor closely, prepare rollback
- 1-4 hours: Continued monitoring, fix minor issues
- 4-24 hours: Most critical period over, evaluate long-term
- After 24 hours: Rollback becomes increasingly complex

---

## Post-Upgrade Validation

### Immediate Validation (First 15 minutes)

```sql
-- Connect to upgraded database

-- 1. Verify version
SELECT version();
-- Expected: PostgreSQL 16.9

-- 2. Check all extensions loaded
SELECT extname, extversion 
FROM pg_extension 
ORDER BY extname;

-- 3. Verify database objects
SELECT 
    schemaname,
    COUNT(*) 
FROM pg_tables 
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname;

-- 4. Check for any errors in recent logs
SELECT * FROM pg_stat_database;

-- 5. Verify replication status (if applicable)
SELECT * FROM pg_stat_replication;

-- 6. Check for connection issues
SELECT 
    COUNT(*) as connection_count,
    state,
    wait_event_type
FROM pg_stat_activity
GROUP BY state, wait_event_type;
```

### Application Health Checks (First 30 minutes)

```bash
# 1. Test application endpoint
curl -f https://your-app.com/health || echo "Health check failed!"

# 2. Check application logs for database errors
tail -f /var/log/application.log | grep -i "database\|postgres\|connection"

# 3. Monitor error rates
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name HTTPCode_Target_5XX_Count \
  --dimensions Name=LoadBalancer,Value=app/your-lb/xxxxx \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# 4. Check database connection pool
# (varies by application framework)
```

### Performance Validation (First 2 hours)

```sql
-- 1. Update table statistics
ANALYZE VERBOSE;

-- 2. Check for missing indexes
SELECT 
    schemaname,
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan,
    seq_tup_read / seq_scan AS avg_seq_tup
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC
LIMIT 20;

-- 3. Identify slow queries
SELECT 
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    max_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;

-- 4. Check for bloat
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
```

### Extended Monitoring (First 24-48 hours)

**CloudWatch Metrics to Monitor:**

```bash
# Database connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=${CLUSTER_NAME} \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# CPU Utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=${CLUSTER_NAME} \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum

# Read/Write Latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ReadLatency \
  --dimensions Name=DBClusterIdentifier,Value=${CLUSTER_NAME} \
  --start-time $(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

**Create CloudWatch Dashboard:**

```bash
# Create a dashboard for monitoring
aws cloudwatch put-dashboard \
  --dashboard-name "Aurora-PG16-Upgrade-Monitor" \
  --dashboard-body file://dashboard_config.json
```

Example `dashboard_config.json`:
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/RDS", "DatabaseConnections", {"stat": "Average"}],
          ["...", {"stat": "Maximum"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Database Connections",
        "yAxis": {
          "left": {
            "min": 0
          }
        }
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/RDS", "CPUUtilization"],
          [".", "FreeableMemory"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Resource Utilization"
      }
    }
  ]
}
```

### Post-Upgrade Maintenance

```sql
-- 1. Update all extensions to latest compatible versions
ALTER EXTENSION pg_stat_statements UPDATE;
-- Repeat for each extension

-- 2. Reindex if recommended
-- (Only if you notice performance issues)
REINDEX DATABASE your_database;

-- 3. Vacuum analyze all tables
VACUUM ANALYZE;

-- 4. Check for any configuration changes needed
SHOW all;
```

---

## Communication Templates

### Template 1: Initial Announcement (1 Week Before)

```
Subject: [ACTION REQUIRED] Aurora PostgreSQL Upgrade - [Database Name]

Hi Team,

We will be upgrading the Aurora PostgreSQL database from version 13.20 to 16.9.

WHEN: [Date] at [Time] [Timezone]
DURATION: Expected 15-30 minutes of downtime
IMPACT: [List affected applications/services]

WHY THIS UPGRADE:
- Security improvements
- Performance enhancements
- Access to new PostgreSQL 16 features
- Extended support timeline

WHAT YOU NEED TO DO:
1. Review the breaking changes document (attached)
2. Verify your application uses compatible database drivers
3. Test your application against the test environment:
   - Test endpoint: [endpoint]
   - Available: [dates]
4. Report any issues by [date]

BREAKING CHANGES:
- Python 2 PL/Python functions no longer supported
- PUBLIC schema permissions changed
- Some system catalog changes
- Full details: [link to this document]

TESTING:
We've created a test environment with PostgreSQL 16.9. Please test your applications:
- Test database endpoint: [endpoint]
- Test period: [dates]
- How to test: [instructions]

Please confirm your availability and testing completion by [date].

Questions? Contact: [team/email]

Best regards,
[Your Name]
Database Engineering Team
```

### Template 2: Maintenance Window Notification (24 Hours Before)

```
Subject: [REMINDER] Aurora PostgreSQL Upgrade Tomorrow - [Database Name]

Hi Team,

This is a reminder that the Aurora PostgreSQL upgrade will occur tomorrow.

WHEN: [Date] at [Time] [Timezone] (in ~24 hours)
DURATION: Expected 15-30 minutes
WHAT: Upgrade from PostgreSQL 13.20 to 16.9

WHAT TO EXPECT:
- Brief connection interruption during switchover
- Applications should automatically reconnect
- Monitor your services for 2-4 hours post-upgrade

ROLLBACK PLAN:
If critical issues are detected, we can rollback within the first 2 hours with minimal data loss.

We will provide updates in [Slack channel / Teams / etc.]:
- Start of maintenance
- Upgrade completion
- Post-upgrade status

CONTACTS:
- On-call engineer: [name/contact]
- War room: [Slack/Teams link]
- Escalation: [contact]

Thank you for your cooperation!

[Your Name]
Database Engineering Team
```

### Template 3: Upgrade In Progress

```
Subject: [IN PROGRESS] Aurora PostgreSQL Upgrade - [Database Name]

The Aurora PostgreSQL upgrade has started.

STATUS: Blue/Green deployment in progress
STARTED: [Time]
CURRENT STEP: Creating Green environment
NEXT STEP: Validation testing

Expected completion: [Time]

We will send another update once the upgrade is complete.

[Your Name]
```

### Template 4: Upgrade Complete

```
Subject: [COMPLETED] Aurora PostgreSQL Upgrade - [Database Name]

The Aurora PostgreSQL upgrade has been completed successfully.

COMPLETED AT: [Time]
NEW VERSION: PostgreSQL 16.9
DOWNTIME: [Actual duration]

CURRENT STATUS: ✅ All systems operational

VALIDATION RESULTS:
✅ Database version confirmed: 16.9
✅ All extensions loaded successfully
✅ Connection tests passed
✅ Sample queries performing normally
✅ Applications reconnected successfully

MONITORING:
We will continue to monitor the database for the next 24-48 hours. Please report any issues immediately.

If you notice any problems with your applications:
1. Check your application logs
2. Verify database connectivity
3. Contact [on-call engineer] if issues persist

Thank you for your patience!

[Your Name]
Database Engineering Team
```

### Template 5: Issue/Rollback Notice

```
Subject: [URGENT] Aurora PostgreSQL Upgrade - Rollback Initiated

We have detected issues following the PostgreSQL upgrade and are initiating a rollback.

ISSUE: [Description of the problem]
ACTION: Rolling back to PostgreSQL 13.20
STATUS: In progress

TIMELINE:
- Issue detected: [Time]
- Rollback started: [Time]
- Expected completion: [Time]

We will provide an update once the rollback is complete and systems are stable.

Apologies for the disruption. We will conduct a thorough post-mortem and reschedule the upgrade.

[Your Name]
Database Engineering Team
```

---

## Additional Resources

### AWS Documentation

1. **Aurora PostgreSQL Major Version Upgrades**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_UpgradeDBInstance.PostgreSQL.html
   - Comprehensive guide on upgrade procedures

2. **Aurora PostgreSQL Release Notes**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraPostgreSQLReleaseNotes/AuroraPostgreSQL.Updates.html
   - Aurora-specific changes and features

3. **Blue/Green Deployments for Aurora**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments.html
   - Detailed Blue/Green deployment guide

4. **Aurora PostgreSQL Best Practices**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html
   - Performance and operational best practices

### PostgreSQL Documentation

1. **PostgreSQL 14 Release Notes**
   - https://www.postgresql.org/docs/14/release-14.html
   - Complete list of changes in version 14

2. **PostgreSQL 15 Release Notes**
   - https://www.postgresql.org/docs/15/release-15.html
   - Complete list of changes in version 15

3. **PostgreSQL 16 Release Notes**
   - https://www.postgresql.org/docs/16/release-16.html
   - Complete list of changes in version 16

4. **PostgreSQL Upgrade Documentation**
   - https://www.postgresql.org/docs/current/upgrading.html
   - General upgrade guidance

### Tools and Scripts

1. **AWS CLI Installation**
   - https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

2. **pg_upgrade Compatibility Check**
   - For self-managed: https://www.postgresql.org/docs/current/pgupgrade.html

3. **PostgreSQL Extension Compatibility**
   - Check each extension's documentation for PostgreSQL 16 support

### Driver Documentation

1. **Python (psycopg2)**
   - https://www.psycopg.org/docs/

2. **Java (JDBC)**
   - https://jdbc.postgresql.org/

3. **Node.js (node-postgres)**
   - https://node-postgres.com/

4. **Ruby (pg gem)**
   - https://github.com/ged/ruby-pg

5. **.NET (Npgsql)**
   - https://www.npgsql.org/

6. **Go (pgx)**
   - https://github.com/jackc/pgx

### Monitoring and Troubleshooting

1. **Aurora Performance Insights**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_PerfInsights.html

2. **CloudWatch Metrics for Aurora**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Monitoring.html

3. **Aurora Recommendations**
   - https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_Recommendations.html

### Community Resources

1. **PostgreSQL Mailing Lists**
   - https://www.postgresql.org/list/

2. **Aurora PostgreSQL Community Forum**
   - https://repost.aws/tags/TA4IHblWvLT4ucfLpo-W-TXw/amazon-aurora

3. **Stack Overflow**
   - Tag: [amazon-aurora] + [postgresql]

---

## Appendix A: Common Issues and Solutions

### Issue 1: "public schema permission denied"

**Symptom:** Applications getting permission errors when creating temp tables

**Cause:** PostgreSQL 15 changed public schema permissions

**Solution:**
```sql
-- Grant CREATE on public schema if needed
GRANT CREATE ON SCHEMA public TO your_app_user;
-- Or better: create a dedicated schema
CREATE SCHEMA app_schema;
GRANT ALL ON SCHEMA app_schema TO your_app_user;
```

### Issue 2: Extension fails to load

**Symptom:** `ERROR: extension "xxx" is not available`

**Cause:** Extension not compatible with PostgreSQL 16

**Solution:**
```sql
-- Check available extensions
SELECT * FROM pg_available_extensions WHERE name = 'extension_name';

-- Update extension
ALTER EXTENSION extension_name UPDATE;

-- If not available, check AWS Aurora documentation for alternatives
```

### Issue 3: Query performance regression

**Symptom:** Queries slower after upgrade

**Cause:** Query planner changes, outdated statistics

**Solution:**
```sql
-- Update statistics
ANALYZE VERBOSE;

-- Check if parallel query is being used
EXPLAIN (ANALYZE, BUFFERS) your_query;

-- Adjust parameters if needed
ALTER DATABASE your_db SET max_parallel_workers_per_gather = 4;
```

### Issue 4: Connection pool exhaustion

**Symptom:** "too many connections" errors

**Cause:** Connection handling changes

**Solution:**
```sql
-- Check current connections
SELECT COUNT(*) FROM pg_stat_activity;

-- Adjust max_connections if needed (requires restart)
-- Better: optimize application connection pooling

-- Review connection timeout settings
ALTER DATABASE your_db SET idle_in_transaction_session_timeout = '5min';
```

### Issue 5: Stored procedure fails

**Symptom:** Stored procedure/function errors after upgrade

**Cause:** Deprecated syntax or behavior changes

**Solution:**
```sql
-- Review the function
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'your_function';

-- Common fixes:
-- 1. Update Python 2 to Python 3 syntax
-- 2. Fix deprecated dollar quoting issues
-- 3. Update deprecated system catalog references

-- Recreate function with updated syntax
CREATE OR REPLACE FUNCTION ...
```

---

## Appendix B: Performance Benchmarking

### Pre-Upgrade Benchmark Script

```sql
-- Save this as pre_upgrade_benchmark.sql
\timing on
\o pre_upgrade_benchmark_results.txt

-- Test 1: Simple SELECT
SELECT COUNT(*) FROM your_main_table;

-- Test 2: JOIN query
SELECT 
    t1.column1,
    t2.column2,
    COUNT(*)
FROM table1 t1
JOIN table2 t2 ON t1.id = t2.foreign_id
GROUP BY t1.column1, t2.column2
ORDER BY COUNT(*) DESC
LIMIT 100;

-- Test 3: Aggregate query
SELECT 
    date_trunc('hour', created_at) as hour,
    COUNT(*),
    AVG(value)
FROM your_metrics_table
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY hour
ORDER BY hour;

-- Test 4: Complex query (use your slowest query)
-- [Your complex query here]

-- Test 5: Insert performance
BEGIN;
INSERT INTO test_table (column1, column2)
SELECT 
    generate_series(1, 10000),
    'test_' || generate_series(1, 10000);
ROLLBACK;

\o
\timing off
```

Run before and after upgrade, compare results.

---

## Appendix C: Upgrade Checklist (Printable)

```
□ PLANNING PHASE
  □ Read this entire document
  □ Review PostgreSQL 14, 15, 16 release notes
  □ Inventory all database objects
  □ Identify custom functions/procedures
  □ Check extension compatibility
  □ Verify application driver versions
  □ Document current performance baseline
  □ Create rollback plan
  □ Schedule maintenance window
  
□ TESTING PHASE
  □ Create test environment
  □ Restore production snapshot to test
  □ Perform test upgrade
  □ Run application test suite
  □ Execute performance benchmarks
  □ Validate all integrations
  □ Document any issues found
  □ Fix compatibility issues
  □ Retest after fixes
  
□ COMMUNICATION PHASE
  □ Notify stakeholders (1 week before)
  □ Send reminder (24 hours before)
  □ Prepare status update templates
  □ Set up war room/incident bridge
  □ Confirm on-call schedule
  
□ PRE-UPGRADE PHASE
  □ Create final snapshot
  □ Verify backup retention
  □ Capture performance metrics
  □ Review rollback procedures
  □ Stage all scripts and commands
  □ Confirm team availability
  
□ UPGRADE EXECUTION
  □ Send "maintenance starting" notification
  □ Create Blue/Green deployment
  □ Wait for Green environment ready
  □ Validate Green environment
  □ Run smoke tests
  □ Perform switchover
  □ Monitor switchover completion
  □ Verify new version
  
□ POST-UPGRADE VALIDATION
  □ Check database version
  □ Verify extensions loaded
  □ Run validation queries
  □ Test application connectivity
  □ Monitor error rates
  □ Check performance metrics
  □ Update table statistics (ANALYZE)
  □ Monitor for 2-4 hours
  □ Send completion notification
  
□ CLEANUP
  □ Document lessons learned
  □ Update runbooks
  □ Delete test environments
  □ Schedule post-mortem (if issues)
  □ Archive upgrade artifacts
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-10-27 | Database Team | Initial document |

---

## Support and Questions

For questions or issues related to this upgrade:

- **Primary Contact:** [Your Team]
- **Email:** [team-email]
- **Slack:** [#database-upgrades]
- **On-Call:** [PagerDuty rotation]

---

**END OF DOCUMENT**

