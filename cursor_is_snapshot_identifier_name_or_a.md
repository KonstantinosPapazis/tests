# Is snapshot identifier name or arn?
_Exported on 10/31/2025 at 08:15:07 GMT+1 from Cursor (2.0.43)_

---

**User**

snapshot identifier is the snapshot name or arn?

---

**Cursor**

I'll help you understand what the `snapshot_identifier` parameter expects. Let me first check your current configuration.

Based on your Terraform configuration, the **`snapshot_identifier`** parameter (line 147 in `main.tf`) expects the **snapshot name/identifier**, **not the ARN**.

```147:147:/Users/kpapazis/Documents/repos/rds/rds_module/main.tf
  snapshot_identifier             = var.snapshot_identifier
```

For AWS RDS clusters, the snapshot identifier is the simple name of the snapshot, such as:
- `my-db-snapshot-2025-10-30`
- `rds:inv-bg-cluster-2025-10-30-12-34`

**Not** the full ARN like:
- ❌ `arn:aws:rds:eu-west-2:123456789012:cluster-snapshot:my-db-snapshot-2025-10-30`

If you want to restore from a snapshot, you would add this to your `terragrunt.hcl` inputs:

```hcl
inputs = {
  snapshot_identifier = "your-snapshot-name-here"
  # ... rest of your inputs
}
```

The AWS Terraform provider will automatically resolve the snapshot name to the correct resource in your account and region.

```plaintext
  snapshot_identifier             = var.snapshot_identifier
```

```plaintext
inputs = {
  snapshot_identifier = "your-snapshot-name-here"
  # ... rest of your inputs
}
```

---

**User**

let suppose that i am doing an rds upgrade and it gores wrong. i have my terraform code. what is the procedure to create a db from snapsshot? 

Should i give the destroy plan command, then set the snapshot_identifier and run the apply or should i do something else?

---

**Cursor**

Great question! Let me check your variable definitions first to see what's available:

Perfect! I can see the `snapshot_identifier` variable is defined (lines 351-355). Now let me explain the **proper disaster recovery procedure** for restoring from a snapshot when an upgrade goes wrong:

## **Recommended Approach: Create a New Cluster from Snapshot (Safest)**

**DO NOT destroy first!** Here's the safer approach:

### **Option 1: Parallel Restore (Recommended - Safest)**

1. **Verify snapshot exists** (check AWS Console or CLI):
   ```bash
   aws rds describe-db-cluster-snapshots \
     --db-cluster-identifier <your-cluster-name> \
     --region eu-west-2
   ```

2. **Create a new Terragrunt configuration** (copy your directory):
   ```bash
   cd /Users/kpapazis/Documents/repos/rds
   cp -r rds rds-recovery
   ```

3. **Edit `rds-recovery/terragrunt.hcl`** and add/modify:
   ```hcl
   inputs = {
     snapshot_identifier = "your-snapshot-identifier-here"
     cluster_name_override = "inv-bg-cluster-recovery"  # Different name!
     # ... keep all other settings the same
   }
   ```

4. **Apply to create new cluster from snapshot**:
   ```bash
   cd rds-recovery
   terragrunt plan
   terragrunt apply
   ```

5. **Test the recovered database** thoroughly

6. **Switch over**: Update your app to point to the new cluster endpoint

7. **Clean up the broken cluster**:
   ```bash
   cd ../rds
   terragrunt destroy
   ```

---

### **Option 2: In-Place Recovery (Faster but Riskier)**

⚠️ **Warning**: Only use this if you're confident the snapshot is good and you don't need the broken cluster.

1. **Ensure you have a valid snapshot** (manual or automatic backup)

2. **Destroy the broken cluster**:
   ```bash
   cd /Users/kpapazis/Documents/repos/rds/rds
   terragrunt destroy
   ```

3. **Update your `terragrunt.hcl`** to add the snapshot identifier:
   ```hcl
   inputs = {
     snapshot_identifier = "rds:inv-bg-cluster-2025-10-30-12-34"  # Your snapshot name
     # ... all your existing settings
   }
   ```

4. **Apply to recreate from snapshot**:
   ```bash
   terragrunt plan
   terragrunt apply
   ```

5. **After successful restore, remove the snapshot_identifier**:
   - This prevents Terraform from trying to restore from snapshot on every apply
   - Comment it out or remove the line from `terragrunt.hcl`

