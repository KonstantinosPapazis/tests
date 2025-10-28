#!/bin/bash
################################################################################
# Blue/Green Switchover Script
# Switches production traffic to the upgraded PostgreSQL 16.8 cluster
#
# Usage: ./upgrade-bluegreen-switchover.sh [deployment-id]
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# Configuration
DEPLOYMENT_ID="${1:-$(cat bluegreen_deployment_id.txt 2>/dev/null)}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SWITCHOVER_TIMEOUT="${SWITCHOVER_TIMEOUT:-300}"

if [ -z "${DEPLOYMENT_ID}" ]; then
    print_error "No deployment ID provided or found in bluegreen_deployment_id.txt"
    echo "Usage: $0 [deployment-id]"
    exit 1
fi

echo "=========================================="
echo "PRODUCTION SWITCHOVER TO POSTGRESQL 16.8"
echo "=========================================="
echo ""
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo ""

# Get deployment information
echo "Retrieving deployment information..."
DEPLOYMENT_INFO=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --region "${AWS_REGION}")

SOURCE_ARN=$(echo "${DEPLOYMENT_INFO}" | jq -r '.BlueGreenDeployments[0].Source')
TARGET_ARN=$(echo "${DEPLOYMENT_INFO}" | jq -r '.BlueGreenDeployments[0].Target')
STATUS=$(echo "${DEPLOYMENT_INFO}" | jq -r '.BlueGreenDeployments[0].Status')

BLUE_CLUSTER=$(basename "${SOURCE_ARN}")
GREEN_CLUSTER=$(basename "${TARGET_ARN}")

echo ""
echo "Blue (Current Production): ${BLUE_CLUSTER}"
echo "Green (New Version): ${GREEN_CLUSTER}"
echo "Status: ${STATUS}"
echo ""

# Verify status
if [ "${STATUS}" != "AVAILABLE" ]; then
    print_error "Deployment status is not AVAILABLE (current: ${STATUS})"
    print_error "Cannot proceed with switchover"
    exit 1
fi

# Get current versions
BLUE_VERSION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${BLUE_CLUSTER}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].EngineVersion' \
    --output text)

GREEN_VERSION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${GREEN_CLUSTER}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].EngineVersion' \
    --output text)

echo "Version Upgrade: ${BLUE_VERSION} → ${GREEN_VERSION}"
echo ""

# Warning prompt
print_warning "=========================================="
print_warning "⚠️  CRITICAL WARNING"
print_warning "=========================================="
echo ""
echo "This will switch production traffic from:"
echo "  ${BLUE_CLUSTER} (v${BLUE_VERSION})"
echo "to:"
echo "  ${GREEN_CLUSTER} (v${GREEN_VERSION})"
echo ""
echo "Expected downtime: 15-30 seconds"
echo ""
echo "Make sure you have:"
echo "  ✓ Tested the green environment thoroughly"
echo "  ✓ Validated all application functionality"
echo "  ✓ Notified stakeholders"
echo "  ✓ Prepared rollback procedure"
echo "  ✓ Monitoring dashboard ready"
echo ""
echo "=========================================="
echo ""
read -p "Type 'SWITCHOVER' to proceed: " confirm

if [ "$confirm" != "SWITCHOVER" ]; then
    print_error "Switchover cancelled"
    exit 0
fi

# Final confirmation with countdown
echo ""
print_warning "Starting switchover in:"
for i in 5 4 3 2 1; do
    echo "  ${i}..."
    sleep 1
done

echo ""
echo "=========================================="
echo "Initiating Switchover"
echo "=========================================="
echo ""

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="switchover-${TIMESTAMP}.log"

# Capture metrics before switchover
echo "Capturing pre-switchover metrics..."
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBClusterIdentifier,Value="${BLUE_CLUSTER}" \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    > "pre-switchover-metrics-${TIMESTAMP}.json"

# Perform switchover
echo ""
echo "Executing switchover (timeout: ${SWITCHOVER_TIMEOUT} seconds)..."
echo ""

aws rds switchover-blue-green-deployment \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --switchover-timeout "${SWITCHOVER_TIMEOUT}" \
    --region "${AWS_REGION}"

# Monitor switchover progress
echo ""
echo "Monitoring switchover progress..."
echo "This typically takes 15-30 seconds"
echo ""

