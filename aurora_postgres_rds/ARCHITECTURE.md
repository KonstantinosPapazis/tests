# Aurora PostgreSQL Terraform Architecture

## Overview

This repository provides production-ready Terraform modules for deploying AWS Aurora PostgreSQL databases in both **provisioned** and **serverless v2** configurations.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            AWS Cloud (Region)                            │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         VPC (10.0.0.0/16)                         │   │
│  │                                                                   │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │   │
│  │  │      AZ-a    │    │      AZ-b    │    │      AZ-c    │      │   │
│  │  │              │    │              │    │              │      │   │
│  │  │  ┌────────┐  │    │  ┌────────┐  │    │  ┌────────┐  │      │   │
│  │  │  │ Public │  │    │  │ Public │  │    │  │ Public │  │      │   │
│  │  │  │ Subnet │  │    │  │ Subnet │  │    │  │ Subnet │  │      │   │
│  │  │  │        │  │    │  │        │  │    │  │        │  │      │   │
│  │  │  │  NAT   │  │    │  │  NAT   │  │    │  │  NAT   │  │      │   │
│  │  │  │  GW    │  │    │  │  GW    │  │    │  │  GW    │  │      │   │
│  │  │  └───┬────┘  │    │  └───┬────┘  │    │  └───┬────┘  │      │   │
│  │  │      │       │    │      │       │    │      │       │      │   │
│  │  │  ┌───▼─────┐ │    │  ┌───▼─────┐ │    │  ┌───▼─────┐ │      │   │
│  │  │  │ Private │ │    │  │ Private │ │    │  │ Private │ │      │   │
│  │  │  │ Subnet  │ │    │  │ Subnet  │ │    │  │ Subnet  │ │      │   │
│  │  │  │         │ │    │  │         │ │    │  │         │ │      │   │
│  │  │  │ ┌─────┐ │ │    │  │ ┌─────┐ │ │    │  │         │ │      │   │
│  │  │  │ │Aurora│ │ │    │  │ │Aurora│ │ │    │  │         │ │      │   │
│  │  │  │ │Writer│ │ │    │  │ │Reader│ │ │    │  │         │ │      │   │
│  │  │  │ │ Inst │ │ │    │  │ │ Inst │ │ │    │  │         │ │      │   │
│  │  │  │ └─────┘ │ │    │  │ └─────┘ │ │    │  │         │ │      │   │
│  │  │  └─────────┘ │    │  └─────────┘ │    │  └─────────┘ │      │   │
│  │  └──────────────┘    └──────────────┘    └──────────────┘      │   │
│  │                                                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │                    Security Group                         │  │   │
│  │  │  • Port 5432 from allowed CIDR/SGs only                   │  │   │
│  │  │  • SSL/TLS enforced                                       │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  │                                                                   │   │
│  │  ┌──────────────────────────────────────────────────────────┐  │   │
│  │  │                   VPC Endpoints                           │  │   │
│  │  │  • S3 (for backups)                                       │  │   │
│  │  │  • Secrets Manager                                        │  │   │
│  │  │  • CloudWatch Logs                                        │  │   │
│  │  └──────────────────────────────────────────────────────────┘  │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                           │
│  ┌────────────────────┐  ┌────────────────────┐  ┌──────────────────┐ │
│  │   Secrets Manager  │  │   CloudWatch       │  │   SNS Topics     │ │
│  │   • DB Password    │  │   • Metrics        │  │   • Alarms       │ │
│  │   • Auto-managed   │  │   • Logs           │  │   • Notifications│ │
│  │                    │  │   • Alarms         │  │                  │ │
│  └────────────────────┘  └────────────────────┘  └──────────────────┘ │
│                                                                           │
│  ┌────────────────────┐  ┌────────────────────┐                        │
│  │   KMS             │  │   Performance      │                        │
│  │   • Encryption    │  │   Insights         │                        │
│  │   • Auto-rotation │  │   • Query Analysis │                        │
│  └────────────────────┘  └────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────────┘
```

## Module Structure

### Core Modules

#### 1. **networking/** - Network Infrastructure
- Creates or uses existing VPC
- Sets up public/private subnets across multiple AZs
- Configures NAT Gateways for internet access
- Creates DB subnet groups
- Sets up security groups with least-privilege rules
- Configures VPC endpoints (S3, Secrets Manager, CloudWatch)

**Key Features:**
- Multi-AZ deployment for high availability
- Private subnets for database isolation
- VPC endpoints to reduce NAT Gateway costs
- Flexible CIDR or security group-based access control

#### 2. **parameter-groups/** - PostgreSQL Configuration
- Cluster parameter group (cluster-wide settings)
- Instance parameter group (instance-specific settings)
- Production-optimized PostgreSQL parameters

**Optimizations:**
- Memory configuration based on instance class
- Logging and monitoring settings
- Performance tuning (work_mem, shared_buffers, etc.)
- Autovacuum configuration
- Connection pooling settings
- SSL enforcement

#### 3. **aurora-provisioned/** - Provisioned Cluster
- Fixed instance sizes (db.r6g.large, db.r7g.xlarge, etc.)
- Auto-scaling read replicas
- Predictable performance and costs

**Features:**
- Multi-AZ with automatic failover
- Read replica auto-scaling based on CPU/connections
- Enhanced monitoring and Performance Insights
- KMS encryption at rest
- IAM database authentication
- CloudWatch alarms
- SNS notifications
- Secrets Manager integration

#### 4. **aurora-serverless/** - Serverless v2 Cluster
- Auto-scaling capacity (0.5-128 ACUs)
- Pay-per-second billing
- Instant scaling

**Features:**
- All provisioned features PLUS:
- Automatic capacity scaling
- ACU-based monitoring and alarms
- Cost-optimized for variable workloads

## Data Flow

### Write Operations
```
Application → VPC Endpoint/NAT → Security Group → Writer Instance → Storage Layer
```

### Read Operations
```
Application → VPC Endpoint/NAT → Security Group → Reader Endpoint (Load Balanced)
                                                  → Reader Instance 1
                                                  → Reader Instance 2
                                                  → Reader Instance N
