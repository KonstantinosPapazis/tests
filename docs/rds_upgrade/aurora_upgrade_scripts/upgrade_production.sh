#!/bin/bash
################################################################################
# Aurora PostgreSQL Upgrade Script - Production
# Version: 1.0
# Upgrades: PostgreSQL 13.20 -> 16.9
# Method: Blue/Green Deployment
################################################################################

set -e
set -o pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="upgrade_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

################################################################################
# CONFIGURATION - CUSTOMIZE THESE VALUES
################################################################################

# AWS Configuration
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="123456789012"
export CLUSTER_NAME="your-prod-cluster-name"
export PG16_PARAMETER_GROUP="aurora-postgresql16-params"
export INSTANCE_CLASS="db.r6g.xlarge"

# Upgrade Configuration
export SOURCE_VERSION="13.20"
export TARGET_VERSION="16.9"
export TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Notification Configuration (optional)
export SLACK_WEBHOOK_URL=""  # Add your Slack webhook if you have one
export PAGERDUTY_KEY=""       # Add your PagerDuty integration key

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

send_notification() {
    local message="$1"
    log_info "Notification: $message"
    
    # Send to Slack if configured
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" 2>/dev/null || true
    fi
}

confirm_action() {
    local prompt="$1"
    local expected="$2"
    read -p "$(echo -e ${YELLOW}$prompt${NC}) " response
    if [ "$response" != "$expected" ]; then
        log_error "Action cancelled by user"
        exit 1
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured properly"
        exit 1
    fi
    
    # Check if cluster exists
    if ! aws rds describe-db-clusters --db-cluster-identifier "$CLUSTER_NAME" &> /dev/null; then
        log_error "Cluster $CLUSTER_NAME not found"
        exit 1
    fi
    
    # Check current version
    CURRENT_VERSION=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].EngineVersion' \
        --output text)
    
    if [ "$CURRENT_VERSION" != "$SOURCE_VERSION" ]; then
        log_warn "Current version is $CURRENT_VERSION, expected $SOURCE_VERSION"
        confirm_action "Continue anyway? Type 'YES' to proceed: " "YES"
    fi
    
    log_info "Prerequisites check passed ✓"
}

create_snapshot() {
    log_info "Creating pre-upgrade snapshot..."
    
    SNAPSHOT_ID="${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"
    
    aws rds create-db-cluster-snapshot \
        --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --tags \
            Key=Purpose,Value=PreUpgradeBackup \
            Key=SourceVersion,Value=$SOURCE_VERSION \
            Key=TargetVersion,Value=$TARGET_VERSION \
            Key=Timestamp,Value=$TIMESTAMP
    
    log_info "Waiting for snapshot to complete..."
    aws rds wait db-cluster-snapshot-available \
        --db-cluster-snapshot-identifier "$SNAPSHOT_ID"
    
    log_info "Snapshot created successfully: $SNAPSHOT_ID ✓"
    send_notification "✅ Pre-upgrade snapshot created: $SNAPSHOT_ID"
}

capture_metrics() {
    log_info "Capturing pre-upgrade metrics..."
    
    # Database connections
    aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name DatabaseConnections \
        --dimensions Name=DBClusterIdentifier,Value=$CLUSTER_NAME \
        --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 \
        --statistics Average,Maximum \
        > "pre_upgrade_connections_${TIMESTAMP}.json"
    
    # CPU Utilization
    aws cloudwatch get-metric-statistics \
        --namespace AWS/RDS \
        --metric-name CPUUtilization \
        --dimensions Name=DBClusterIdentifier,Value=$CLUSTER_NAME \
        --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 300 \
        --statistics Average,Maximum \
        > "pre_upgrade_cpu_${TIMESTAMP}.json"
    
    log_info "Metrics captured ✓"
}

create_bluegreen() {
    log_info "Creating Blue/Green deployment..."
    send_notification "🔵🟢 Starting Blue/Green deployment for PostgreSQL 16.9 upgrade"
    
    DEPLOYMENT_ID=$(aws rds create-blue-green-deployment \
        --blue-green-deployment-name "${CLUSTER_NAME}-pg16-production" \
        --source-arn "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster:${CLUSTER_NAME}" \
        --target-engine-version "$TARGET_VERSION" \
        --target-db-parameter-group-name "$PG16_PARAMETER_GROUP" \
        --tags \
            Key=Environment,Value=Production \
            Key=Upgrade,Value=13-to-16 \
            Key=Timestamp,Value=$TIMESTAMP \
        --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
        --output text)
    
    if [ -z "$DEPLOYMENT_ID" ]; then
        log_error "Failed to create Blue/Green deployment"
        exit 1
    fi
    
    log_info "Blue/Green deployment created: $DEPLOYMENT_ID ✓"
    echo "$DEPLOYMENT_ID" > "deployment_id_${TIMESTAMP}.txt"
}

