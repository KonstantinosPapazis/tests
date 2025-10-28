#!/bin/bash
################################################################################
# Blue/Green Rollback Script
# Rolls back to PostgreSQL 13.20 if issues are found
#
# Usage: ./upgrade-bluegreen-rollback.sh [deployment-id]
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

if [ -z "${DEPLOYMENT_ID}" ]; then
    print_error "No deployment ID provided or found in bluegreen_deployment_id.txt"
    echo "Usage: $0 [deployment-id]"
    exit 1
fi

echo "=========================================="
echo "BLUE/GREEN ROLLBACK"
echo "=========================================="
echo ""

# Get deployment status
echo "Checking deployment status..."
DEPLOYMENT_INFO=$(aws rds describe-blue-green-deployments \
    --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
    --region "${AWS_REGION}")

STATUS=$(echo "${DEPLOYMENT_INFO}" | jq -r '.BlueGreenDeployments[0].Status')
SOURCE_ARN=$(echo "${DEPLOYMENT_INFO}" | jq -r '.BlueGreenDeployments[0].Source')
TARGET_ARN=$(echo "${DEPLOYMENT_INFO}" | jq -r '.BlueGreenDeployments[0].Target')

BLUE_CLUSTER=$(basename "${SOURCE_ARN}")
GREEN_CLUSTER=$(basename "${TARGET_ARN}")

echo "Deployment ID: ${DEPLOYMENT_ID}"
echo "Status: ${STATUS}"
echo "Blue Cluster: ${BLUE_CLUSTER}"
echo "Green Cluster: ${GREEN_CLUSTER}"
echo ""

# Determine rollback scenario
if [ "${STATUS}" == "AVAILABLE" ]; then
    echo "=========================================="
    echo "SCENARIO: Pre-Switchover Rollback"
    echo "=========================================="
    echo ""
    print_warning "Green environment exists but has NOT been switched to production"
    echo ""
    echo "Action: Delete green environment"
    echo "Impact: None - production is unchanged"
    echo ""
    read -p "Type 'DELETE' to remove the green environment: " confirm
    
    if [ "$confirm" != "DELETE" ]; then
        print_error "Rollback cancelled"
        exit 0
    fi
    
    echo ""
    echo "Deleting green environment..."
    aws rds delete-blue-green-deployment \
        --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
        --delete-target \
        --region "${AWS_REGION}"
    
    print_success "Green environment deletion initiated"
    print_success "Production remains on original cluster (${BLUE_CLUSTER})"
    
elif [ "${STATUS}" == "SWITCHOVER_COMPLETED" ]; then
    echo "=========================================="
    echo "SCENARIO: Post-Switchover Rollback"
    echo "=========================================="
    echo ""
    print_warning "Production has been switched to PostgreSQL 16.8"
    echo ""
    
    # Get current versions
    CURRENT_VERSION=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${BLUE_CLUSTER}" \
        --region "${AWS_REGION}" \
        --query 'DBClusters[0].EngineVersion' \
        --output text)
    
    echo "Current Production Version: ${CURRENT_VERSION}"
    echo ""
    echo "Action: Switch back to previous version"
    echo "Impact: 15-30 seconds downtime"
    echo ""
    print_warning "⚠️  CRITICAL: This will reverse the upgrade"
    echo ""
    read -p "Type 'ROLLBACK' to switch back to the old version: " confirm
    
    if [ "$confirm" != "ROLLBACK" ]; then
        print_error "Rollback cancelled"
        exit 0
    fi
    
    # Final confirmation
    echo ""
    print_warning "Starting rollback in:"
    for i in 5 4 3 2 1; do
        echo "  ${i}..."
        sleep 1
    done
    
    echo ""
    echo "Executing switchback..."
    
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    
    # Perform switchback
    aws rds switchover-blue-green-deployment \
        --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
        --switchover-timeout 300 \
        --region "${AWS_REGION}"
    
    # Monitor switchback
    echo ""
    echo "Monitoring switchback progress..."
    
    WAIT_COUNT=0
    MAX_WAIT=120
    
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        CURRENT_STATUS=$(aws rds describe-blue-green-deployments \
            --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
            --region "${AWS_REGION}" \
            --query 'BlueGreenDeployments[0].Status' \
            --output text)
        
        echo "[$(date +%H:%M:%S)] Status: ${CURRENT_STATUS}"
        
        if [ "$CURRENT_STATUS" == "AVAILABLE" ]; then
            echo ""
            print_success "=========================================="
            print_success "ROLLBACK COMPLETED SUCCESSFULLY!"
            print_success "=========================================="
            break
        elif [ "$CURRENT_STATUS" == "SWITCHOVER_FAILED" ]; then
            echo ""
            print_error "Switchback failed!"
            exit 1
        fi
        
        sleep 5
        ((WAIT_COUNT++))
    done
    
    if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
        print_error "Timeout waiting for switchback!"
        exit 1
    fi
    
    # Verify rollback
    ROLLED_BACK_VERSION=$(aws rds describe-db-clusters \
        --db-cluster-identifier "${BLUE_CLUSTER}" \
        --region "${AWS_REGION}" \
        --query 'DBClusters[0].EngineVersion' \
        --output text)
    
    echo ""
    print_success "Production has been rolled back to: PostgreSQL ${ROLLED_BACK_VERSION}"
    
    # Save rollback details
    cat > "rollback-complete-${TIMESTAMP}.txt" <<EOF
Rollback Completed: $(date)
Deployment ID: ${DEPLOYMENT_ID}
Rolled Back From: ${CURRENT_VERSION}
Rolled Back To: ${ROLLED_BACK_VERSION}
Reason: Manual rollback requested
EOF
    
    echo ""
    echo "=========================================="
    echo "POST-ROLLBACK ACTIONS"
    echo "=========================================="
    echo ""
    echo "1. Verify application is working correctly"
    echo "2. Check for any data inconsistencies"
    echo "3. Document what issues caused the rollback"
    echo "4. Plan next upgrade attempt with fixes"
    echo ""
    print_warning "Note: You can keep the blue/green deployment for investigation"
    echo "Or delete it with:"
    echo "  aws rds delete-blue-green-deployment \\"
    echo "    --blue-green-deployment-identifier ${DEPLOYMENT_ID} \\"
    echo "    --delete-target"
    
else
    print_error "Unknown deployment status: ${STATUS}"
    print_error "Cannot perform automated rollback"
    echo ""
    echo "Manual intervention required. Contact AWS Support if needed."
    exit 1
fi

echo ""
print_success "Rollback operation complete"

