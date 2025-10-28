# Upgrading Aurora PostgreSQL with Terragrunt
## From 13.20 to 16.8 Using Blue/Green Deployment

This guide shows how to perform a major version upgrade using your existing Terragrunt configuration.

---

## Quick Reference

| Method | Downtime | Risk | Complexity | Recommended For |
|--------|----------|------|------------|-----------------|
| **Blue/Green** | 15-30 sec | Low | Medium | **Production** ✅ |
| **Snapshot+Restore** | 30-45 min | Medium | Medium | Testing |
| **In-Place** | 30-60 min | High | Low | Emergency only |
| **Staged (13→14→15→16)** | Hours | Medium | High | Compatibility issues |

---

## Option 1: Blue/Green Deployment (Recommended)

### Overview
- Creates a copy of your cluster on v16.8
- Test everything on the copy
- Switch traffic with ~15 seconds downtime
- Keep old cluster for 24h rollback window

### Step-by-Step Process

#### Phase 1: Preparation (1 week before)

**1. Create v16 Parameter Groups**

```hcl
# terragrunt-examples/production-serverless-pg16/terragrunt.hcl

# Copy your existing terragrunt.hcl and update:

inputs = {
  # Update version
  engine_version         = "16.8"
  parameter_group_family = "aurora-postgresql16"
  
  # New cluster name for testing
  cluster_identifier = "prod-aurora-serverless-pg16-test"
  
  # Rest of config stays the same
  # ...
}
```

**2. Test Parameter Group Changes**

```bash
cd terragrunt-examples/production-serverless-pg16
terragrunt plan
# Review the parameter group changes
```

#### Phase 2: Create Blue/Green Deployment

**Option A: Using AWS CLI (Direct)**

```bash
#!/bin/bash
# upgrade-bluegreen.sh

set -e

# Configuration
CLUSTER_NAME="prod-aurora-serverless-postgres"  # Your current cluster
TARGET_VERSION="16.8"
PARAM_GROUP="prod-aurora-serverless-pg16-cluster-pg"  # From terragrunt
AWS_REGION="us-east-1"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo "=========================================="
echo "Aurora PostgreSQL Upgrade: 13.20 → 16.8"
echo "Method: Blue/Green Deployment"
echo "=========================================="

# Step 1: Create final snapshot
echo ""
echo "Step 1: Creating pre-upgrade snapshot..."
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}" \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --region "${AWS_REGION}"

echo "Waiting for snapshot completion..."
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}" \
  --region "${AWS_REGION}"

echo "✓ Snapshot created: ${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"

# Step 2: Create parameter group for v16 (if not exists)
echo ""
echo "Step 2: Creating PostgreSQL 16 parameter group..."
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name "${PARAM_GROUP}" \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Aurora PostgreSQL 16 parameters for production" \
  --region "${AWS_REGION}" \
  2>/dev/null || echo "Parameter group already exists"

# Step 3: Create Blue/Green deployment
echo ""
echo "Step 3: Creating Blue/Green deployment..."
DEPLOYMENT_ID=$(aws rds create-blue-green-deployment \
  --blue-green-deployment-name "${CLUSTER_NAME}-to-pg16-${TIMESTAMP}" \
  --source-arn "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER_NAME}" \
  --target-engine-version "${TARGET_VERSION}" \
  --target-db-cluster-parameter-group-name "${PARAM_GROUP}" \
  --region "${AWS_REGION}" \
  --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
  --output text)

echo "✓ Blue/Green Deployment ID: ${DEPLOYMENT_ID}"

# Step 4: Monitor deployment creation
echo ""
echo "Step 4: Waiting for green environment (this takes 15-20 minutes)..."
while true; do
  STATUS=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --region "${AWS_REGION}" \
    --query 'BlueGreenDeployments[0].Status' \
    --output text)
  
  echo "  Status: ${STATUS}"
  
  if [ "$STATUS" == "AVAILABLE" ]; then
    echo "✓ Green environment is ready for testing!"
    break
  elif [ "$STATUS" == "FAILED" ]; then
    echo "✗ Deployment failed!"
    exit 1
  fi
  
  sleep 60
done

# Step 5: Get green cluster endpoint
GREEN_CLUSTER_ID=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --region "${AWS_REGION}" \
  --query 'BlueGreenDeployments[0].Target' \
  --output text)

GREEN_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier "${GREEN_CLUSTER_ID}" \
  --region "${AWS_REGION}" \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo ""
echo "=========================================="
echo "GREEN ENVIRONMENT READY FOR TESTING"
echo "=========================================="
echo ""
echo "Blue (Production) Cluster: ${CLUSTER_NAME}"
echo "Green (Test) Cluster: ${GREEN_CLUSTER_ID}"
echo "Green Endpoint: ${GREEN_ENDPOINT}"
echo ""
echo "Next Steps:"
echo "1. Test your application against: ${GREEN_ENDPOINT}"
echo "2. Run validation queries (see below)"
echo "3. When ready to switch: ./upgrade-bluegreen-switchover.sh ${DEPLOYMENT_ID}"
echo "4. To rollback/cancel: ./upgrade-bluegreen-rollback.sh ${DEPLOYMENT_ID}"
echo ""
echo "Deployment ID saved to: bluegreen_deployment_id.txt"
echo "${DEPLOYMENT_ID}" > bluegreen_deployment_id.txt
```