wait_for_green() {
    log_info "Waiting for Green environment to be ready (this may take 15-30 minutes)..."
    
    local max_wait=3600  # 1 hour max
    local elapsed=0
    local sleep_time=60
    
    while [ $elapsed -lt $max_wait ]; do
        STATUS=$(aws rds describe-blue-green-deployments \
            --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
            --query 'BlueGreenDeployments[0].Status' \
            --output text)
        
        log_info "Current status: $STATUS (${elapsed}s elapsed)"
        
        case $STATUS in
            AVAILABLE)
                log_info "Green environment is ready! ✓"
                return 0
                ;;
            FAILED)
                log_error "Deployment failed!"
                exit 1
                ;;
            *)
                sleep $sleep_time
                elapsed=$((elapsed + sleep_time))
                ;;
        esac
    done
    
    log_error "Timeout waiting for Green environment"
    exit 1
}

get_green_endpoint() {
    log_info "Retrieving Green environment endpoint..."
    
    GREEN_ENDPOINT=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
        --query 'BlueGreenDeployments[0].Target' \
        --output text)
    
    if [ -z "$GREEN_ENDPOINT" ]; then
        log_error "Failed to get Green endpoint"
        exit 1
    fi
    
    log_info "Green endpoint: $GREEN_ENDPOINT ✓"
    echo "$GREEN_ENDPOINT" > "green_endpoint_${TIMESTAMP}.txt"
}

validate_green() {
    log_info "Validation phase - Please test the Green environment"
    log_warn "Green Endpoint: $GREEN_ENDPOINT"
    log_warn "Deployment ID: $DEPLOYMENT_ID"
    echo ""
    echo "=========================================="
    echo "VALIDATION CHECKLIST:"
    echo "=========================================="
    echo ""
    echo "Please perform these validations:"
    echo "1. Connect to Green endpoint and verify version"
    echo "   psql -h $GREEN_ENDPOINT -U your_user -c 'SELECT version();'"
    echo ""
    echo "2. Check extensions loaded:"
    echo "   psql -h $GREEN_ENDPOINT -U your_user -c 'SELECT * FROM pg_extension;'"
    echo ""
    echo "3. Run your smoke tests against Green endpoint"
    echo ""
    echo "4. Test application connectivity"
    echo ""
    echo "5. Run sample queries and check performance"
    echo ""
    echo "=========================================="
    echo ""
}

perform_switchover() {
    log_info "Ready to perform switchover"
    log_warn "This will cause brief downtime (2-5 minutes)"
    
    confirm_action "Type 'SWITCHOVER' to proceed, or 'ABORT' to cancel: " "SWITCHOVER"
    
    log_info "Starting switchover in 10 seconds... Press Ctrl+C to abort."
    sleep 10
    
    send_notification "⚠️ Starting database switchover - brief downtime expected"
    
    aws rds switchover-blue-green-deployment \
        --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
        --switchover-timeout 300
    
    log_info "Switchover initiated, monitoring progress..."
}

wait_for_switchover() {
    log_info "Waiting for switchover to complete..."
    
    local max_wait=600  # 10 minutes max
    local elapsed=0
    local sleep_time=30
    
    while [ $elapsed -lt $max_wait ]; do
        STATUS=$(aws rds describe-blue-green-deployments \
            --blue-green-deployment-identifier "$DEPLOYMENT_ID" \
            --query 'BlueGreenDeployments[0].Status' \
            --output text)
        
        log_info "Switchover status: $STATUS"
        
        case $STATUS in
            SWITCHOVER_COMPLETED)
                log_info "Switchover completed successfully! ✓"
                return 0
                ;;
            SWITCHOVER_FAILED)
                log_error "Switchover failed!"
                exit 1
                ;;
            *)
                sleep $sleep_time
                elapsed=$((elapsed + sleep_time))
                ;;
        esac
    done
    
    log_error "Timeout waiting for switchover"
    exit 1
}

verify_upgrade() {
    log_info "Verifying upgrade..."
    
    # Get new version
    NEW_VERSION=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].EngineVersion' \
        --output text)
    
    if [ "$NEW_VERSION" == "$TARGET_VERSION" ]; then
        log_info "Cluster is now running version: $NEW_VERSION ✓"
        send_notification "✅ Aurora PostgreSQL upgrade completed successfully! Now running $NEW_VERSION"
    else
        log_error "Version mismatch! Expected $TARGET_VERSION, got $NEW_VERSION"
        exit 1
    fi
    
    # Get cluster endpoint
    CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
        --db-cluster-identifier "$CLUSTER_NAME" \
        --query 'DBClusters[0].Endpoint' \
        --output text)
    
    log_info "Production endpoint: $CLUSTER_ENDPOINT"
}

