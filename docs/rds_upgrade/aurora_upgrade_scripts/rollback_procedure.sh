#!/bin/bash
################################################################################
# Aurora PostgreSQL Rollback Script
# Version: 1.0
# Purpose: Rollback from PostgreSQL 16.9 to 13.20
################################################################################

set -e
set -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# CONFIGURATION
################################################################################

export AWS_REGION="us-east-1"
export CLUSTER_NAME="your-prod-cluster-name"
export DEPLOYMENT_ID=""  # Will be prompted or read from file

LOG_FILE="rollback_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

################################################################################
# FUNCTIONS
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

confirm_action() {
    local prompt="$1"
    local expected="$2"
    read -p "$(echo -e ${RED}$prompt${NC}) " response
    if [ "$response" != "$expected" ]; then
        log_error "Action cancelled"
        exit 1
    fi
}

################################################################################
# ROLLBACK METHODS
################################################################################

method_1_bluegreen_switchback() {
    log_warn "METHOD 1: Blue/Green Switchback"
    log_warn "This will switch back to the PostgreSQL 13.20 environment"
    log_warn "Data changes made during PG 16 runtime will be LOST"
    echo ""
    
    # Get or verify deployment ID
    if [ -z "$DEPLOYMENT_ID" ]; then
        read -p "Enter Blue/Green Deployment ID: " DEPLOYMENT_ID
    fi
    
    # Verify deployment exists
    if ! aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$DEPLOYMENT_ID" &> /dev/null; then
        log_error "Deployment $DEPLOYMENT_ID not found"
        exit 1
    fi
    
    # Get current status
    STATUS=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
        --query 'BlueGreenDeployments[0].Status' \
        --output text)
    
    log_info "Current deployment status: $STATUS"
    
    if [ "$STATUS" != "SWITCHOVER_COMPLETED" ]; then
        log_error "Deployment is not in SWITCHOVER_COMPLETED state"
        log_error "Current state: $STATUS"
        exit 1
    fi
    
    # Final confirmation
    echo ""
    log_error "⚠️  WARNING: This will rollback to PostgreSQL 13.20"
    log_error "⚠️  All data changes since upgrade will be LOST"
    log_error "⚠️  Brief downtime will occur (2-5 minutes)"
    echo ""
    confirm_action "Type 'ROLLBACK' to proceed: " "ROLLBACK"
    
    log_info "Starting switchback in 10 seconds... Press Ctrl+C to abort."
    sleep 10
    
    # Perform switchback
    log_info "Performing switchback..."
    aws rds switchover-blue-green-deployment \
        --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
        --switchover-timeout 300
    
    # Monitor switchback
    log_info "Monitoring switchback progress..."
    local max_wait=600
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        STATUS=$(aws rds describe-blue-green-deployments \
            --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
            --query 'BlueGreenDeployments[0].Status' \
            --output text)
        
        log_info "Switchback status: $STATUS"
        
        if [ "$STATUS" == "SWITCHOVER_COMPLETED" ]; then
            log_info "Switchback completed! ✓"
            break
        elif [ "$STATUS" == "SWITCHOVER_FAILED" ]; then
            log_error "Switchback failed!"
            exit 1
        fi
        
        sleep 30
        elapsed=$((elapsed + 30))
    done
    
    # Verify version
    CURRENT_VERSION=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].EngineVersion' \
        --output text)
    
    log_info "Current version: $CURRENT_VERSION"
    
    if [[ "$CURRENT_VERSION" == 13.* ]]; then
        log_info "Successfully rolled back to PostgreSQL 13 ✓"
    else
        log_warn "Version is $CURRENT_VERSION - verify rollback success"
    fi
}

