# Aurora PostgreSQL Quick Start Guide

This guide will help you deploy a production-ready Aurora PostgreSQL cluster in under 10 minutes.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0 installed
- Existing VPC with private subnets (or use our VPC module)
- S3 bucket for Terraform state (recommended for production)

## Quick Deploy: Provisioned Cluster

### 1. Clone and Navigate

```bash
cd aurora_postgres_rds/environments/production-provisioned
```

### 2. Create Configuration

```bash
cp ../../examples/terraform.tfvars.provisioned.example terraform.tfvars
```

### 3. Edit Configuration

Edit `terraform.tfvars` with your values:

```hcl
# Minimum required changes:
cluster_identifier = "my-prod-aurora"
vpc_id            = "vpc-xxxxx"          # Your VPC ID
allowed_cidr_blocks = ["10.0.0.0/16"]    # Your VPC CIDR

# Add your email for alarms
alarm_email_addresses = ["ops@example.com"]
```

### 4. Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (will take 10-15 minutes)
terraform apply
```

### 5. Get Connection Details

```bash
# Get the writer endpoint
terraform output cluster_endpoint

# Get the master password from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id $(terraform output -raw cluster_master_user_secret_arn) \
  --query SecretString \
  --output text | jq -r .password
```

### 6. Connect

```bash
psql "postgresql://postgres:PASSWORD@ENDPOINT:5432/postgres?sslmode=require"
```

## Quick Deploy: Serverless Cluster

### 1. Navigate to Serverless Environment

```bash
cd aurora_postgres_rds/environments/production-serverless
```

### 2. Create Configuration

```bash
cp ../../examples/terraform.tfvars.serverless.example terraform.tfvars
```

### 3. Edit Configuration

```hcl
# Minimum required changes:
cluster_identifier      = "my-serverless-aurora"
vpc_id                  = "vpc-xxxxx"
allowed_cidr_blocks     = ["10.0.0.0/16"]
serverless_min_capacity = 0.5
serverless_max_capacity = 16
alarm_email_addresses   = ["ops@example.com"]
```

### 4. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Post-Deployment Tasks

### 1. Confirm Alarm Subscriptions

Check your email and confirm SNS subscription for CloudWatch alarms.

### 2. Test Connection

```bash
# Using psql
psql "postgresql://USERNAME@ENDPOINT:5432/DATABASE?sslmode=require"

# Using Python
pip install psycopg2-binary
python -c "import psycopg2; conn = psycopg2.connect('postgresql://USER@HOST:5432/DB?sslmode=require')"
```

### 3. Verify High Availability

```bash
# Check cluster instances
aws rds describe-db-cluster-members \
  --db-cluster-identifier $(terraform output -raw cluster_identifier)

# Should show multiple instances in different AZs
```

### 4. Review Monitoring

- Open CloudWatch Console
- Navigate to RDS → Your Cluster
- Check Performance Insights
- Verify alarms are created

### 5. Create Initial Database Objects

```sql
-- Connect to the database
\c myapp

-- Create application user
CREATE ROLE app_user WITH LOGIN PASSWORD 'secure_password';

-- Create application database
CREATE DATABASE myapp_db OWNER app_user;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE myapp_db TO app_user;
```

## Common Configurations

### Development Environment

```hcl
cluster_identifier              = "dev-aurora"
instance_count                  = 1  # Single instance
instance_class                  = "db.r6g.large"  # For provisioned
serverless_min_capacity         = 0.5  # For serverless
serverless_max_capacity         = 4    # For serverless
backup_retention_period         = 7
deletion_protection             = false
enable_performance_insights     = false
```

### Production Environment

```hcl
cluster_identifier              = "prod-aurora"
instance_count                  = 2  # Multi-AZ
instance_class                  = "db.r6g.xlarge"  # For provisioned
serverless_min_capacity         = 1    # For serverless
serverless_max_capacity         = 32   # For serverless
backup_retention_period         = 30
deletion_protection             = true
enable_performance_insights     = true
performance_insights_retention_period = 731  # 2 years
enable_autoscaling              = true  # For provisioned
autoscaling_max_capacity        = 5     # For provisioned
```

## Using Existing VPC

If you have an existing VPC:

```hcl
create_vpc = false
vpc_id     = "vpc-xxxxx"