**Option B: Using Terraform/Terragrunt**

Unfortunately, AWS Blue/Green deployments aren't directly supported in Terraform yet, so use the AWS CLI approach above.

#### Phase 3: Testing the Green Environment

```bash
#!/bin/bash
# test-green-environment.sh

DEPLOYMENT_ID=$(cat bluegreen_deployment_id.txt)
AWS_REGION="us-east-1"

# Get green cluster endpoint
GREEN_CLUSTER_ID=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --region "${AWS_REGION}" \
  --query 'BlueGreenDeployments[0].Target' \
  --output text)

GREEN_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier "${GREEN_CLUSTER_ID}" \
  --region "${AWS_REGION}" \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo "Testing Green Environment: ${GREEN_ENDPOINT}"
echo ""

# Test 1: Connection test
echo "Test 1: Connection Test"
psql "postgresql://YOUR_USER@${GREEN_ENDPOINT}:5432/YOUR_DB?sslmode=require" \
  -c "SELECT version();" \
  && echo "✓ Connection successful" \
  || echo "✗ Connection failed"

# Test 2: Verify version
echo ""
echo "Test 2: Verify PostgreSQL Version"
psql "postgresql://YOUR_USER@${GREEN_ENDPOINT}:5432/YOUR_DB?sslmode=require" \
  -c "SHOW server_version;" \
  | grep -q "16.8" \
  && echo "✓ Version is 16.8" \
  || echo "✗ Wrong version"

# Test 3: Check extensions
echo ""
echo "Test 3: Verify Extensions"
psql "postgresql://YOUR_USER@${GREEN_ENDPOINT}:5432/YOUR_DB?sslmode=require" \
  -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"

# Test 4: Run critical queries
echo ""
echo "Test 4: Running Critical Queries"
psql "postgresql://YOUR_USER@${GREEN_ENDPOINT}:5432/YOUR_DB?sslmode=require" \
  -f your_critical_queries.sql

# Test 5: Application integration test
echo ""
echo "Test 5: Application Integration"
echo "Update your application config to point to: ${GREEN_ENDPOINT}"
echo "Run your application test suite"
echo ""
echo "Example:"
echo "  export DATABASE_URL=postgresql://user@${GREEN_ENDPOINT}:5432/db"
echo "  npm test  # or pytest, mvn test, etc."
```

#### Phase 4: Switchover to Production