---

## **Important Notes:**

- **Snapshot naming**: AWS automatic snapshots follow the pattern `rds:cluster-name-YYYY-MM-DD-HH-MM`
- **Manual snapshots**: Use the name you assigned when creating them
- **One-time restore**: The `snapshot_identifier` is only used during cluster **creation**, not updates
- **Deletion protection**: Your current config has `deletion_protection = false`, so be careful with destroy commands
- **Final snapshot**: You have `database_skip_final_snapshot = true`, which means **no automatic snapshot on destroy** - ensure you have a manual snapshot first!

## **Best Practice:**

Before destroying anything, create a **manual snapshot** first:
```bash
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier <your-cluster-id> \
  --db-cluster-snapshot-identifier inv-bg-manual-recovery-$(date +%Y%m%d-%H%M) \
  --region eu-west-2
```

**I recommend Option 1** (parallel restore) as it's safer - you keep the broken cluster until you've verified the restored one works perfectly.

```shellscript
   aws rds describe-db-cluster-snapshots \
     --db-cluster-identifier <your-cluster-name> \
     --region eu-west-2
```

```shellscript
   cd /Users/kpapazis/Documents/repos/rds
   cp -r rds rds-recovery
```

```plaintext
   inputs = {
     snapshot_identifier = "your-snapshot-identifier-here"
     cluster_name_override = "inv-bg-cluster-recovery"  # Different name!
     # ... keep all other settings the same
   }
```

```shellscript
   cd rds-recovery
   terragrunt plan
   terragrunt apply
```

```shellscript
   cd ../rds
   terragrunt destroy
```

```shellscript
   cd /Users/kpapazis/Documents/repos/rds/rds
   terragrunt destroy
```

```plaintext
   inputs = {
     snapshot_identifier = "rds:inv-bg-cluster-2025-10-30-12-34"  # Your snapshot name
     # ... all your existing settings
   }
```

```shellscript
   terragrunt plan
   terragrunt apply
```

```shellscript
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier <your-cluster-id> \
  --db-cluster-snapshot-identifier inv-bg-manual-recovery-$(date +%Y%m%d-%H%M) \
  --region eu-west-2
```

---

**User**

i want to do another test, i will create a new rds cluster. I want you to give me the commands to create a table inside the database. Then i will take a snapshot. I will perform the upgrade and check if my table is still there. Then I will delete the rds. I will create a new one from snapshot and i want to verify that my table will still be there, Is it ok?

---

**Cursor**

Excellent test plan! This is a great way to validate your disaster recovery procedure. Let me give you the complete step-by-step commands.

Perfect! This is an excellent test plan. Here's the complete workflow with all commands:

## **📋 Complete Test Workflow**

### **Step 1: Create the RDS Cluster**

```bash
cd /Users/kpapazis/Documents/repos/rds/rds
terragrunt plan
terragrunt apply
```

Wait for the cluster to be available (~5-10 minutes).

---

### **Step 2: Get the Cluster Endpoint and Connect**

```bash
# Get the cluster endpoint
aws rds describe-db-clusters \
  --region eu-west-2 \
  --query 'DBClusters[?DatabaseName==`invbg`].[Endpoint,Port,DBClusterIdentifier]' \
  --output table

# Or using terragrunt output (if you have an output defined)
terragrunt output
```

**Connect to PostgreSQL:**

```bash
# Replace <ENDPOINT> with your actual cluster endpoint
psql -h <ENDPOINT> \
     -U adminmiscloud \
     -d invbg \
     -p 5432
```

When prompted, enter the password from your `rds_credentials`.

---

### **Step 3: Create a Test Table with Data**

Once connected to PostgreSQL, run these SQL commands:

```sql
-- Create a test table
CREATE TABLE upgrade_test (
    id SERIAL PRIMARY KEY,
    test_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    test_data TEXT
);

-- Insert test data
INSERT INTO upgrade_test (test_name, test_data) VALUES
    ('Pre-upgrade test', 'This data was created before the upgrade'),
    ('Snapshot verification', 'Testing snapshot restore functionality'),
    ('Version 13.20', 'Created in PostgreSQL 13.20');

-- Verify data was inserted
SELECT * FROM upgrade_test;

-- Check the current PostgreSQL version
SELECT version();

-- Exit psql
\q
```