method_2_snapshot_restore() {
    log_warn "METHOD 2: Snapshot Restore"
    log_warn "This will restore from a pre-upgrade snapshot"
    log_warn "All data changes since snapshot will be LOST"
    echo ""
    
    # List available snapshots
    log_info "Finding pre-upgrade snapshots..."
    aws rds describe-db-cluster-snapshots \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, `before-pg16`)].{ID:DBClusterSnapshotIdentifier,Time:SnapshotCreateTime,Status:Status}' \
        --output table
    
    # Get snapshot ID
    read -p "Enter snapshot ID to restore from: " SNAPSHOT_ID
    
    # Verify snapshot exists
    if ! aws rds describe-db-cluster-snapshots \
        --db-cluster-snapshot-identifier "$SNAPSHOT_ID" &> /dev/null; then
        log_error "Snapshot $SNAPSHOT_ID not found"
        exit 1
    fi
    
    # Get snapshot info
    SNAPSHOT_TIME=$(aws rds describe-db-cluster-snapshots \
        --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
        --query 'DBClusterSnapshots[0].SnapshotCreateTime' \
        --output text)
    
    log_warn "Snapshot: $SNAPSHOT_ID"
    log_warn "Created: $SNAPSHOT_TIME"
    log_warn "All changes after this time will be LOST"
    echo ""
    
    # Confirm
    confirm_action "Type 'RESTORE' to proceed: " "RESTORE"
    
    # Strategy: Rename current, restore with original name
    TEMP_NAME="${CLUSTER_NAME}-pg16-backup"
    
    log_info "Step 1: Renaming current cluster to $TEMP_NAME"
    aws rds modify-db-cluster-identifier \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --new-db-cluster-identifier "$TEMP_NAME" \
        --apply-immediately
    
    log_info "Waiting for rename to complete..."
    sleep 30
    
    log_info "Step 2: Restoring snapshot with original cluster name"
    aws rds restore-db-cluster-from-snapshot \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --snapshot-identifier "$SNAPSHOT_ID" \
        --engine aurora-postgresql
    
    log_info "Step 3: Creating cluster instances..."
    # Get instance info from temp cluster
    INSTANCE_INFO=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$TEMP_NAME" \
        --query 'DBClusters[0].DBClusterMembers[0].[DBInstanceIdentifier,IsClusterWriter]' \
        --output text)
    
    INSTANCE_CLASS=$(aws rds describe-db-instances \
        --db-instance-identifier "${INSTANCE_INFO%	*}" \
        --query 'DBInstances[0].DBInstanceClass' \
        --output text)
    
    aws rds create-db-instance \
        --db-instance-identifier "${CLUSTER_NAME}-instance-1" \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --engine aurora-postgresql \
        --db-instance-class "$INSTANCE_CLASS"
    
    log_info "Waiting for cluster to be available (this may take 10-15 minutes)..."
    aws rds wait db-cluster-available \
        --db-cluster-identifier "$CLUSTER_NAME"
    
    # Verify version
    RESTORED_VERSION=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].EngineVersion' \
        --output text)
    
    log_info "Restored to version: $RESTORED_VERSION ✓"
    
    log_warn "The upgraded cluster has been renamed to: $TEMP_NAME"
    log_warn "After validation, delete it with:"
    log_warn "  aws rds delete-db-cluster --db-cluster-identifier $TEMP_NAME --skip-final-snapshot"
}

method_3_point_in_time() {
    log_warn "METHOD 3: Point-in-Time Recovery"
    log_warn "Restore to a specific point in time before upgrade"
    echo ""
    
    # Get earliest restorable time
    EARLIEST=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].EarliestRestorableTime' \
        --output text)
    
    LATEST=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].LatestRestorableTime' \
        --output text)
    
    log_info "Available restore window:"
    log_info "  Earliest: $EARLIEST"
    log_info "  Latest: $LATEST"
    echo ""
    
    read -p "Enter restore time (YYYY-MM-DDTHH:MM:SSZ): " RESTORE_TIME
    
    # Validate time format
    if ! date -d "$RESTORE_TIME" &> /dev/null; then
        log_error "Invalid time format"
        exit 1
    fi
    
    log_warn "Will restore to: $RESTORE_TIME"
    log_warn "All changes after this time will be LOST"
    echo ""
    
    confirm_action "Type 'PITR' to proceed: " "PITR"
    
    TEMP_NAME="${CLUSTER_NAME}-pg16-backup"
    RESTORE_CLUSTER="${CLUSTER_NAME}-pitr-restore"
    
    log_info "Creating point-in-time restore..."
    aws rds restore-db-cluster-to-point-in-time \
        --source-db-cluster-identifier "$CLUSTER_NAME" \
        --db-cluster-identifier "$RESTORE_CLUSTER" \
        --restore-to-time "$RESTORE_TIME" \
        --use-latest-restorable-time false
    
    log_info "Waiting for restore to complete..."
    aws rds wait db-cluster-available \
        --db-cluster-identifier "$RESTORE_CLUSTER"
    
    log_info "Restore completed. Test the restored cluster before switching over."
    log_info "Restored cluster: $RESTORE_CLUSTER"
    log_info ""
    log_info "To complete rollback:"
    log_info "1. Test the restored cluster"
    log_info "2. Rename current production cluster"
    log_info "3. Rename restored cluster to production name"
}

################################################################################
# MAIN
################################################################################

main() {
    echo "=========================================="
    echo "Aurora PostgreSQL Rollback Script"
    echo "=========================================="
    echo ""
    log_error "⚠️  WARNING: Rollback operations cause data loss!"
    log_error "⚠️  Changes made after upgrade/snapshot will be lost"
    echo ""
    
    echo "Available rollback methods:"
    echo "1. Blue/Green Switchback (fastest, if available)"
    echo "2. Snapshot Restore (if snapshot exists)"
    echo "3. Point-in-Time Recovery (most flexible)"
    echo ""
    
    read -p "Select rollback method (1-3): " METHOD
    
    case $METHOD in
        1)
            method_1_bluegreen_switchback
            ;;
        2)
            method_2_snapshot_restore
            ;;
        3)
            method_3_point_in_time
            ;;
        *)
            log_error "Invalid selection"
            exit 1
            ;;
    esac
    
    echo ""
    echo "=========================================="
    echo "Rollback Summary"
    echo "=========================================="
    echo "Cluster: $CLUSTER_NAME"
    echo "Method: $METHOD"
    echo "Log File: $LOG_FILE"
    echo ""
    echo "Next Steps:"
    echo "1. Verify application connectivity"
    echo "2. Check database version"
    echo "3. Monitor for issues"
    echo "4. Conduct post-mortem"
    echo "5. Plan re-attempt of upgrade"
    echo "=========================================="
}

# Run main
main

exit 0