# Terraform will automatically discover subnets in the VPC
# Or specify subnet tags to filter:
# subnet_tags = {
#   Tier = "database"
# }
```

## Creating New VPC

If you need a new VPC:

```hcl
create_vpc         = true
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
enable_nat_gateway = true
```

This will create:
- VPC with the specified CIDR
- Public and private subnets in each AZ
- Internet Gateway
- NAT Gateways (one per AZ)
- Route tables
- DB subnet group
- Security groups

## Choosing Provisioned vs Serverless

| Factor | Provisioned | Serverless v2 |
|--------|-------------|---------------|
| Workload Pattern | Steady, predictable | Variable, unpredictable |
| Scaling | Manual or autoscaling read replicas | Automatic ACU scaling |
| Cold Start | None | None (instant) |
| Min Cost | ~$190/month (2x db.r6g.large) | ~$45/month (0.5 ACU min) |
| Best For | Always-on production | Dev, staging, variable prod |
| Reserved Instances | Yes (30-40% savings) | No |

## Cost Estimates (us-east-1, monthly)

### Provisioned
- **Small**: 2x db.r6g.large = ~$380
- **Medium**: 2x db.r6g.xlarge = ~$760
- **Large**: 2x db.r6g.2xlarge = ~$1,520

### Serverless v2 (2 instances)
- **Low traffic**: Avg 1 ACU = ~$180
- **Medium traffic**: Avg 4 ACU = ~$700
- **High traffic**: Avg 8 ACU = ~$1,400

*Note: Add costs for storage (~$0.10/GB), backups, I/O, etc.*

## Monitoring and Alerting

After deployment, you'll have:

### CloudWatch Alarms
- High CPU utilization (>80%)
- High database connections
- Low freeable memory
- High replica lag
- High read/write latency
- High ACU utilization (serverless)

### CloudWatch Logs
- PostgreSQL logs
- Slow query logs
- Connection logs

### Performance Insights
- Query performance metrics
- Wait event analysis
- Top SQL queries

## Backup and Recovery

### Automated Backups
- Daily automated backups
- Configurable retention (1-35 days)
- Point-in-time recovery (PITR)

### Manual Snapshots
```bash
# Create snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier my-cluster \
  --db-cluster-snapshot-identifier my-snapshot

# List snapshots
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier my-cluster
```

### Restore from Snapshot
```bash
# Restore to new cluster
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier restored-cluster \
  --snapshot-identifier my-snapshot \
  --engine aurora-postgresql
```

## Scaling

### Provisioned - Vertical Scaling
```hcl
# In terraform.tfvars, change:
instance_class = "db.r6g.2xlarge"  # Scale up
```

### Provisioned - Horizontal Scaling
```hcl
# Add more read replicas
instance_count = 3  # Or let autoscaling handle it
```

### Serverless - Adjust Capacity
```hcl
serverless_min_capacity = 2   # Increase minimum
serverless_max_capacity = 64  # Increase maximum
```

## Security Best Practices

1. **Never make database publicly accessible**
   ```hcl
   publicly_accessible = false  # Always!
   ```

2. **Use Secrets Manager for passwords**
   ```hcl
   manage_master_password = true
   ```

3. **Enable encryption**
   ```hcl
   storage_encrypted = true
   force_ssl         = true
   ```

4. **Use IAM authentication**
   ```hcl
   iam_database_authentication_enabled = true
   ```

5. **Restrict network access**
   ```hcl
   allowed_security_groups = ["sg-app-only"]
   ```

## Troubleshooting

### Issue: Can't connect to database

1. Check security group rules
   ```bash
   aws ec2 describe-security-groups --group-ids sg-xxxxx
   ```

2. Verify endpoint
   ```bash
   terraform output cluster_endpoint
   ```

3. Test from bastion host in same VPC
   ```bash
   nc -zv ENDPOINT 5432
   ```

### Issue: High CPU usage

1. Check Performance Insights for slow queries
2. Review pg_stat_statements:
   ```sql
   SELECT * FROM pg_stat_statements 
   ORDER BY total_exec_time DESC LIMIT 10;
   ```
3. Consider scaling up or optimizing queries

### Issue: Connection limit reached

1. Check current connections:
   ```sql
   SELECT count(*) FROM pg_stat_activity;
   ```
2. Increase max_connections or use connection pooling (PgBouncer, RDS Proxy)

## Next Steps

1. **Set up RDS Proxy** for connection pooling
2. **Configure cross-region replication** for disaster recovery
3. **Set up automated backup testing**
4. **Implement connection pooling** (PgBouncer, RDS Proxy)
5. **Review and optimize parameter groups** based on workload
6. **Set up monitoring dashboards** in CloudWatch or Grafana

## Getting Help

- **AWS Documentation**: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/
- **Terraform Documentation**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/

## Cleanup

To destroy the cluster (be careful in production!):

```bash
# Disable deletion protection first
terraform apply -var="deletion_protection=false"

# Then destroy
terraform destroy
```

**Note**: If `skip_final_snapshot = false`, a final snapshot will be created automatically.

