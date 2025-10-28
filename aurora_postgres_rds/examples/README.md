# Terraform Configuration Examples

This directory contains example `terraform.tfvars` files for deploying Aurora PostgreSQL clusters.

## Files

- **terraform.tfvars.provisioned.example** - Configuration for provisioned Aurora cluster
- **terraform.tfvars.serverless.example** - Configuration for serverless v2 Aurora cluster

## Usage

1. **Copy the appropriate example file to your environment directory:**

   For provisioned cluster:
   ```bash
   cp examples/terraform.tfvars.provisioned.example \
      environments/production-provisioned/terraform.tfvars
   ```

   For serverless cluster:
   ```bash
   cp examples/terraform.tfvars.serverless.example \
      environments/production-serverless/terraform.tfvars
   ```

2. **Edit the file with your specific values:**
   - Update VPC ID (or set `create_vpc = true` to create new VPC)
   - Set allowed CIDR blocks or security groups
   - Configure backup and maintenance windows
   - Add alarm email addresses
   - Adjust instance sizes/ACU limits based on workload

3. **Initialize and apply:**
   ```bash
   cd environments/production-provisioned  # or production-serverless
   terraform init
   terraform plan
   terraform apply
   ```

## Key Configuration Decisions

### Provisioned vs Serverless

**Choose Provisioned if:**
- Predictable, steady workload
- Need specific instance sizing control
- Cost-effective for always-on workloads
- Want to use Reserved Instances for savings

**Choose Serverless if:**
- Variable, unpredictable workload
- Need automatic scaling
- Cost-conscious with periods of low traffic
- Development/staging environments

### Instance Sizing (Provisioned)

| Instance Class | vCPU | Memory | Est. Cost/Month (us-east-1) |
|----------------|------|---------|----------------------------|
| db.r6g.large   | 2    | 16 GB   | ~$190                      |
| db.r6g.xlarge  | 4    | 32 GB   | ~$380                      |
| db.r6g.2xlarge | 8    | 64 GB   | ~$760                      |
| db.r7g.large   | 2    | 16 GB   | ~$210                      |
| db.r7g.xlarge  | 4    | 32 GB   | ~$420                      |

**Recommendations:**
- Start with `db.r6g.large` for small to medium workloads
- Use `db.r7g.*` for latest generation (5-10% better performance)
- Monitor CPU and memory, scale up if needed

### ACU Sizing (Serverless)

| ACU | Approx. Memory | Est. Cost/Hour (us-east-1) |
|-----|----------------|---------------------------|
| 0.5 | 1 GB           | ~$0.06                    |
| 1   | 2 GB           | ~$0.12                    |
| 2   | 4 GB           | ~$0.24                    |
| 4   | 8 GB           | ~$0.48                    |
| 8   | 16 GB          | ~$0.96                    |
| 16  | 32 GB          | ~$1.92                    |

**Recommendations:**
- Start with min: 0.5, max: 16 for most workloads
- Monitor ACU usage in CloudWatch
- Adjust max based on peak requirements

### High Availability

For production, always configure:
- At least 2 instances (1 writer + 1 reader)
- Instances in multiple availability zones
- Automated backups with 30-day retention
- Deletion protection enabled

### Security Best Practices

1. **Network:**
   - Deploy in private subnets
   - Use security groups, not CIDR blocks if possible
   - Enable VPC endpoints for AWS services

2. **Encryption:**
   - Enable encryption at rest (KMS)
   - Force SSL connections (`force_ssl = true`)
   - Use Secrets Manager for password management

3. **Authentication:**
   - Enable IAM database authentication
   - Let RDS manage master password

4. **Monitoring:**
   - Enable Performance Insights
   - Enable Enhanced Monitoring
   - Export logs to CloudWatch
   - Configure alarms with SNS notifications

### Cost Optimization

**Provisioned:**
- Use Graviton instances (r6g/r7g) for 20% savings
- Purchase Reserved Instances for long-term production (30-40% savings)
- Enable autoscaling to match read capacity with demand
- Right-size instances based on actual usage

**Serverless:**
- Set appropriate min/max ACU limits
- Monitor average ACU usage
- Consider provisioned if consistently using > 2-3 ACUs
- Use for dev/staging to save costs during off-hours

## Environment-Specific Customization

### Development
```hcl
instance_count = 1                    # Single instance for dev
backup_retention_period = 7           # Shorter retention
deletion_protection = false           # Allow easy cleanup
skip_final_snapshot = true            # No final snapshot needed
enable_performance_insights = false   # Reduce costs
performance_insights_retention_period = 7
serverless_min_capacity = 0.5         # For serverless
serverless_max_capacity = 4
```

### Staging
```hcl
instance_count = 2                    # Multi-AZ for testing
backup_retention_period = 14
deletion_protection = true
skip_final_snapshot = false
enable_performance_insights = true
serverless_min_capacity = 0.5
serverless_max_capacity = 8
```

### Production
```hcl
instance_count = 2                    # Minimum for HA
backup_retention_period = 30          # Maximum retention
deletion_protection = true            # Protect from deletion
skip_final_snapshot = false           # Always take final snapshot
enable_performance_insights = true
performance_insights_retention_period = 731  # 2 years
enable_autoscaling = true             # Scale readers
autoscaling_max_capacity = 5
serverless_min_capacity = 1           # Higher min for production
serverless_max_capacity = 32          # Higher max for peaks
```

## Troubleshooting

### Common Issues

1. **VPC/Subnet Issues**
   ```
   Error: DB Subnet Group doesn't meet availability zone coverage requirement
   ```
   **Solution:** Ensure subnets span at least 2 availability zones

2. **Parameter Group Family Mismatch**
   ```
   Error: Invalid parameter group family
   ```
   **Solution:** Ensure `parameter_group_family` matches `engine_version`
   - PostgreSQL 16.x → aurora-postgresql16
   - PostgreSQL 15.x → aurora-postgresql15

3. **Serverless v2 Not Available**
   ```
   Error: Serverless v2 is not available for this engine version
   ```
   **Solution:** Check AWS documentation for supported versions

## Next Steps

After deployment:
1. Retrieve database credentials from Secrets Manager
2. Test connections from your application
3. Review CloudWatch metrics and adjust capacity
4. Subscribe to SNS alarm notifications
5. Set up regular backup testing
6. Review and optimize parameter groups

## Support

- AWS Aurora Documentation: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
- Internal upgrade guides: See `/docs/rds_upgrade/`

