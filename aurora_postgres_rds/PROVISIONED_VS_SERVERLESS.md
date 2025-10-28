# Aurora PostgreSQL: Provisioned vs Serverless v2

## Quick Decision Matrix

| Factor | Provisioned | Serverless v2 | Winner |
|--------|-------------|---------------|--------|
| **Cost (Always-on)** | Lower at scale | Higher at scale | Provisioned |
| **Cost (Variable)** | Higher (fixed) | Lower (pay-per-use) | Serverless |
| **Scaling Speed** | Minutes | Seconds | Serverless |
| **Scaling Granularity** | Instance sizes | 0.5 ACU increments | Serverless |
| **Cold Starts** | None | None | Tie |
| **Reserved Instances** | Yes (30-40% off) | No | Provisioned |
| **Setup Complexity** | Same | Same | Tie |
| **Predictable Costs** | High | Lower | Provisioned |
| **Max Capacity** | db.r7g.16xlarge | 128 ACU (~256 GB) | Provisioned |
| **Dev/Test Cost** | Higher | Lower | Serverless |

## Detailed Comparison

### Architecture

#### Provisioned
```
Fixed instance sizes:
db.r6g.large    → 2 vCPU,  16 GB RAM
db.r6g.xlarge   → 4 vCPU,  32 GB RAM
db.r6g.2xlarge  → 8 vCPU,  64 GB RAM
db.r6g.4xlarge  → 16 vCPU, 128 GB RAM

Scaling:
- Vertical: Change instance class (requires restart)
- Horizontal: Add/remove read replicas (auto-scaling available)
```

#### Serverless v2
```
Capacity measured in ACU (Aurora Capacity Units):
1 ACU ≈ 2 GB RAM + corresponding CPU

Range: 0.5 to 128 ACU
Examples:
0.5 ACU  → ~1 GB RAM
2 ACU    → ~4 GB RAM
8 ACU    → ~16 GB RAM
32 ACU   → ~64 GB RAM
128 ACU  → ~256 GB RAM

Scaling:
- Automatic and instant (seconds)
- No instance size changes needed
- Granular (0.5 ACU increments)
```

### Cost Analysis (us-east-1, monthly estimates)

#### Scenario 1: Low Traffic Application
**Workload:** Business hours only, 8-5 Monday-Friday

**Provisioned (2x db.r6g.large):**
```
Base cost: $0.26/hour × 2 instances × 730 hours
= $380/month (fixed)
```

**Serverless v2 (min: 0.5, max: 8):**
```
Business hours (176 hours): Avg 4 ACU × $0.12 × 2 instances = $169
Off hours (554 hours): Avg 0.5 ACU × $0.12 × 2 instances = $66
Total: ~$235/month

Savings: $145/month (38%)
```

**Winner: Serverless v2** ✅

#### Scenario 2: Steady Production Workload
**Workload:** 24/7 consistent traffic

**Provisioned (2x db.r6g.large):**
```
Base cost: $380/month
With 1-year Reserved Instance (30% off): $266/month
```

**Serverless v2 (min: 2, max: 16):**
```
Average usage: 6 ACU constant
Cost: 6 ACU × $0.12 × 2 instances × 730 hours = $1,051/month
```

**Winner: Provisioned** ✅ (especially with Reserved Instances)

#### Scenario 3: Highly Variable Workload
**Workload:** Batch processing, unpredictable spikes

**Provisioned (2x db.r6g.xlarge):**
```
Must provision for peak: $760/month
Wasted capacity during low periods
```

**Serverless v2 (min: 0.5, max: 32):**
```
Low periods (600 hours): 1 ACU × $0.12 × 2 = $144
Medium periods (100 hours): 8 ACU × $0.12 × 2 = $192
Peak periods (30 hours): 24 ACU × $0.12 × 2 = $173
Total: ~$509/month

Savings: $251/month (33%)
```

**Winner: Serverless v2** ✅

#### Scenario 4: Large Production Database
**Workload:** High, consistent load requiring 128 GB RAM

