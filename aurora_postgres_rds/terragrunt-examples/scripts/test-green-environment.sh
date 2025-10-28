#!/bin/bash
################################################################################
# Test Green Environment Script
# Tests the upgraded PostgreSQL 16.8 cluster before production switchover
#
# Usage: ./test-green-environment.sh [deployment-id]
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Configuration
DEPLOYMENT_ID="${1:-$(cat bluegreen_deployment_id.txt 2>/dev/null)}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-postgres}"

if [ -z "${DEPLOYMENT_ID}" ]; then
    print_error "No deployment ID provided or found in bluegreen_deployment_id.txt"
    echo "Usage: $0 [deployment-id]"
    exit 1
fi

echo "=========================================="
echo "Testing Green Environment"
echo "=========================================="
echo "Deployment ID: ${DEPLOYMENT_ID}"
echo ""

# Get green cluster information
echo "Retrieving green cluster information..."
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

GREEN_PORT=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${GREEN_CLUSTER_ID}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].Port' \
    --output text)

print_success "Green cluster found"
echo "  Cluster ID: ${GREEN_CLUSTER_ID}"
echo "  Endpoint: ${GREEN_ENDPOINT}"
echo "  Port: ${GREEN_PORT}"
echo ""

# Create connection string
CONNECTION_STRING="postgresql://${DB_USER}@${GREEN_ENDPOINT}:${GREEN_PORT}/${DB_NAME}?sslmode=require"

# Test 1: Basic Connection
echo "=========================================="
echo "Test 1: Database Connection"
echo "=========================================="

if psql "${CONNECTION_STRING}" -c "SELECT 1;" &>/dev/null; then
    print_success "Connection successful"
else
    print_error "Connection failed!"
    print_warning "Make sure:"
    echo "  - Security groups allow your IP"
    echo "  - You have the correct password"
    echo "  - psql is installed"
    echo ""
    echo "Connection string: ${CONNECTION_STRING}"
    exit 1
fi
echo ""

# Test 2: Verify PostgreSQL Version
echo "=========================================="
echo "Test 2: PostgreSQL Version"
echo "=========================================="

VERSION=$(psql "${CONNECTION_STRING}" -t -c "SHOW server_version;" | xargs)
echo "Version: ${VERSION}"

if echo "${VERSION}" | grep -q "16.8"; then
    print_success "Correct version (16.8)"
elif echo "${VERSION}" | grep -q "^16\."; then
    print_warning "Version is PostgreSQL 16, but may not be exactly 16.8"
    echo "Actual version: ${VERSION}"
else
    print_error "Wrong version! Expected 16.x, got: ${VERSION}"
fi
echo ""

# Test 3: Check Cluster Status
echo "=========================================="
echo "Test 3: Cluster Status"
echo "=========================================="

CLUSTER_STATUS=$(aws rds describe-db-clusters \
    --db-cluster-identifier "${GREEN_CLUSTER_ID}" \
    --region "${AWS_REGION}" \
    --query 'DBClusters[0].Status' \
    --output text)

echo "Cluster Status: ${CLUSTER_STATUS}"
if [ "${CLUSTER_STATUS}" == "available" ]; then
    print_success "Cluster is available"
else
    print_warning "Cluster status is: ${CLUSTER_STATUS}"
fi
echo ""

# Test 4: List Extensions
echo "=========================================="
echo "Test 4: PostgreSQL Extensions"
echo "=========================================="

echo "Installed extensions:"
psql "${CONNECTION_STRING}" -c "
    SELECT 
        extname as \"Extension\",
        extversion as \"Version\"
    FROM pg_extension 
    WHERE extname NOT IN ('plpgsql')
    ORDER BY extname;
"
echo ""

# Test 5: Check Replication
echo "=========================================="
echo "Test 5: Replication Status"
echo "=========================================="