```

### Monitoring Flow
```
Aurora Cluster → Enhanced Monitoring → CloudWatch Metrics
              → Performance Insights → AWS Console
              → PostgreSQL Logs → CloudWatch Logs
              → Alarms → SNS → Email/SMS
```

### Backup Flow
```
Aurora Cluster → Automated Backup → S3 (via VPC Endpoint)
              → Manual Snapshot → S3
              → PITR Logs → S3
```

## Security Layers

### 1. Network Security
- Private subnet deployment (no public internet access)
- Security groups with minimal port access (5432 only)
- Network ACLs (if configured)
- VPC endpoints to avoid internet transit

### 2. Encryption
- **At Rest**: KMS encryption for all data
- **In Transit**: SSL/TLS enforced for all connections
- **Backups**: Encrypted with same KMS key
- **Secrets**: Managed by AWS Secrets Manager

### 3. Authentication & Authorization
- IAM database authentication
- AWS Secrets Manager for password management
- PostgreSQL role-based access control (RBAC)
- Fine-grained IAM policies

### 4. Monitoring & Auditing
- CloudWatch Logs for all database activity
- Enhanced monitoring (OS-level metrics)
- Performance Insights (query-level analysis)
- CloudWatch Alarms for anomaly detection
- AWS Config for compliance

## High Availability Architecture

### Automatic Failover
```
┌─────────────────────────────────────────────────────────────┐
│                      Normal Operation                        │
│                                                               │
│  Application                                                 │
│      ↓                                                        │
│  Writer Endpoint (DNS) → Primary Instance (AZ-a)            │
│  Reader Endpoint (DNS) → Reader 1 (AZ-b), Reader 2 (AZ-c)   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Failover Scenario                         │
│                                                               │
│  Primary Instance Fails (AZ-a) ✗                            │
│      ↓                                                        │
│  Aurora detects failure (< 30 seconds)                       │
│      ↓                                                        │
│  Promotes Reader 1 to Writer (< 60 seconds)                 │
│      ↓                                                        │
│  Writer Endpoint (DNS) → Reader 1 (now Primary, AZ-b)       │
│  Reader Endpoint (DNS) → Reader 2 (AZ-c)                     │
│      ↓                                                        │
│  Application automatically reconnects                        │
│                                                               │
│  Total Downtime: < 120 seconds                              │
└─────────────────────────────────────────────────────────────┘
```

## Scaling Strategies

### Provisioned Cluster

#### Vertical Scaling (Increase Instance Size)
```
db.r6g.large → db.r6g.xlarge → db.r6g.2xlarge
   2 vCPU         4 vCPU           8 vCPU
   16 GB          32 GB            64 GB
```

#### Horizontal Scaling (Add Read Replicas)
```
Auto-scaling policy:
- Target: 70% CPU utilization
- Min replicas: 1
- Max replicas: 5
- Scale out: Add replica when CPU > 70% for 5 min
- Scale in: Remove replica when CPU < 40% for 15 min
```

### Serverless v2 Cluster

#### Capacity Scaling (ACU-based)
```
Workload increases → ACU scales up automatically
0.5 → 1 → 2 → 4 → 8 → 16 → 32 → 64 → 128 ACU

Scaling time: Seconds to minutes
Billing: Per-second, for actual ACU usage
```

## Deployment Patterns

### Pattern 1: Single Region, Multi-AZ (Standard)
```
Region: us-east-1
├── AZ-a: Writer Instance
├── AZ-b: Reader Instance 1
└── AZ-c: Reader Instance 2 (auto-scaled)

Benefits:
- < 2ms latency between AZs
- Automatic failover
- Cost-effective
```

### Pattern 2: Multi-Region (Global Database)
```
Primary Region: us-east-1
├── Writer Cluster (us-east-1)
└── Replicas in us-east-1

Secondary Region: eu-west-1
└── Read-only Cluster (cross-region replica)