```bash
#!/bin/bash
# upgrade-bluegreen-switchover.sh

DEPLOYMENT_ID="${1:-$(cat bluegreen_deployment_id.txt)}"
AWS_REGION="us-east-1"

echo "=========================================="
echo "SWITCHING TO POSTGRESQL 16.8"
echo "=========================================="
echo ""
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo ""
echo "⚠️  WARNING: This will switch production traffic to PostgreSQL 16.8"
echo "⚠️  Expected downtime: 15-30 seconds"
echo ""
read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Switchover cancelled"
  exit 0
fi

echo ""
echo "Starting switchover..."

# Perform switchover
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --switchover-timeout 300 \
  --region "${AWS_REGION}"

# Monitor switchover
echo "Monitoring switchover progress..."
while true; do
  STATUS=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --region "${AWS_REGION}" \
    --query 'BlueGreenDeployments[0].Status' \
    --output text)
  
  echo "  Status: ${STATUS}"
  
  if [ "$STATUS" == "SWITCHOVER_COMPLETED" ]; then
    echo ""
    echo "=========================================="
    echo "✓ SWITCHOVER COMPLETED SUCCESSFULLY!"
    echo "=========================================="
    break
  elif [ "$STATUS" == "SWITCHOVER_FAILED" ]; then
    echo ""
    echo "✗ SWITCHOVER FAILED!"
    exit 1
  fi
  
  sleep 10
done

# Verify new version
NEW_VERSION=$(aws rds describe-db-clusters \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'DBClusters[0].EngineVersion' \
  --output text)

echo ""
echo "Current Version: ${NEW_VERSION}"
echo ""
echo "Next Steps:"
echo "1. Monitor your application for 1-2 hours"
echo "2. Check CloudWatch metrics and alarms"
echo "3. The old cluster (v13.20) is retained for 24h emergency rollback"
echo "4. After 24h validation, delete old environment:"
echo "   aws rds delete-blue-green-deployment \\"
echo "     --blue-green-deployment-identifier ${DEPLOYMENT_ID} \\"
echo "     --delete-target"
```

#### Phase 5: Rollback (if needed)

```bash
#!/bin/bash
# upgrade-bluegreen-rollback.sh

DEPLOYMENT_ID="${1:-$(cat bluegreen_deployment_id.txt)}"
AWS_REGION="us-east-1"

echo "=========================================="
echo "ROLLBACK: Switching back to PostgreSQL 13.20"
echo "=========================================="

# If BEFORE switchover - just delete green
STATUS=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --region "${AWS_REGION}" \
  --query 'BlueGreenDeployments[0].Status' \
  --output text)

if [ "$STATUS" != "SWITCHOVER_COMPLETED" ]; then
  echo "Green environment not yet in production. Deleting green environment..."
  aws rds delete-blue-green-deployment \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --delete-target \
    --region "${AWS_REGION}"
  echo "✓ Rollback complete - production unchanged"
  exit 0
fi

# If AFTER switchover - switch back
echo "Switching back to old environment..."
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
  --switchover-timeout 300 \
  --region "${AWS_REGION}"

echo "✓ Rolled back to PostgreSQL 13.20"
```

#### Phase 6: Update Terragrunt Configuration

After successful switchover, update your Terragrunt config:

```hcl
# terragrunt-examples/production-serverless/terragrunt.hcl

inputs = {
  # Update to new version
  engine_version         = "16.8"
  parameter_group_family = "aurora-postgresql16"
  
  # Keep everything else the same
  # ...
}
```

Then import the new state:

```bash
cd terragrunt-examples/production-serverless

# Import the upgraded cluster
terragrunt import 'module.aurora_cluster.aws_rds_cluster.main' your-cluster-id

# Verify no changes needed
terragrunt plan

# Should show no changes or only minor parameter adjustments
```

---

## Option 2: Snapshot Restore Approach

If Blue/Green is not available:

```bash
#!/bin/bash
# upgrade-snapshot-method.sh

CLUSTER_NAME="prod-aurora-serverless"
NEW_CLUSTER_NAME="${CLUSTER_NAME}-pg16"
TARGET_VERSION="16.8"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Step 1: Create snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-pg16-upgrade-${TIMESTAMP}" \
  --db-cluster-identifier "${CLUSTER_NAME}"

aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-pg16-upgrade-${TIMESTAMP}"

# Step 2: Restore to new cluster with v16
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier "${NEW_CLUSTER_NAME}" \
  --snapshot-identifier "${CLUSTER_NAME}-pg16-upgrade-${TIMESTAMP}" \
  --engine aurora-postgresql \
  --engine-version "${TARGET_VERSION}" \
  --db-cluster-parameter-group-name "aurora-postgresql16-params" \
  --vpc-security-group-ids "sg-xxxxx" \
  --db-subnet-group-name "your-subnet-group"

# Step 3: Create instances
aws rds create-db-instance \
  --db-instance-identifier "${NEW_CLUSTER_NAME}-instance-1" \
  --db-cluster-identifier "${NEW_CLUSTER_NAME}" \
  --engine aurora-postgresql \
  --db-instance-class db.serverless

# Step 4: Test, then manually switch application
echo "Test cluster: ${NEW_CLUSTER_NAME}"
echo "When ready, update application config and delete old cluster"
```