---

### **Step 4: Take a Manual Snapshot**

```bash
# Get your cluster identifier first
CLUSTER_ID=$(aws rds describe-db-clusters \
  --region eu-west-2 \
  --query 'DBClusters[?DatabaseName==`invbg`].DBClusterIdentifier' \
  --output text)

echo "Cluster ID: $CLUSTER_ID"

# Create manual snapshot
SNAPSHOT_ID="inv-bg-pre-upgrade-test-$(date +%Y%m%d-%H%M)"
echo "Creating snapshot: $SNAPSHOT_ID"

aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region eu-west-2

# Wait for snapshot to complete
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region eu-west-2

echo "Snapshot created successfully!"

# Verify snapshot
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region eu-west-2 \
  --query 'DBClusterSnapshots[0].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table
```

---

### **Step 5: Perform the Upgrade**

Update your `terragrunt.hcl`:

```hcl
inputs = {
  # Change these lines:
  rds_family_name        = "aurora-postgresql14"  # Was: aurora-postgresql13
  rds_engine_version     = "14.13"                 # Was: 13.20
  
  # ... keep all other settings the same
}
```

Then apply:

```bash
terragrunt plan
terragrunt apply
```

Wait for the upgrade to complete.

---

### **Step 6: Verify Table Still Exists After Upgrade**

```bash
# Reconnect (endpoint will be the same)
psql -h <ENDPOINT> -U adminmiscloud -d invbg -p 5432
```

```sql
-- Verify your table and data survived the upgrade
SELECT * FROM upgrade_test;

-- Check new version
SELECT version();

-- Add a post-upgrade row to differentiate
INSERT INTO upgrade_test (test_name, test_data) VALUES
    ('Post-upgrade test', 'This data was added after upgrading to 14.x');

SELECT * FROM upgrade_test;

\q
```

---

### **Step 7: Delete the RDS Cluster**

```bash
cd /Users/kpapazis/Documents/repos/rds/rds
terragrunt destroy
```

**Note**: Since you have `database_skip_final_snapshot = true`, no automatic snapshot will be created on destroy. That's fine - you already have your manual snapshot!

---

### **Step 8: Restore from Snapshot (New Cluster)**

Edit your `terragrunt.hcl` to add the snapshot identifier:

```hcl
inputs = {
  snapshot_identifier = "inv-bg-pre-upgrade-test-YYYYMMDD-HHMM"  # Your snapshot name from Step 4
  
  # IMPORTANT: Use the original version settings that match the snapshot!
  rds_family_name        = "aurora-postgresql13"  # Match snapshot version
  rds_engine_version     = "13.20"                 # Match snapshot version
  
  # ... all other settings remain the same
}
```

Apply to create from snapshot:

```bash
terragrunt plan
terragrunt apply
```

---

### **Step 9: Verify Table from Snapshot**

```bash
# Get new endpoint (might be the same if using same cluster name)
psql -h <ENDPOINT> -U adminmiscloud -d invbg -p 5432
```

```sql
-- Verify the data from BEFORE the upgrade is there
SELECT * FROM upgrade_test ORDER BY id;

-- You should see:
-- 1. Pre-upgrade test
-- 2. Snapshot verification  
-- 3. Version 13.20
-- But NOT the "Post-upgrade test" row (that was added after the snapshot)

-- Check version (should be 13.x since we restored from that snapshot)
SELECT version();

\q
```

---

## **Expected Results:**

✅ **After Step 6 (post-upgrade)**: 4 rows including the post-upgrade test  
✅ **After Step 9 (restored from snapshot)**: 3 rows only (the pre-upgrade data)  
✅ **This proves the snapshot captured the exact state before the upgrade**

---

## **Quick Reference Commands:**

```bash
# Save these for quick access during your test:

# List all snapshots
aws rds describe-db-cluster-snapshots \
  --region eu-west-2 \
  --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier,`inv-bg`)].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table

# Get cluster status
aws rds describe-db-clusters \
  --region eu-west-2 \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].[DBClusterIdentifier,Status,EngineVersion,Endpoint]' \
  --output table
```

This test will definitively prove that your snapshot/restore process works correctly! 🎯

```shellscript
cd /Users/kpapazis/Documents/repos/rds/rds
terragrunt plan
terragrunt apply
```

