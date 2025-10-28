#!/bin/bash
################################################################################
# Aurora PostgreSQL Blue/Green Upgrade Script
# Upgrades from version 13.20 to 16.8 using Blue/Green deployment
#
# Usage: ./upgrade-bluegreen.sh
################################################################################

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration - UPDATE THESE VALUES
CLUSTER_NAME="${CLUSTER_NAME:-prod-aurora-serverless-postgres}"
TARGET_VERSION="${TARGET_VERSION:-16.8}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PARAM_GROUP="${PARAM_GROUP:-}"  # Will be auto-created if empty
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Logging
LOG_FILE="upgrade-bluegreen-${TIMESTAMP}.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=========================================="
echo "Aurora PostgreSQL Blue/Green Upgrade"
echo "=========================================="
echo "Cluster: ${CLUSTER_NAME}"
echo "Target Version: ${TARGET_VERSION}"
echo "Region: ${AWS_REGION}"
echo "Timestamp: ${TIMESTAMP}"
echo "Log File: ${LOG_FILE}"
echo "=========================================="
echo ""

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
print_success "AWS Account ID: ${AWS_ACCOUNT_ID}"

# Verify cluster exists
echo ""
echo "Step 0: Verifying cluster exists..."
CURRENT_VERSION=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].EngineVersion' \
    --output text 2>/dev/null) || {
    print_error "Cluster ${CLUSTER_NAME} not found!"
    exit 1
}

print_success "Found cluster ${CLUSTER_NAME}"
echo "Current version: ${CURRENT_VERSION}"

# Step 1: Create final pre-upgrade snapshot
echo ""
echo "Step 1: Creating pre-upgrade snapshot..."
SNAPSHOT_ID="${CLUSTER_NAME}-before-pg16-${TIMESTAMP}"

aws rds create-db-cluster-snapshot \
    --db-cluster-snapshot-identifier "${SNAPSHOT_ID}" \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --tags Key=UpgradeFrom,Value="${CURRENT_VERSION}" \
           Key=UpgradeTo,Value="${TARGET_VERSION}" \
           Key=Timestamp,Value="${TIMESTAMP}"

echo "Waiting for snapshot to complete (this may take 5-15 minutes)..."
aws rds wait db-cluster-snapshot-available \
    --db-cluster-snapshot-identifier "${SNAPSHOT_ID}" \
    --region "${AWS_REGION}"

print_success "Snapshot created: ${SNAPSHOT_ID}"

# Step 2: Create or verify parameter group
echo ""
echo "Step 2: Setting up parameter group..."

if [ -z "${PARAM_GROUP}" ]; then
    # Auto-generate parameter group name
    PARAM_GROUP="${CLUSTER_NAME}-pg16-params"
fi

# Check if parameter group exists
if aws rds describe-db-cluster-parameter-groups \
    --db-cluster-parameter-group-name "${PARAM_GROUP}" \
    --region "${AWS_REGION}" &>/dev/null; then
    print_success "Parameter group ${PARAM_GROUP} already exists"
else
    echo "Creating parameter group: ${PARAM_GROUP}"
    aws rds create-db-cluster-parameter-group \
        --db-cluster-parameter-group-name "${PARAM_GROUP}" \
        --db-parameter-group-family aurora-postgresql16 \
        --description "Aurora PostgreSQL 16 parameters for ${CLUSTER_NAME}" \
        --region "${AWS_REGION}"
    print_success "Parameter group created: ${PARAM_GROUP}"
fi

# Step 3: Create Blue/Green deployment
echo ""
echo "Step 3: Creating Blue/Green deployment..."
DEPLOYMENT_NAME="${CLUSTER_NAME}-to-pg16-${TIMESTAMP}"
SOURCE_ARN="arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster:${CLUSTER_NAME}"

