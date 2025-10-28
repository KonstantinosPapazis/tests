# Aurora PostgreSQL Upgrade Scripts

These scripts automate the Blue/Green deployment upgrade process for Aurora PostgreSQL.

## Scripts Overview

| Script | Purpose | Usage |
|--------|---------|-------|
| `upgrade-bluegreen.sh` | Create Blue/Green deployment | First step: creates test environment |
| `test-green-environment.sh` | Test the upgraded cluster | Validates the green (upgraded) cluster |
| `upgrade-bluegreen-switchover.sh` | Switch to production | Moves traffic to upgraded cluster |
| `upgrade-bluegreen-rollback.sh` | Rollback if needed | Returns to original version |

## Quick Start

### 1. Initial Setup

```bash
# Set environment variables (optional - scripts have defaults)
export CLUSTER_NAME="prod-aurora-serverless-postgres"
export AWS_REGION="us-east-1"
export TARGET_VERSION="16.8"

# Or edit the scripts directly to set these values
```

### 2. Create Blue/Green Deployment

```bash
./upgrade-bluegreen.sh
```

**What it does:**
- Creates a final snapshot
- Creates PostgreSQL 16 parameter group
- Creates Blue/Green deployment
- Waits for green environment to be ready (~15-20 minutes)
- Outputs green cluster endpoint for testing

**Output files:**
- `bluegreen_deployment_id.txt` - Deployment ID (needed for other scripts)
- `green_cluster_info.txt` - Green cluster details
- `upgrade-bluegreen-TIMESTAMP.log` - Full log

### 3. Test Green Environment

```bash
./test-green-environment.sh
```

**What it does:**
- Connects to green cluster
- Verifies PostgreSQL version (16.8)
- Checks extensions
- Tests replication
- Runs sample queries
- Provides checklist for manual testing

**Requirements:**
- `psql` command-line tool installed
- Database credentials (uses environment or prompts)
- Security groups allow your IP

### 4. Switch to Production

```bash
./upgrade-bluegreen-switchover.sh
```

**What it does:**
- Confirms you want to proceed (requires typing "SWITCHOVER")
- Captures pre-switchover metrics
- Performs switchover (~15-30 seconds downtime)
- Monitors progress
- Verifies new version
- Provides post-switchover checklist

**Output files:**
- `switchover-complete-TIMESTAMP.txt` - Switchover details
- `pre-switchover-metrics-TIMESTAMP.json` - Metrics before switch

### 5. Rollback (if needed)

```bash
./upgrade-bluegreen-rollback.sh
```

**What it does:**
- Detects if switchover has occurred
- **Before switchover**: Simply deletes green environment (no production impact)
- **After switchover**: Switches back to old version (~15-30 seconds downtime)

**Output files:**
- `rollback-complete-TIMESTAMP.txt` - Rollback details

## Workflow Diagram

```
┌──────────────────────────────────────────────────────────────┐
│ Step 1: Create Blue/Green                                     │
│ Script: upgrade-bluegreen.sh                                  │
│ Time: 15-20 minutes                                           │
│ Output: Green cluster ready for testing                       │
└────────────┬─────────────────────────────────────────────────┘
             │
             ▼
┌──────────────────────────────────────────────────────────────┐
│ Step 2: Test Green Environment                                │
│ Script: test-green-environment.sh                             │
│ Time: 1-4 hours (thorough testing)                            │
│ Output: Test results + validation                             │
└────────────┬─────────────────────────────────────────────────┘
             │
             ▼
      ┌──────────────┐
      │ Tests Pass?  │
      └──┬────────┬──┘
         │ No     │ Yes
         │        │
         ▼        ▼
    ┌────────┐  ┌──────────────────────────────────────────────┐
    │Rollback│  │ Step 3: Switchover to Production             │
    │        │  │ Script: upgrade-bluegreen-switchover.sh      │
    └────────┘  │ Time: 15-30 seconds downtime                 │
                │ Output: Production on PostgreSQL 16.8         │
                └────────────┬─────────────────────────────────┘
                             │
                             ▼
                      ┌──────────────┐
                      │ Issues Found?│
                      └──┬────────┬──┘
                         │ Yes    │ No
                         │        │
                         ▼        ▼
                    ┌────────┐  ┌─────────────┐
                    │Rollback│  │ Success!    │
                    │ Step 5 │  │ Monitor 24h │
                    └────────┘  └─────────────┘
```

## Environment Variables

Scripts use these environment variables (with defaults):

```bash
# Cluster Configuration
CLUSTER_NAME="prod-aurora-serverless-postgres"  # Your cluster name
TARGET_VERSION="16.8"                            # Target PostgreSQL version
AWS_REGION="us-east-1"                          # AWS region

# Database Connection (for testing)
DB_USER="postgres"                               # Database username
DB_NAME="postgres"                               # Database name

# Optional
PARAM_GROUP=""                                   # Auto-generated if empty
SWITCHOVER_TIMEOUT="300"                         # 5 minutes
```

## Prerequisites

