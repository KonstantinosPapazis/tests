# Multi-Region Access Point (MRAP) Configuration

This directory contains Terraform configuration to set up MRAP for automatic geographic routing of S3 downloads.

## 🎯 Use Case

**Problem:**
- Developers upload images to `eu-west-2` bucket
- Images replicate to `us-east-2` bucket
- All users download from same bucket → high latency for distant users

**Solution:**
- ✅ Generate ONE presigned URL using MRAP
- ✅ European users automatically download from `eu-west-2` (low latency)
- ✅ US users automatically download from `us-east-2` (low latency)
- ✅ No application logic needed!

## 📁 Files

- **`main.tf`** - Complete Terraform configuration for MRAP
- **`BOTO3_CLIENT_CONFIGURATION.md`** - Developer guide for boto3 code changes
- **`terraform.tfvars.example`** - Example configuration file
- **`README.md`** - This file

## 🚀 Quick Start

### Step 1: Configure Terraform

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your bucket names
vim terraform.tfvars
```

Update these values in `terraform.tfvars`:

```hcl
mrap_name = "my-global-access-point"
eu_bucket_name = "my-bucket-eu-west-2"  # Your EU bucket
us_bucket_name = "my-bucket-us-east-2"  # Your US bucket
create_buckets = false  # Set to false if buckets already exist
```

### Step 2: Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply configuration
terraform apply
```

⚠️ **IMPORTANT:** MRAP creation can take up to 24 hours!

### Step 3: Get Configuration Values

After `terraform apply` completes, get the values you need:

```bash
# Get MRAP alias (needed for boto3)
terraform output mrap_alias

# Get your AWS Account ID
terraform output account_id

# Get complete MRAP ARN (ready to use in code)
terraform output boto3_mrap_arn

# See complete developer instructions
terraform output developer_instructions
```

### Step 4: Update Developer Code

See **`BOTO3_CLIENT_CONFIGURATION.md`** for complete code examples.

**Quick summary:**

```python
# OLD: Bucket-specific presigned URLs
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': 'my-bucket-eu-west-2', 'Key': 'image.jpg'})

# NEW: MRAP presigned URLs (automatic routing!)
mrap_arn = "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS"  # From terraform output
url = s3_client.generate_presigned_url('get_object',
    Params={'Bucket': mrap_arn, 'Key': 'image.jpg'})
```

## 📊 What Gets Created

1. **Versioning** enabled on both buckets (required for MRAP)
2. **S3 Replication** from eu-west-2 → us-east-2 (automatic)
3. **Multi-Region Access Point** spanning both regions
4. **IAM Role** for replication with appropriate permissions
5. **Public Access Blocks** for security best practices

## 🔍 Check MRAP Status

MRAP creation can take up to 24 hours. Check status:

```bash
# Via Terraform
terraform output mrap_status

# Via AWS CLI
aws s3control get-multi-region-access-point \
  --account-id YOUR_ACCOUNT_ID \
  --name my-global-access-point
```

Status will be one of:
- `CREATING` - Still being created (wait)
- `READY` - Ready to use! ✅
- `UPDATING` - Configuration change in progress
- `DELETING` - Being deleted

## 🌍 How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer Workflow                        │
└─────────────────────────────────────────────────────────────┘
    │
    │ 1. Upload to eu-west-2
    ├────────────────────────────►  ┌──────────────────┐
    │                               │  eu-west-2       │
    │ 2. Generate presigned URL     │  Bucket          │
    │    using MRAP ARN             └──────────────────┘
    │                                      │
    │                                      │ Replication
    │                                      │ (within 15 min)
    │                                      ▼
    │                               ┌──────────────────┐
    │                               │  us-east-2       │
    │                               │  Bucket          │
    │                               └──────────────────┘
    │
    │ 3. User clicks presigned URL
    ▼
┌─────────────────────────────────────────────────────────────┐
│                    MRAP Automatic Routing                    │
└─────────────────────────────────────────────────────────────┘
    │
    ├─► EU User    ──► Routes to eu-west-2  (low latency ✅)
    │
    └─► US User    ──► Routes to us-east-2  (low latency ✅)
```

## 💰 Cost Considerations

| Component | Cost | Notes |
|-----------|------|-------|
| MRAP Routing | ~$0.0005 per 1,000 requests | Charged per request routed |
| S3 Replication | ~$0.02/GB | Standard cross-region transfer |
| S3 RTC | ~$0.015/GB | Optional, guarantees 15-min replication |
| Storage | Standard S3 pricing | Charged in both regions |

**Estimated monthly cost** for 1TB data with 1M downloads:
- Without MRAP: ~$0 (but poor UX for US users)
- With MRAP: ~$30-50 (great UX for all users)

## 🔐 Security

- ✅ Public access blocked on all buckets
- ✅ IAM roles follow least-privilege principle
- ✅ Versioning enabled (protects against accidental deletes)
- ✅ Presigned URLs support same security as regular S3
- ✅ MRAP respects existing bucket policies

## 📈 Monitoring

### Check Replication Status

```bash
# Via AWS CLI
aws s3api get-bucket-replication \
  --bucket my-bucket-eu-west-2