Benefits:
- < 1 second cross-region replication lag
- Disaster recovery
- Global read scale
- Manual promotion for DR
```

### Pattern 3: Blue-Green Deployment
```
Blue Environment (Production)
└── prod-aurora-blue

Green Environment (New version/changes)
└── prod-aurora-green

Switch traffic using DNS/application config
```

## Cost Optimization Strategies

### Provisioned
1. **Use Graviton Instances** (r6g, r7g): 20% cheaper than x86
2. **Reserved Instances**: 30-40% savings for 1-3 year commitments
3. **Right-size instances**: Monitor CPU/memory, adjust accordingly
4. **Auto-scaling**: Only pay for replicas when needed
5. **Backtrack instead of snapshots**: Lower storage costs

### Serverless v2
1. **Set appropriate min/max ACU**: Avoid over-provisioning
2. **Use for variable workloads**: Pay only for what you use
3. **Dev/staging with low min ACU**: Save costs during off-hours
4. **Monitor average ACU usage**: Switch to provisioned if consistently high

### Both
1. **Enable storage auto-scaling**: Pay only for used storage
2. **Optimize backup retention**: Balance between compliance and cost
3. **Use VPC endpoints**: Reduce NAT Gateway data transfer costs
4. **Archive old data**: Move to cheaper storage (S3)

## Monitoring and Observability

### Key Metrics to Monitor

#### Database Health
- CPU Utilization
- Freeable Memory
- Database Connections
- Network Throughput
- Disk I/O

#### Performance
- Read/Write Latency
- Read/Write IOPS
- Read/Write Throughput
- Query Performance (via Performance Insights)

#### Availability
- Replica Lag
- Failed Login Attempts
- Error Logs
- Failover Events

#### Capacity (Serverless)
- ACU Utilization
- ServerlessDatabaseCapacity
- Scaling Events

### Alerting Thresholds (Default)

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU | > 80% | Scale up or optimize queries |
| Memory | < 256 MB | Scale up instance |
| Connections | > 80% max | Implement connection pooling |
| Replica Lag | > 1000ms | Investigate write load |
| Write Latency | > 20ms | Check storage performance |
| Read Latency | > 20ms | Add read replicas |

## Disaster Recovery

### RPO and RTO Targets

| Scenario | RPO | RTO | Recovery Method |
|----------|-----|-----|----------------|
| AZ Failure | 0 | < 2 min | Auto-failover to replica |
| Region Failure | < 5 min | < 1 hour | Promote cross-region replica |
| Data Corruption | < 5 min | < 30 min | Point-in-time restore |
| Accidental Deletion | < 5 min | < 30 min | Restore from snapshot |

### Backup Strategy
1. **Automated daily backups**: 30-day retention
2. **Point-in-time recovery**: 5-minute granularity
3. **Manual snapshots**: Before major changes
4. **Cross-region snapshot copy**: For DR
5. **Backup testing**: Monthly restore drills

## Best Practices

### Development
- Use separate clusters for dev/staging/prod
- Use serverless for dev/staging (cost savings)
- Implement CI/CD for database changes
- Test backups and restores regularly

### Security
- Never use default passwords
- Rotate credentials regularly (Secrets Manager handles this)
- Use IAM authentication for applications
- Audit access logs
- Implement least privilege access

### Performance
- Use connection pooling (RDS Proxy or PgBouncer)
- Monitor slow query logs
- Implement proper indexing
- Use read replicas for read-heavy workloads
- Partition large tables

### Operations
- Automate everything with Terraform
- Use tags for cost allocation
- Monitor costs with AWS Cost Explorer
- Document runbooks for common issues
- Test failover scenarios regularly

## Upgrade Path

For upgrading between PostgreSQL major versions, see:
- `/docs/rds_upgrade/AURORA_POSTGRESQL_13_TO_16_UPGRADE_GUIDE.md`
- `/docs/rds_upgrade/aurora_upgrade_scripts/`

## Integration Examples

### Application Connection
```python
import psycopg2
import boto3
import json

# Get credentials from Secrets Manager
secrets = boto3.client('secretsmanager')
secret = secrets.get_secret_value(SecretId='prod-aurora-db-password')
creds = json.loads(secret['SecretString'])

# Connect with SSL
conn = psycopg2.connect(
    host=creds['host'],
    port=creds['port'],
    database=creds['database'],
    user=creds['username'],
    password=creds['password'],
    sslmode='require'
)
```

### RDS Proxy Integration
```hcl
# Add RDS Proxy for connection pooling
resource "aws_db_proxy" "main" {
  name                   = "${var.cluster_identifier}-proxy"
  engine_family          = "POSTGRESQL"
  auth {
    secret_arn = aws_secretsmanager_secret.db_password.arn
  }
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = module.networking.private_subnet_ids
  require_tls            = true
}
```

## Troubleshooting Guide

See `QUICKSTART.md` for common issues and solutions.

## Additional Resources

- [AWS Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/)
- [Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