WAIT_COUNT=0
MAX_WAIT=120  # 2 minutes max

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    CURRENT_STATUS=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
        --region "${AWS_REGION}" \
        --query 'BlueGreenDeployments[0].Status' \
        --output text)
    
    echo "[$(date +%H:%M:%S)] Status: ${CURRENT_STATUS}"
    
    if [ "$CURRENT_STATUS" == "SWITCHOVER_COMPLETED" ]; then
        echo ""
        print_success "=========================================="
        print_success "SWITCHOVER COMPLETED SUCCESSFULLY!"
        print_success "=========================================="
        break
    elif [ "$CURRENT_STATUS" == "SWITCHOVER_FAILED" ]; then
        echo ""
        print_error "=========================================="
        print_error "SWITCHOVER FAILED!"
        print_error "=========================================="
        
        # Get failure details
        FAILURE=$(aws rds describe-blue-green-deployments \
            --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
            --region "${AWS_REGION}" \
            --query 'BlueGreenDeployments[0].StatusDetails' \
            --output text)
        
        echo ""
        echo "Failure reason: ${FAILURE}"
        echo ""
        print_error "Production traffic remains on blue (old) cluster"
        exit 1
    fi
    
    sleep 5
    ((WAIT_COUNT++))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    print_error "Timeout waiting for switchover!"
    exit 1
fi

# Verify the swap
echo ""
echo "Verifying switchover..."

# The clusters swap identities, so check the original cluster name
NEW_VERSION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${BLUE_CLUSTER}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].EngineVersion' \
    --output text)

echo "Production cluster (${BLUE_CLUSTER}) is now running: PostgreSQL ${NEW_VERSION}"

if echo "${NEW_VERSION}" | grep -q "^16\."; then
    print_success "Version verification passed"
else
    print_warning "Version verification inconclusive: ${NEW_VERSION}"
fi

# Get new endpoint (should be same, but verify)
NEW_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${BLUE_CLUSTER}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].Endpoint' \
    --output text)

echo "Production endpoint: ${NEW_ENDPOINT}"

# Save switchover details
cat > "switchover-complete-${TIMESTAMP}.txt" <<EOF
Switchover Completed: $(date)
Deployment ID: ${DEPLOYMENT_ID}
Production Cluster: ${BLUE_CLUSTER}
PostgreSQL Version: ${NEW_VERSION}
Endpoint: ${NEW_ENDPOINT}
Previous Version: ${BLUE_VERSION}
EOF

echo ""
echo "=========================================="
echo "POST-SWITCHOVER ACTIONS"
echo "=========================================="
echo ""
print_success "Production is now running PostgreSQL ${NEW_VERSION}"
echo ""
echo "IMMEDIATE (Next 30 minutes):"
echo "  1. Monitor application error rates"
echo "  2. Check CloudWatch alarms"
echo "  3. Verify database connections"
echo "  4. Test critical user workflows"
echo ""
echo "SHORT-TERM (Next 2-4 hours):"
echo "  5. Monitor query performance"
echo "  6. Check application logs for errors"
echo "  7. Verify backup processes"
echo "  8. Monitor resource utilization"
echo ""
echo "WITHIN 24 HOURS:"
echo "  9. Full application regression testing"
echo "  10. Review all monitoring dashboards"
echo "  11. Document any issues found"
echo ""
echo "=========================================="
echo "ROLLBACK INFORMATION"
echo "=========================================="
echo ""
print_warning "The old cluster (PostgreSQL ${BLUE_VERSION}) is retained for emergency rollback"
echo ""
echo "If critical issues occur within 24 hours:"
echo "  ./upgrade-bluegreen-rollback.sh"
echo ""
echo "After 24 hours of successful operation:"
echo "  # Delete the old blue/green deployment"
echo "  aws rds delete-blue-green-deployment \\"
echo "    --blue-green-deployment-identifier ${DEPLOYMENT_ID} \\"
echo "    --delete-target \\"
echo "    --region ${AWS_REGION}"
echo ""
echo "=========================================="
echo "MONITORING COMMANDS"
echo "=========================================="
echo ""
echo "# Check current connections"
echo "psql \"postgresql://user@${NEW_ENDPOINT}/db\" -c 'SELECT count(*) FROM pg_stat_activity;'"
echo ""
echo "# Monitor replica lag"
echo "psql \"postgresql://user@${NEW_ENDPOINT}/db\" -c 'SELECT * FROM pg_stat_replication;'"
echo ""
echo "# Watch CloudWatch metrics"
echo "aws cloudwatch get-metric-statistics \\"
echo "  --namespace AWS/RDS \\"
echo "  --metric-name CPUUtilization \\"
echo "  --dimensions Name=DBClusterIdentifier,Value=${BLUE_CLUSTER} \\"
echo "  --start-time \$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \\"
echo "  --end-time \$(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "  --period 300 --statistics Average"
echo ""
echo "=========================================="
echo "FILES CREATED"
echo "=========================================="
echo "  switchover-complete-${TIMESTAMP}.txt"
echo "  pre-switchover-metrics-${TIMESTAMP}.json"
echo ""
print_success "Switchover process complete!"
print_warning "Continue monitoring for the next 24 hours"