**Provisioned (2x db.r6g.4xlarge):**
```
Base cost: $1,520/month
With 1-year RI: $1,064/month
With 3-year RI: $730/month
```

**Serverless v2 (min: 32, max: 64):**
```
Average: 48 ACU constant
Cost: 48 ACU × $0.12 × 2 instances × 730 hours = $8,409/month
```

**Winner: Provisioned** ✅ (by a large margin!)

### Performance Comparison

| Metric | Provisioned | Serverless v2 |
|--------|-------------|---------------|
| **Cold Start** | None | None (instant) |
| **Scale Up Time** | 5-10 minutes | Seconds |
| **Scale Down Time** | 5-10 minutes | Seconds |
| **Connection Handling** | Same | Same |
| **Query Performance** | Identical | Identical |
| **Max IOPS** | Same | Same |
| **Latency** | Same | Same |

**Winner: Tie** (Serverless has faster scaling)

### Feature Comparison

| Feature | Provisioned | Serverless v2 |
|---------|-------------|---------------|
| Multi-AZ | ✅ | ✅ |
| Read Replicas | ✅ | ✅ |
| Global Database | ✅ | ✅ |
| Backtrack | ✅ | ✅ |
| Performance Insights | ✅ | ✅ |
| Enhanced Monitoring | ✅ | ✅ |
| IAM Auth | ✅ | ✅ |
| Encryption | ✅ | ✅ |
| Auto Scaling Replicas | ✅ | ✅ (capacity auto-scales) |
| Reserved Instances | ✅ | ❌ |
| Auto Scaling Capacity | ❌ | ✅ |

### Use Case Recommendations

#### Choose **Provisioned** when:

1. **Steady, Predictable Workload**
   - 24/7 production applications
   - Consistent traffic patterns
   - Long-term deployments (use Reserved Instances)

2. **Large-Scale Deployments**
   - Need > 64 GB RAM consistently
   - High throughput requirements
   - Cost-sensitive at scale

3. **Budget Predictability**
   - Need fixed monthly costs
   - Finance requires cost certainty
   - Using Reserved Instance pricing

4. **Maximum Performance**
   - Need largest instance sizes
   - Require > 128 ACU equivalent
   - Consistent high IOPS

**Example Applications:**
- E-commerce platforms (always-on)
- SaaS applications with steady growth
- Enterprise ERPs
- Large-scale analytics databases

#### Choose **Serverless v2** when:

1. **Variable Workload**
   - Batch processing jobs
   - Weekend/night time low traffic
   - Unpredictable spikes
   - Seasonal applications

2. **Development/Staging**
   - Cost-conscious environments
   - Intermittent usage
   - Not business-critical

3. **New Applications**
   - Unknown capacity requirements
   - Want to start small
   - Need flexibility

4. **Microservices**
   - Many small databases
   - Independent scaling per service
   - Cost allocation per service

**Example Applications:**
- Internal tools (business hours only)
- Development environments
- Prototype/POC projects
- Seasonal retail applications
- Event-driven processing

### Migration Between Types

#### Provisioned → Serverless

```bash
# 1. Take snapshot
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier provisioned-cluster \
  --db-cluster-snapshot-identifier migration-snapshot

# 2. Create serverless cluster from snapshot
# Use terraform module: aurora-serverless
# Set: restore_from_snapshot = true

# 3. Update application endpoints
# 4. Verify and delete old cluster
```

#### Serverless → Provisioned

```bash
# Same process as above
# Use terraform module: aurora-provisioned
```

**Migration Time:** ~30 minutes (snapshot + restore)

### Cost Optimization Tips

#### For Provisioned

1. **Use Reserved Instances**
   - 1-year: 30% savings
   - 3-year: 50% savings
   - All upfront for max savings

2. **Right-size Instances**
   - Monitor CPU/memory usage
   - Scale down if consistently < 50% utilized
   - Use auto-scaling for read replicas

3. **Use Graviton Instances**
   - r6g/r7g: 20% cheaper than Intel/AMD
   - Same or better performance

4. **Delete Unused Snapshots**
   - Automate snapshot lifecycle
   - Keep only required retention