### Required

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws sts get-caller-identity
   ```

2. **jq** for JSON parsing
   ```bash
   # macOS
   brew install jq
   
   # Linux
   sudo apt-get install jq
   # or
   sudo yum install jq
   ```

3. **IAM Permissions**
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "rds:CreateBlueGreenDeployment",
       "rds:DeleteBlueGreenDeployment",
       "rds:DescribeBlueGreenDeployments",
       "rds:SwitchoverBlueGreenDeployment",
       "rds:CreateDBClusterSnapshot",
       "rds:DescribeDBClusters",
       "rds:DescribeDBClusterSnapshots",
       "rds:CreateDBClusterParameterGroup",
       "rds:DescribeDBClusterParameterGroups",
       "cloudwatch:GetMetricStatistics"
     ],
     "Resource": "*"
   }
   ```

### Optional (for testing script)

4. **psql** PostgreSQL client
   ```bash
   # macOS
   brew install postgresql
   
   # Linux
   sudo apt-get install postgresql-client
   ```

## Error Handling

All scripts:
- ✅ Use `set -e` to exit on error
- ✅ Check prerequisites before starting
- ✅ Validate deployment status
- ✅ Provide clear error messages
- ✅ Log all operations
- ✅ Create state files for resumability

## Safety Features

### Pre-flight Checks
- Verifies cluster exists
- Checks deployment status
- Validates permissions
- Confirms prerequisites

### Confirmation Prompts
- **Switchover**: Requires typing "SWITCHOVER"
- **Rollback**: Requires typing "DELETE" or "ROLLBACK"
- **Countdown**: 5-second countdown before critical operations

### State Preservation
- Creates snapshots before changes
- Keeps old cluster for 24h after switchover
- Logs all operations
- Saves deployment details to files

## Troubleshooting

### Script fails: "Command not found: jq"
```bash
# Install jq
brew install jq  # macOS
sudo apt-get install jq  # Ubuntu/Debian
```

### Script fails: "Cannot find deployment ID"
```bash
# Check if file exists
ls -la bluegreen_deployment_id.txt

# Or provide deployment ID manually
./test-green-environment.sh bgd-abc123xyz
```

### Test script fails: "Connection refused"
```bash
# Check security groups
aws rds describe-db-clusters \
  --db-cluster-identifier YOUR-CLUSTER \
  --query 'DBClusters[0].VpcSecurityGroups'

# Add your IP to security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp \
  --port 5432 \
  --cidr YOUR-IP/32
```

### Switchover takes too long
```bash
# Increase timeout
export SWITCHOVER_TIMEOUT=600  # 10 minutes

# Or edit the script
SWITCHOVER_TIMEOUT="${SWITCHOVER_TIMEOUT:-600}"
```

## Advanced Usage

### Running from CI/CD

```bash
# Non-interactive mode (use with caution!)
echo "SWITCHOVER" | ./upgrade-bluegreen-switchover.sh

# Or modify script to accept --force flag
# NOT RECOMMENDED for production
```

### Custom Validation Queries

Create a file `custom_validation.sql` in the same directory:

```sql
-- Your custom validation queries
SELECT count(*) FROM your_important_table;
SELECT * FROM your_critical_view LIMIT 10;
```

The test script will automatically run it if present.

### Monitoring During Switchover

```bash
# In another terminal, monitor metrics
watch -n 5 'aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=YOUR-CLUSTER \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average'
```

## Timeline Example

**Real-world timeline for a production upgrade:**

| Time | Action | Duration | Status |
|------|--------|----------|--------|
| 00:00 | Run `upgrade-bluegreen.sh` | 2 min | Setup |
| 00:02 | Wait for green environment | 18 min | Automated |
| 00:20 | Run `test-green-environment.sh` | 15 min | Manual |
| 00:35 | Run application tests | 2 hours | Manual |
| 02:35 | Review test results | 30 min | Manual |
| 03:05 | Run `upgrade-bluegreen-switchover.sh` | 30 sec | Downtime |
| 03:06 | Monitor production | 2 hours | Observation |
| 05:06 | Declare success | - | Complete |

**Total elapsed time**: ~5 hours  
**Actual downtime**: 30 seconds

## Files Created by Scripts

```
terragrunt-examples/scripts/
├── bluegreen_deployment_id.txt        # Deployment ID
├── green_cluster_info.txt             # Green cluster details
├── upgrade-bluegreen-TIMESTAMP.log    # Full upgrade log
├── switchover-complete-TIMESTAMP.txt  # Switchover details
├── pre-switchover-metrics-TIMESTAMP.json  # Metrics
├── rollback-complete-TIMESTAMP.txt    # Rollback details (if used)
└── custom_validation.sql              # Your custom tests (optional)
```

## Best Practices

1. **Test in Non-Production First**
   - Always test the upgrade process in dev/staging
   - Validate all application functionality
   - Measure performance differences

2. **Schedule During Low Traffic**
   - Choose a maintenance window
   - Notify stakeholders 48+ hours in advance
   - Have rollback plan ready

3. **Monitor Closely**
   - Watch for 1-2 hours post-switchover
   - Check application logs
   - Monitor database metrics
   - Verify backup processes

4. **Keep Old Cluster**
   - Wait 24-48 hours before deleting
   - Gives time to find issues
   - Easy emergency rollback

5. **Document Everything**
   - Save all log files
   - Document any issues found
   - Update runbooks with lessons learned

## Support

For issues with:
- **Scripts**: Check this README and logs
- **Upgrade process**: See `../UPGRADE_GUIDE.md`
- **AWS Blue/Green**: [AWS Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments.html)
- **PostgreSQL 16**: [Release Notes](https://www.postgresql.org/docs/16/release-16.html)