---

## Option 3: Direct In-Place Upgrade (Not Recommended)

```bash
#!/bin/bash
# upgrade-inplace.sh - USE WITH CAUTION

CLUSTER_NAME="prod-aurora-serverless"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Snapshot first
aws rds create-db-cluster-snapshot \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}" \
  --db-cluster-identifier "${CLUSTER_NAME}"

aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier "${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"

# Upgrade (causes downtime!)
aws rds modify-db-cluster \
  --db-cluster-identifier "${CLUSTER_NAME}" \
  --engine-version "16.8" \
  --db-cluster-parameter-group-name "aurora-postgresql16-params" \
  --apply-immediately \
  --allow-major-version-upgrade

echo "Upgrade started - expect 30-60 minutes downtime"
```

---

## Comparison Matrix

| Aspect | Blue/Green | Snapshot | In-Place |
|--------|-----------|----------|----------|
| **Setup Time** | 20 min | 30 min | 5 min |
| **Testing** | Full prod data | Full prod data | No testing |
| **Downtime** | 15-30 sec | 30-45 min | 30-60 min |
| **Rollback Time** | 15 sec | Hours | Hours |
| **Risk** | ⭐⭐⭐⭐⭐ Low | ⭐⭐⭐ Medium | ⭐ High |
| **Cost** | 2x cluster for test period | 2x cluster | 1x cluster |
| **Complexity** | Medium | Medium | Low |

---

## Checklist: Before Production Upgrade

```markdown
- [ ] Tested upgrade in non-production environment
- [ ] Parameter groups created for PostgreSQL 16
- [ ] Application tested against PostgreSQL 16
- [ ] Stakeholders notified of maintenance window
- [ ] Rollback plan documented and tested
- [ ] Snapshot retention extended
- [ ] On-call team ready
- [ ] Monitoring dashboards prepared
- [ ] Recent backup verified
- [ ] Performance baseline captured
```

---

## Post-Upgrade Validation

```sql
-- Connect to upgraded cluster
-- Run these validation queries

-- 1. Verify version
SHOW server_version;
-- Should show: PostgreSQL 16.8

-- 2. Check extensions
SELECT extname, extversion FROM pg_extension ORDER BY extname;

-- 3. Check replication lag (if multi-instance)
SELECT
  client_addr,
  state,
  sync_state,
  replay_lag
FROM pg_stat_replication;

-- 4. Verify statistics are updating
SELECT schemaname, tablename, last_vacuum, last_analyze
FROM pg_stat_user_tables
ORDER BY last_analyze DESC NULLS LAST
LIMIT 10;

-- 5. Check for any errors
SELECT * FROM pg_stat_database WHERE datname = current_database();
```

---

## Troubleshooting

### Issue: Parameter group incompatibility
```bash
# Check which parameters need updating
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name your-pg13-params \
  --query 'Parameters[?ApplyType==`pending-reboot`]'
```

### Issue: Extension version mismatch
```sql
-- Update extensions after upgrade
ALTER EXTENSION pg_stat_statements UPDATE;
ALTER EXTENSION pgaudit UPDATE;
```

### Issue: Application connection errors
```bash
# Verify security groups
aws rds describe-db-clusters \
  --db-cluster-identifier your-cluster \
  --query 'DBClusters[0].VpcSecurityGroups'
```

---

## Support Resources

- Full upgrade guide: `/docs/rds_upgrade/AURORA_POSTGRESQL_13_TO_16_UPGRADE_GUIDE.md`
- Upgrade scripts: `/docs/rds_upgrade/aurora_upgrade_scripts/`
- AWS Documentation: [Aurora PostgreSQL Upgrades](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_UpgradeDBInstance.PostgreSQL.html)