#### For Serverless

1. **Set Appropriate Min/Max ACU**
   ```hcl
   # Bad (over-provisioned min)
   min_capacity = 8
   
   # Good
   min_capacity = 0.5
   ```

2. **Monitor Average ACU Usage**
   - If consistently high (> 50% of max), consider provisioned
   - Adjust max based on actual peaks

3. **Use for Dev/Staging**
   - Lower min ACU (0.5)
   - Save costs during off-hours

4. **Consolidate Small Workloads**
   - Multiple schemas in one cluster
   - Shared infrastructure

### Real-World Cost Comparison

#### Example 1: Startup MVP
```
Requirements:
- Unknown traffic pattern
- Small initial user base
- Need to scale if successful

Provisioned (2x db.t4g.medium - smallest HA):
$130/month fixed

Serverless (0.5 min, 4 max, avg 1 ACU):
$88/month variable

Recommendation: Serverless v2
Savings: $42/month (32%)
```

#### Example 2: Medium SaaS (1000 customers)
```
Requirements:
- 24/7 uptime
- Predictable growth
- 3-year commitment

Provisioned (2x db.r6g.large + 3yr RI):
$220/month

Serverless (2 min, 16 max, avg 8 ACU):
$1,402/month

Recommendation: Provisioned
Savings: $1,182/month (84%)
```

#### Example 3: Analytics Workload
```
Requirements:
- Batch jobs (4 hours/day)
- Heavy processing during jobs
- Idle rest of time

Provisioned (2x db.r6g.2xlarge):
$1,520/month

Serverless (0.5 min, 32 max):
- Active: 32 ACU × 4 hours × 30 days = $231
- Idle: 0.5 ACU × 20 hours × 30 days = $36
Total: $267/month

Recommendation: Serverless v2
Savings: $1,253/month (82%)
```

## Decision Tree

```
Start
  │
  ├─ Is workload 24/7 with consistent load?
  │   │
  │   ├─ YES → Will you commit to 1-3 years?
  │   │   │
  │   │   ├─ YES → **Provisioned with Reserved Instances** ✅
  │   │   └─ NO → Compare costs at current scale
  │   │
  │   └─ NO → Are there significant off-peak periods?
  │       │
  │       ├─ YES → **Serverless v2** ✅
  │       └─ NO → **Provisioned** ✅
  │
  ├─ Is this development/staging?
  │   │
  │   └─ YES → **Serverless v2** ✅
  │
  ├─ Do you need > 128 ACU equivalent consistently?
  │   │
  │   └─ YES → **Provisioned** ✅
  │
  └─ Unsure about capacity needs?
      │
      └─ YES → Start with **Serverless v2**, migrate if needed ✅
```

## Summary Table

| Criteria | Provisioned Score | Serverless Score | Recommendation |
|----------|-------------------|------------------|----------------|
| Always-on workload | 9/10 | 5/10 | Provisioned |
| Variable workload | 5/10 | 10/10 | Serverless |
| Dev/Test | 4/10 | 9/10 | Serverless |
| Large scale (> 64GB) | 10/10 | 6/10 | Provisioned |
| Cost predictability | 9/10 | 6/10 | Provisioned |
| Cost optimization | 7/10 | 9/10 | Depends |
| Scaling speed | 6/10 | 10/10 | Serverless |
| Long-term production | 10/10 | 7/10 | Provisioned |
| New/unknown workload | 5/10 | 9/10 | Serverless |

## Conclusion

**Use Provisioned if:**
- Consistent 24/7 workload
- Can commit to Reserved Instances
- Need maximum capacity (> 256 GB)
- Require predictable costs

**Use Serverless v2 if:**
- Variable or unpredictable workload
- Development/staging environments
- Starting new project with unknown capacity
- Need rapid scaling
- Want to minimize costs for intermittent use

**Both are excellent choices** - the decision comes down to your specific workload pattern and cost optimization strategy. Many organizations use **both**:
- Provisioned for production
- Serverless for dev/staging/analytics

You can always migrate between them using snapshots with minimal downtime!

