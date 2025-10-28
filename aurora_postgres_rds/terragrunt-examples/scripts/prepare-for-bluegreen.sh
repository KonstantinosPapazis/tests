#!/bin/bash
# prepare-for-bluegreen.sh

CLUSTER_NAME="prod-aurora-serverless-postgres"
AWS_REGION="us-east-1"

echo "=========================================="
echo "Preparing Cluster for Blue/Green Upgrade"
echo "=========================================="
echo ""

# Check current capacity
echo "Step 1: Checking current capacity..."
CURRENT_MIN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].ServerlessV2ScalingConfiguration.MinCapacity' \
    --output text)

echo "Current minimum capacity: ${CURRENT_MIN} ACU"

# Check if scaling needed
if (( $(echo "$CURRENT_MIN >= 1.0" | bc -l) )); then
    echo "✓ Minimum capacity is already >= 1.0 ACU"
    echo "No scaling needed!"
else
    echo "⚠ Minimum capacity is ${CURRENT_MIN} ACU (below required 1.0)"
    echo ""
    echo "Step 2: Scaling to 1.0 ACU minimum..."
    echo "This is an ONLINE operation with ZERO downtime"
    echo ""
    
    # Scale up
    aws rds modify-db-cluster \
        --db-cluster-identifier "${CLUSTER_NAME}" \
        --serverless-v2-scaling-configuration MinCapacity=1.0,MaxCapacity=16 \
        --apply-immediately \
        --region "${AWS_REGION}"
    
    echo "Scaling initiated..."
    echo ""
    echo "Step 3: Waiting for modification to complete..."
    
    # Wait for modification
    aws rds wait db-cluster-available \
        --db-cluster-identifier "${CLUSTER_NAME}" \
        --region "${AWS_REGION}"
    
    echo "✓ Scaling complete!"
fi

# Verify final state
echo ""
echo "Step 4: Verifying configuration..."
FINAL_MIN=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].ServerlessV2ScalingConfiguration.MinCapacity' \
    --output text)

echo "Final minimum capacity: ${FINAL_MIN} ACU"

if (( $(echo "$FINAL_MIN >= 1.0" | bc -l) )); then
    echo ""
    echo "=========================================="
    echo "✓ Cluster is ready for Blue/Green upgrade!"
    echo "=========================================="
    echo ""
    echo "Next step: Run the Blue/Green deployment"
    echo "  cd terragrunt-examples/scripts"
    echo "  ./upgrade-bluegreen.sh"
else
    echo ""
    echo "✗ Scaling failed. Current minimum: ${FINAL_MIN}"
    exit 1
fi