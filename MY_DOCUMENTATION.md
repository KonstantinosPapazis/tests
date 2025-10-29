Aurora PostgreSQL Major Version Upgrade Guide
Overview
This guide covers two methods for upgrading your Aurora PostgreSQL database to a newer major version:

    Blue/Green Deployment (Recommended for production)
    Direct In-Place Upgrade (Faster but riskier)

Option 1: Blue/Green Deployment (Recommended)
What is Blue/Green Deployment?
Blue/Green deployment creates a complete copy of your database cluster running the new PostgreSQL version. This allows you to:

    Test thoroughly before switching production traffic
    Minimize downtime during the upgrade
    Roll back easily if issues arise

Prerequisites
1. Scale Serverless Capacity

    ⚠️ Important: Blue/Green deployment runs two clusters simultaneously, requiring minimum capacity ≥ 1.0 ACU 

Current Configuration (in terragrunt.hcl):
hcl

inputs = {
  serverless_min_capacity = 0.5  # Must be changed to 1.0
  serverless_max_capacity = xxx
  engine_version = "13.20"
}

Required Change:
hcl

serverless_min_capacity = 1.0

2. Custom Parameter Group Setup

    🚨 Critical Requirement: Blue/Green deployments do not support default parameter groups. You must create a custom parameter group. 

Why? Default parameter groups (like default.aurora-postgresql13) are AWS-managed and read-only. Blue/Green deployments require custom parameter groups for configuration control.Step 1: Create Custom Parameter Group
hcl

cluster_parameter_group_parameters = [
  {
    "apply_method" = "pending-reboot"
    "name"         = "rds.logical_replication"
    "value"        = "1"
  }
]

    ⚠️ Note: This change requires a database reboot to take effect. 

Step 2: Create Target Parameter Group for New VersionUsing AWS CLI:
bash

aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name <your-parameter-group-name> \
  --db-parameter-group-family aurora-postgresql14 \
  --description "PostgreSQL 14 cluster parameters" \
  --region eu-west-2

Or using Terraform module (add to terragrunt.hcl):
hcl

create_target_parameter_group = true 
target_rds_family_name        = "aurora-postgresql14"

Executing the Blue/Green Deployment
Command Template
The Terraform module provides this command output:
bash

aws rds create-blue-green-deployment \
    --blue-green-deployment-name "${cluster-id}-upgrade-${current-version}-to-${target-version}" \
    --source-arn "${cluster-arn}" \
    --target-engine-version "<TARGET_VERSION>" \
    --target-db-cluster-parameter-group-name "${target-parameter-group-name}" \
    --region ${aws-region}

Real Example (13.20 to 14.18)
bash

aws rds create-blue-green-deployment \
    --blue-green-deployment-name "production-db-upgrade-13-to-14" \
    --source-arn "arn:aws:rds:eu-west-2:123456789:cluster:prod-db" \
    --target-engine-version "14.18" \
    --target-db-cluster-parameter-group-name "aurora-postgresql14-custom" \
    --region eu-west-2

Option 2: Direct In-Place Upgrade
What is Direct In-Place Upgrade?
This method directly modifies your existing cluster to the new PostgreSQL version through Terraform/Terragrunt configuration changes.
Prerequisites
1. Create Manual Snapshot

    🚨 Critical: Always create a manual snapshot before upgrading 

bash

aws rds create-db-cluster-snapshot \
    --db-cluster-snapshot-identifier pre-upgrade-snapshot \
    --db-cluster-identifier your-cluster-id

2. Enable Immediate Modifications
Add to terragrunt.hcl:
hcl

apply_modifications_immediately = true

Upgrade Process
Standard Upgrade (Without Custom Parameter Groups)

    Update the engine version in terragrunt.hcl
    Run terragrunt plan and review changes
    Run terragrunt apply

Upgrade With Custom Parameter Groups

    ⚠️ Important: Custom parameter group upgrades cannot be done directly through Terraform/Terragrunt 

Step-by-Step Process:

    Temporarily Switch to Default Parameter Group
        Comment out custom parameter group in configuration
        Add default parameter group reference
        Apply changes: terragrunt apply

    Upgrade Database Version
        Update engine_version in terragrunt.hcl
        Apply changes: terragrunt apply

    Restore Custom Parameter Group
        Remove default parameter group reference
        Uncomment custom parameter group configuration
        Apply changes: terragrunt apply

Rollback Procedure

    🚨 Warning: Rollback after in-place upgrade requires deleting the upgraded cluster and restoring from snapshot 

If Issues Are Discovered Post-Upgrade:

    Document the issue and impact
    Delete the upgraded cluster
    Restore from pre-upgrade snapshot
    Verify data integrity
    Update connection strings if needed

Decision Matrix
Factor	Blue/Green Deployment	Direct In-Place Upgrade
Downtime	Minimal (seconds to minutes)	Extended (30+ minutes)
Rollback Capability	Easy (switch back to blue)	Complex (restore from snapshot)
Testing Opportunity	Full testing possible	Limited testing
Resource Cost	Higher (two clusters)	Lower (single cluster)
Complexity	Higher setup complexity	Simpler process
Best For	Production environments	Development/Testing environments