REPLICA_COUNT=$(psql "${CONNECTION_STRING}" -t -c "
    SELECT count(*) FROM pg_stat_replication;
" | xargs)

echo "Active replicas: ${REPLICA_COUNT}"
if [ "${REPLICA_COUNT}" -gt 0 ]; then
    print_success "Replication is active"
    psql "${CONNECTION_STRING}" -c "
        SELECT 
            client_addr,
            state,
            sync_state,
            COALESCE(replay_lag::text, 'N/A') as replay_lag
        FROM pg_stat_replication;
    "
else
    print_warning "No active replicas (might be single-instance cluster)"
fi
echo ""

# Test 6: Database Size
echo "=========================================="
echo "Test 6: Database Statistics"
echo "=========================================="

psql "${CONNECTION_STRING}" -c "
    SELECT 
        datname as \"Database\",
        pg_size_pretty(pg_database_size(datname)) as \"Size\",
        numbackends as \"Connections\"
    FROM pg_stat_database
    WHERE datname NOT IN ('template0', 'template1', 'rdsadmin')
    ORDER BY pg_database_size(datname) DESC;
"
echo ""

# Test 7: Recent Activity
echo "=========================================="
echo "Test 7: Recent Activity"
echo "=========================================="

ACTIVE_CONNECTIONS=$(psql "${CONNECTION_STRING}" -t -c "
    SELECT count(*) FROM pg_stat_activity 
    WHERE state = 'active' AND pid <> pg_backend_pid();
" | xargs)

echo "Active queries: ${ACTIVE_CONNECTIONS}"
echo ""

# Test 8: Table Count
echo "=========================================="
echo "Test 8: Schema Objects"
echo "=========================================="

psql "${CONNECTION_STRING}" -c "
    SELECT 
        schemaname as \"Schema\",
        count(*) as \"Table Count\"
    FROM pg_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    GROUP BY schemaname
    ORDER BY count(*) DESC;
"
echo ""

# Test 9: Run Custom Validation SQL (if exists)
if [ -f "custom_validation.sql" ]; then
    echo "=========================================="
    echo "Test 9: Custom Validation Queries"
    echo "=========================================="
    
    echo "Running custom_validation.sql..."
    psql "${CONNECTION_STRING}" -f custom_validation.sql
    echo ""
fi

# Test 10: Performance Comparison Query
echo "=========================================="
echo "Test 10: Sample Query Performance"
echo "=========================================="

echo "Running sample query with EXPLAIN ANALYZE..."
psql "${CONNECTION_STRING}" -c "
    EXPLAIN (ANALYZE, BUFFERS) 
    SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
    FROM pg_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    LIMIT 10;
" 2>&1 | head -20
echo ""

# Summary
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo ""
print_success "Basic tests completed"
echo ""
echo "Green Cluster Details:"
echo "  Endpoint: ${GREEN_ENDPOINT}"
echo "  Port: ${GREEN_PORT}"
echo "  Version: ${VERSION}"
echo "  Status: ${CLUSTER_STATUS}"
echo ""
echo "=========================================="
echo "MANUAL TESTING CHECKLIST"
echo "=========================================="
echo ""
echo "Next, you should manually test:"
echo ""
echo "1. Application Integration Test:"
echo "   export DATABASE_HOST=${GREEN_ENDPOINT}"
echo "   export DATABASE_PORT=${GREEN_PORT}"
echo "   # Run your application test suite"
echo ""
echo "2. Critical Queries:"
echo "   # Test your most important queries"
echo "   # Compare execution plans with production"
echo ""
echo "3. Load Testing (optional):"
echo "   # Run load tests to verify performance"
echo ""
echo "4. Business Logic Validation:"
echo "   # Verify critical business operations"
echo ""
echo "=========================================="
echo "WHEN READY TO PROCEED"
echo "=========================================="
echo ""
echo "If all tests pass:"
echo "  ./upgrade-bluegreen-switchover.sh"
echo ""
echo "If issues found:"
echo "  ./upgrade-bluegreen-rollback.sh"
echo ""
print_info "The blue (production) environment remains unchanged"