post_upgrade_checks() {
    log_info "Post-upgrade validation..."
    
    echo ""
    echo "=========================================="
    echo "POST-UPGRADE CHECKLIST:"
    echo "=========================================="
    echo ""
    echo "Immediate checks (next 15 minutes):"
    echo "1. Verify database version:"
    echo "   psql -h $CLUSTER_ENDPOINT -U your_user -c 'SELECT version();'"
    echo ""
    echo "2. Check extensions:"
    echo "   psql -h $CLUSTER_ENDPOINT -U your_user -c 'SELECT * FROM pg_extension;'"
    echo ""
    echo "3. Run ANALYZE:"
    echo "   psql -h $CLUSTER_ENDPOINT -U your_user -c 'ANALYZE VERBOSE;'"
    echo ""
    echo "4. Monitor application logs for errors"
    echo ""
    echo "5. Check CloudWatch metrics:"
    echo "   - Database Connections"
    echo "   - CPU Utilization"
    echo "   - Read/Write Latency"
    echo ""
    echo "Extended monitoring (next 2-4 hours):"
    echo "- Application error rates"
    echo "- Query performance"
    echo "- Connection pool behavior"
    echo ""
    echo "=========================================="
    echo ""
    
    log_warn "The old Blue environment will be retained for 24-48 hours for emergency rollback"
    log_warn "To delete it after validation:"
    log_warn "  aws rds delete-blue-green-deployment --blue-green-deployment-identifier $DEPLOYMENT_ID --delete-target"
}

generate_summary() {
    log_info "Generating upgrade summary..."
    
    cat > "upgrade_summary_${TIMESTAMP}.txt" << EOF
========================================
Aurora PostgreSQL Upgrade Summary
========================================

Date: $(date)
Cluster: $CLUSTER_NAME
Source Version: $SOURCE_VERSION
Target Version: $TARGET_VERSION

Snapshot ID: $SNAPSHOT_ID
Deployment ID: $DEPLOYMENT_ID
Green Endpoint: $GREEN_ENDPOINT
Production Endpoint: $CLUSTER_ENDPOINT

Log File: $LOG_FILE
Metrics Files:
  - pre_upgrade_connections_${TIMESTAMP}.json
  - pre_upgrade_cpu_${TIMESTAMP}.json

Status: SUCCESS

Next Steps:
1. Monitor for 24-48 hours
2. Run ANALYZE on all tables
3. Update table statistics if needed
4. Delete Blue/Green deployment after validation period
5. Update documentation

Rollback Command (if needed within 48 hours):
aws rds switchover-blue-green-deployment \\
  --blue-green-deployment-identifier $DEPLOYMENT_ID

========================================
EOF

    cat "upgrade_summary_${TIMESTAMP}.txt"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    echo "=========================================="
    echo "Aurora PostgreSQL Upgrade Script"
    echo "=========================================="
    echo "Cluster: $CLUSTER_NAME"
    echo "Upgrade: $SOURCE_VERSION -> $TARGET_VERSION"
    echo "Method: Blue/Green Deployment"
    echo "Log: $LOG_FILE"
    echo "=========================================="
    echo ""
    
    # Pre-flight checks
    check_prerequisites
    
    # Confirmation
    log_warn "This script will upgrade $CLUSTER_NAME to PostgreSQL $TARGET_VERSION"
    confirm_action "Type 'START' to begin the upgrade: " "START"
    
    # Step 1: Create snapshot
    create_snapshot
    
    # Step 2: Capture baseline metrics
    capture_metrics
    
    # Step 3: Create Blue/Green deployment
    create_bluegreen
    
    # Step 4: Wait for Green environment
    wait_for_green
    
    # Step 5: Get Green endpoint
    get_green_endpoint
    
    # Step 6: Validation phase
    validate_green
    confirm_action "After validation, type 'VALIDATED' to proceed: " "VALIDATED"
    
    # Step 7: Perform switchover
    perform_switchover
    
    # Step 8: Wait for switchover
    wait_for_switchover
    
    # Step 9: Verify upgrade
    verify_upgrade
    
    # Step 10: Post-upgrade guidance
    post_upgrade_checks
    
    # Generate summary
    generate_summary
    
    log_info "Upgrade completed successfully! ✓"
    send_notification "🎉 Aurora PostgreSQL upgrade to 16.9 completed successfully!"
}

# Trap errors
trap 'log_error "Script failed at line $LINENO"' ERR

# Run main function
main

exit 0

