# Aurora PostgreSQL Terraform Configurations

This directory contains production-ready Terraform configurations for deploying AWS Aurora PostgreSQL databases in both **Provisioned** and **Serverless v2** modes.

## Directory Structure

```
aurora_postgres_rds/
├── README.md                           # This file
├── modules/                            # Reusable Terraform modules
│   ├── aurora-provisioned/            # Provisioned Aurora cluster module
│   ├── aurora-serverless/             # Serverless v2 Aurora cluster module
│   ├── networking/                     # VPC, subnets, security groups
│   └── parameter-groups/              # DB parameter and cluster parameter groups
├── environments/                       # Environment-specific configurations
│   ├── production-provisioned/        # Production provisioned cluster
│   ├── production-serverless/         # Production serverless cluster
│   ├── staging/                       # Staging environment
│   └── dev/                           # Development environment
└── examples/                          # Example configurations
    ├── terraform.tfvars.provisioned.example
    └── terraform.tfvars.serverless.example
```

## Features

### Production-Ready Features (Both Modes)
- ✅ Multi-AZ high availability
- ✅ Automated backups with configurable retention
- ✅ Encryption at rest (KMS)
- ✅ Encryption in transit (SSL/TLS)
- ✅ Enhanced monitoring with Performance Insights
- ✅ CloudWatch alarms for critical metrics
- ✅ Secrets Manager integration for credentials
- ✅ IAM database authentication support
- ✅ Automated minor version patching
- ✅ Maintenance window configuration
- ✅ Backup window configuration
- ✅ Parameter groups for optimization
- ✅ Security groups with least privilege
- ✅ DB subnet groups spanning multiple AZs
- ✅ Tags for cost allocation and governance
- ✅ SNS notifications for events
- ✅ Point-in-time recovery (PITR)
- ✅ Cross-region read replicas (optional)

### Provisioned Mode Features
- Instance sizing (db.r6g, db.r7g families)
- Auto-scaling for read replicas
- Fine-grained instance control
- Optimized for predictable workloads

### Serverless v2 Features
- Auto-scaling from 0.5 to 128 ACUs
- Pay-per-second billing
- Instant scaling
- Optimized for variable workloads

## Quick Start

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Existing VPC or use the networking module

### Provisioned Cluster Deployment

```bash
cd environments/production-provisioned
cp ../../examples/terraform.tfvars.provisioned.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

### Serverless Cluster Deployment

```bash
cd environments/production-serverless
cp ../../examples/terraform.tfvars.serverless.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_identifier` | Unique identifier for the cluster | Required |
| `engine_version` | PostgreSQL version (13.x, 14.x, 15.x, 16.x) | `16.1` |
| `master_username` | Master database username | `postgres` |
| `database_name` | Initial database name | `postgres` |
| `backup_retention_period` | Backup retention in days | `30` |
| `preferred_backup_window` | Backup window (UTC) | `03:00-04:00` |
| `preferred_maintenance_window` | Maintenance window (UTC) | `mon:04:00-mon:05:00` |
| `enable_performance_insights` | Enable Performance Insights | `true` |
| `enable_enhanced_monitoring` | Enable Enhanced Monitoring | `true` |
| `enable_cloudwatch_logs_exports` | CloudWatch log types | `["postgresql"]` |

### Provisioned-Specific Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `instance_class` | DB instance class | `db.r6g.large` |
| `instance_count` | Number of instances (1 writer + n readers) | `2` |
| `enable_autoscaling` | Enable read replica autoscaling | `true` |
| `autoscaling_min_capacity` | Min read replicas | `1` |
| `autoscaling_max_capacity` | Max read replicas | `5` |

### Serverless-Specific Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `serverless_min_capacity` | Min ACUs | `0.5` |
| `serverless_max_capacity` | Max ACUs | `16` |
| `serverless_scaling_timeout` | Scaling timeout in seconds | `300` |

## Security Best Practices

1. **Encryption**
   - All data encrypted at rest using AWS KMS
   - SSL/TLS required for connections
   - Encrypted automated backups and snapshots

2. **Network Security**
   - Database deployed in private subnets
   - Security groups with minimal access
   - No public accessibility by default

3. **Access Control**
   - Master password stored in AWS Secrets Manager
   - IAM database authentication enabled
   - Fine-grained IAM policies

4. **Monitoring**
   - CloudWatch alarms for CPU, memory, connections
   - Performance Insights enabled
   - Enhanced monitoring with 1-second granularity
   - PostgreSQL logs exported to CloudWatch

## High Availability

### Multi-AZ Deployment
- Writer instance in primary AZ
- Read replicas in different AZs
- Automatic failover (typically < 120 seconds)
- DB subnet group spanning 3+ AZs

### Backup Strategy
- Automated daily backups
- 30-day retention (configurable)
- Point-in-time recovery (PITR)
- Manual snapshots for long-term retention
- Cross-region snapshot copy (optional)

## Monitoring and Alerting

### CloudWatch Alarms
- High CPU utilization (> 80%)
- High database connections (> 80% of max)
- Low freeable memory (< 256 MB)
- High replica lag (> 1000 ms)
- Low disk throughput
- Failed login attempts

### Performance Insights
- Query performance monitoring
- Wait event analysis
- Top SQL identification
- Database load tracking

## Cost Optimization

### Provisioned Mode
- Right-size instances based on workload
- Use Reserved Instances for 30-40% savings
- Use graviton2/3 instances (r6g/r7g) for 20% savings
- Scale read replicas based on demand

### Serverless Mode
- Configure appropriate min/max ACUs
- Leverage auto-pause for dev/staging (if needed)
- Monitor ACU usage and adjust scaling configuration
- Ideal for unpredictable workloads

## Disaster Recovery

### RPO/RTO Targets
- **RPO**: 5 minutes (via continuous backups)
- **RTO**: < 2 hours (via automated failover or snapshot restore)

### Recovery Procedures
1. **Automated Failover**: Aurora automatically promotes a replica
2. **Point-in-Time Restore**: Restore to any point within backup retention
3. **Snapshot Restore**: Restore from manual or automated snapshots
4. **Cross-Region Recovery**: Promote a cross-region replica

## Maintenance

### Patching Strategy
- **Minor versions**: Automated patching enabled during maintenance window
- **Major versions**: Manual upgrade with testing
- **Zero-downtime patching**: Uses rolling deployments for readers

### Upgrade Path
Refer to `/docs/rds_upgrade/` for detailed upgrade procedures.

## Troubleshooting

### Common Issues

1. **Connection Timeout**
   - Check security group rules
   - Verify subnet routing
   - Check NACLs

2. **High CPU**
   - Review slow queries in Performance Insights
   - Check for missing indexes
   - Consider scaling up or optimizing queries

3. **Replication Lag**
   - Check network latency
   - Review write-heavy workloads
   - Consider provisioned IOPS

## Testing

Each module includes basic validation tests. Run:

```bash
cd modules/aurora-provisioned  # or aurora-serverless
terraform fmt -check
terraform validate
```

## Contributing

When adding new features:
1. Update module documentation
2. Add examples
3. Update this README
4. Test in a non-production environment

## Support

For issues specific to:
- **Aurora PostgreSQL**: See AWS documentation
- **Terraform**: See Terraform AWS provider documentation
- **This configuration**: Open an issue in the repository

## License

This configuration is provided as-is for internal use.

## References

- [Aurora PostgreSQL Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraPostgreSQL.html)
- [Aurora Serverless v2 Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-serverless-v2.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)