```shellscript
# Get the cluster endpoint
aws rds describe-db-clusters \
  --region eu-west-2 \
  --query 'DBClusters[?DatabaseName==`invbg`].[Endpoint,Port,DBClusterIdentifier]' \
  --output table

# Or using terragrunt output (if you have an output defined)
terragrunt output
```

```shellscript
# Replace <ENDPOINT> with your actual cluster endpoint
psql -h <ENDPOINT> \
     -U adminmiscloud \
     -d invbg \
     -p 5432
```

```sql
-- Create a test table
CREATE TABLE upgrade_test (
    id SERIAL PRIMARY KEY,
    test_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    test_data TEXT
);

-- Insert test data
INSERT INTO upgrade_test (test_name, test_data) VALUES
    ('Pre-upgrade test', 'This data was created before the upgrade'),
    ('Snapshot verification', 'Testing snapshot restore functionality'),
    ('Version 13.20', 'Created in PostgreSQL 13.20');

-- Verify data was inserted
SELECT * FROM upgrade_test;

-- Check the current PostgreSQL version
SELECT version();

-- Exit psql
\q
```

```shellscript
# Get your cluster identifier first
CLUSTER_ID=$(aws rds describe-db-clusters \
  --region eu-west-2 \
  --query 'DBClusters[?DatabaseName==`invbg`].DBClusterIdentifier' \
  --output text)

echo "Cluster ID: $CLUSTER_ID"

# Create manual snapshot
SNAPSHOT_ID="inv-bg-pre-upgrade-test-$(date +%Y%m%d-%H%M)"
echo "Creating snapshot: $SNAPSHOT_ID"

aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region eu-west-2

# Wait for snapshot to complete
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region eu-west-2

echo "Snapshot created successfully!"

# Verify snapshot
aws rds describe-db-cluster-snapshots \
  --db-cluster-snapshot-identifier $SNAPSHOT_ID \
  --region eu-west-2 \
  --query 'DBClusterSnapshots[0].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table
```

```plaintext
inputs = {
  # Change these lines:
  rds_family_name        = "aurora-postgresql14"  # Was: aurora-postgresql13
  rds_engine_version     = "14.13"                 # Was: 13.20
  
  # ... keep all other settings the same
}
```

```shellscript
terragrunt plan
terragrunt apply
```

```shellscript
# Reconnect (endpoint will be the same)
psql -h <ENDPOINT> -U adminmiscloud -d invbg -p 5432
```

```sql
-- Verify your table and data survived the upgrade
SELECT * FROM upgrade_test;

-- Check new version
SELECT version();

-- Add a post-upgrade row to differentiate
INSERT INTO upgrade_test (test_name, test_data) VALUES
    ('Post-upgrade test', 'This data was added after upgrading to 14.x');

SELECT * FROM upgrade_test;

\q
```

```shellscript
cd /Users/kpapazis/Documents/repos/rds/rds
terragrunt destroy
```

```plaintext
inputs = {
  snapshot_identifier = "inv-bg-pre-upgrade-test-YYYYMMDD-HHMM"  # Your snapshot name from Step 4
  
  # IMPORTANT: Use the original version settings that match the snapshot!
  rds_family_name        = "aurora-postgresql13"  # Match snapshot version
  rds_engine_version     = "13.20"                 # Match snapshot version
  
  # ... all other settings remain the same
}
```

```shellscript
terragrunt plan
terragrunt apply
```

```shellscript
# Get new endpoint (might be the same if using same cluster name)
psql -h <ENDPOINT> -U adminmiscloud -d invbg -p 5432
```

```sql
-- Verify the data from BEFORE the upgrade is there
SELECT * FROM upgrade_test ORDER BY id;

-- You should see:
-- 1. Pre-upgrade test
-- 2. Snapshot verification  
-- 3. Version 13.20
-- But NOT the "Post-upgrade test" row (that was added after the snapshot)

-- Check version (should be 13.x since we restored from that snapshot)
SELECT version();

\q
```

```shellscript
# Save these for quick access during your test:

# List all snapshots
aws rds describe-db-cluster-snapshots \
  --region eu-west-2 \
  --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier,`inv-bg`)].[DBClusterSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table

# Get cluster status
aws rds describe-db-clusters \
  --region eu-west-2 \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].[DBClusterIdentifier,Status,EngineVersion,Endpoint]' \
  --output table
```