```

### CloudWatch Metrics

Monitor these metrics:
- `ReplicationLatency` - Time to replicate objects
- `BytesPendingReplication` - Data waiting to replicate
- `OperationsPendingReplication` - Objects waiting to replicate

### Test Replication

```python
import boto3
import time

s3 = boto3.client('s3', region_name='eu-west-2')
s3_us = boto3.client('s3', region_name='us-east-2')

# Upload to EU
s3.put_object(Bucket='my-bucket-eu-west-2', Key='test.txt', Body=b'test')

# Wait a bit
time.sleep(30)

# Check if replicated to US
try:
    s3_us.head_object(Bucket='my-bucket-us-east-2', Key='test.txt')
    print("✓ Replication working!")
except:
    print("✗ Not yet replicated (wait longer)")
```

## 🐛 Troubleshooting

### MRAP Status Stuck on CREATING

**Normal!** MRAP creation can take up to 24 hours. Check periodically:

```bash
watch -n 300 'terraform output mrap_status'  # Check every 5 minutes
```

### Objects Not Replicating

1. ✅ Check versioning is enabled:
   ```bash
   aws s3api get-bucket-versioning --bucket my-bucket-eu-west-2
   ```

2. ✅ Check replication rule is active:
   ```bash
   aws s3api get-bucket-replication --bucket my-bucket-eu-west-2
   ```

3. ✅ Check CloudWatch metrics for replication lag

### Presigned URLs Return 403

1. ✅ Check MRAP status is `READY`
2. ✅ Verify IAM permissions include MRAP access
3. ✅ Ensure boto3 client has `use_arn_region: True`

### Error: "The ARN is not supported for this operation"

**Fix:** Enable `use_arn_region` in boto3 config:

```python
from botocore.config import Config
import boto3

s3 = boto3.client('s3', config=Config(s3={'use_arn_region': True}))
```

## 🔄 Updates and Changes

### Changing MRAP Configuration

```bash
# Update terraform.tfvars with new values
vim terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

### Adding More Regions

Edit `main.tf` and add additional buckets and replication rules. For example, to add `ap-southeast-1`:

1. Add provider for new region
2. Add bucket resource
3. Add versioning resource
4. Add replication rules
5. Add region to MRAP configuration

### Removing MRAP

```bash
# This will destroy MRAP but keep buckets
terraform destroy

# Warning: MRAP deletion can also take several hours!
```

## 📚 Additional Resources

- **`BOTO3_CLIENT_CONFIGURATION.md`** - Complete developer guide
- [AWS MRAP Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiRegionAccessPoints.html)
- [S3 Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [S3 Presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/PresignedUrlUploadObject.html)

## ❓ FAQ

**Q: Can developers still upload directly to eu-west-2?**  
A: Yes! Uploads work exactly as before. MRAP is only for generating presigned URLs.

**Q: What happens if an object hasn't replicated yet?**  
A: MRAP automatically fetches from the source region (eu-west-2) until replication completes.

**Q: Do we need to change our upload code?**  
A: No! Only presigned URL generation needs to change. See `BOTO3_CLIENT_CONFIGURATION.md`.

**Q: Can we test before going to production?**  
A: Yes! Use environment variables to toggle between MRAP and direct bucket access.

**Q: What if we want to add more regions later?**  
A: Easy! Just edit `main.tf` to add more buckets and update the MRAP configuration.

## 🎉 Success Criteria

After deployment, you should have:

- ✅ MRAP status is `READY`
- ✅ Objects replicate from eu-west-2 → us-east-2 within 15 minutes
- ✅ Presigned URLs work from both regions
- ✅ EU users download from eu-west-2 (verify with VPN/proxy)
- ✅ US users download from us-east-2 (verify with VPN/proxy)
- ✅ CloudWatch metrics show successful replication

## 📞 Support

For issues:
1. Check `BOTO3_CLIENT_CONFIGURATION.md` for code examples
2. Review troubleshooting section above
3. Check AWS CloudWatch for replication metrics
4. Verify MRAP status with `terraform output mrap_status`

---

**Ready to get started?**

```bash
# 1. Configure
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# 2. Deploy
terraform init
terraform apply

# 3. Wait for MRAP to become READY (up to 24 hours)
terraform output mrap_status

# 4. Update developer code (see BOTO3_CLIENT_CONFIGURATION.md)
```

🚀 Your users will thank you for the improved download speeds!