DEPLOYMENT_ID=$(aws rds create-blue-green-deployment \
    --blue-green-deployment-name "${DEPLOYMENT_NAME}" \
    --source-arn "${SOURCE_ARN}" \
    --target-engine-version "${TARGET_VERSION}" \
    --target-db-cluster-parameter-group-name "${PARAM_GROUP}" \
    --region "${AWS_REGION}" \
    --tags Key=Purpose,Value=MajorVersionUpgrade \
           Key=SourceVersion,Value="${CURRENT_VERSION}" \
           Key=TargetVersion,Value="${TARGET_VERSION}" \
    --query 'BlueGreenDeployment.BlueGreenDeploymentIdentifier' \
    --output text)

print_success "Blue/Green Deployment created"
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo "${DEPLOYMENT_ID}" > bluegreen_deployment_id.txt

# Step 4: Monitor deployment creation
echo ""
echo "Step 4: Waiting for green environment to be ready..."
echo "This typically takes 15-25 minutes. Status will be checked every minute."
echo ""

WAIT_COUNT=0
MAX_WAIT=60  # 60 minutes max

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    STATUS=$(aws rds describe-blue-green-deployments \
        --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
        --region "${AWS_REGION}" \
        --query 'BlueGreenDeployments[0].Status' \
        --output text)
    
    echo "[$(date +%H:%M:%S)] Status: ${STATUS}"
    
    if [ "$STATUS" == "AVAILABLE" ]; then
        echo ""
        print_success "Green environment is ready for testing!"
        break
    elif [ "$STATUS" == "FAILED" ]; then
        echo ""
        print_error "Deployment failed!"
        
        # Get failure message
        FAILURE_MSG=$(aws rds describe-blue-green-deployments \
            --blue-green-deployment-identifier "${DEPLOYMENT_ID}" \
            --region "${AWS_REGION}" \
            --query 'BlueGreenDeployments[0].StatusDetails' \
            --output text)
        
        echo "Failure reason: ${FAILURE_MSG}"
        exit 1
    fi
    
    sleep 60
    ((WAIT_COUNT++))
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    print_error "Timeout waiting for green environment!"
    exit 1
fi

# Step 5: Get green cluster information
echo ""
echo "Step 5: Retrieving green cluster information..."

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

GREEN_READER_ENDPOINT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${GREEN_CLUSTER_ID}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].ReaderEndpoint' \
    --output text)

# Save to file
cat > green_cluster_info.txt <<EOF
Deployment ID: ${DEPLOYMENT_ID}
Green Cluster ID: ${GREEN_CLUSTER_ID}
Green Writer Endpoint: ${GREEN_ENDPOINT}
Green Reader Endpoint: ${GREEN_READER_ENDPOINT}
Created: ${TIMESTAMP}
Source Version: ${CURRENT_VERSION}
Target Version: ${TARGET_VERSION}
EOF

echo ""
echo "=========================================="
print_success "GREEN ENVIRONMENT READY FOR TESTING"
echo "=========================================="
echo ""
echo "Blue (Production) Cluster: ${CLUSTER_NAME}"
echo "  Version: ${CURRENT_VERSION}"
echo "  (Still serving production traffic)"
echo ""
echo "Green (Test) Cluster: ${GREEN_CLUSTER_ID}"
echo "  Version: ${TARGET_VERSION}"
echo "  Writer Endpoint: ${GREEN_ENDPOINT}"
echo "  Reader Endpoint: ${GREEN_READER_ENDPOINT}"
echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Test your application against green endpoint:"
echo "   export DATABASE_HOST=${GREEN_ENDPOINT}"
echo "   # Run your test suite"
echo ""
echo "2. Run validation queries:"
echo "   ./test-green-environment.sh"
echo ""
echo "3. When ready to switch to production:"
echo "   ./upgrade-bluegreen-switchover.sh"
echo ""
echo "4. To cancel/rollback:"
echo "   ./upgrade-bluegreen-rollback.sh"
echo ""
echo "=========================================="
echo "FILES CREATED"
echo "=========================================="
echo "  bluegreen_deployment_id.txt - Deployment ID"
echo "  green_cluster_info.txt - Green cluster details"
echo "  ${LOG_FILE} - Complete log"
echo ""
print_success "Blue/Green deployment setup complete!"

