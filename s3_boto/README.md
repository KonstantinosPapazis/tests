# S3 Boto3 Configuration Examples

This folder contains comprehensive examples for three different S3 access patterns using boto3. Each configuration serves different use cases and has different networking characteristics.

## Overview

| Configuration | Traffic Path | Use Case | Latency | Cost |
|--------------|--------------|----------|---------|------|
| **VPC Endpoint** | AWS Private Backbone via Direct Connect | Private, secure S3 access from VPC | Low (single region) | No additional charge for Gateway endpoints |
| **Transfer Acceleration** | CloudFront Edge Locations (Public) | Fast transfers over long distances | Lowest for distant clients | +$0.04-0.08/GB |
| **MRAP** | Automatic multi-region routing | Global applications, DR scenarios | Lowest (routes to nearest region) | Additional routing charges |

---

## 1. VPC Endpoint (`s3_vpc_endpoint_example.py`)

### What It Does
Routes S3 traffic through AWS's private backbone network via your VPC, bypassing the public internet entirely when used with Direct Connect Private VIF.

### Traffic Flow
```
Your App (VPC) → VPC Endpoint → S3 (via AWS backbone)
           ↓
    Direct Connect (Private VIF) → On-premises
```

### When to Use
- ✅ Security and compliance requirements (no public internet)
- ✅ Using AWS Direct Connect with Private VIF
- ✅ Reducing data transfer costs (no NAT gateway needed)
- ✅ Single-region or known-region access patterns
- ✅ Internal applications within AWS

### Key Features
- **Gateway VPC Endpoint**: Free, prefix list-based routing (most common)
- **Interface VPC Endpoint**: Uses PrivateLink, specific IP addresses
- Works seamlessly with Direct Connect Private VIF
- Presigned URLs work normally

### ⚠️ CRITICAL: Regional Endpoint Issue with Presigned URLs

**COMMON PROBLEM**: Developers specify a region when creating the S3 client, but the presigned URL doesn't include the regional endpoint!

```python
# ❌ BAD: Region specified, but presigned URL may use legacy endpoint
s3_client = boto3.client('s3', region_name='us-east-1')
url = s3_client.generate_presigned_url(...)
# URL might be: https://bucket.s3.amazonaws.com/key  (no region!)
```

**Why this matters:**
- Legacy endpoint (`s3.amazonaws.com`) may not route through VPC endpoint properly
- Can bypass Direct Connect Private VIF and use public internet
- Inconsistent routing behavior across regions

**Solution:**
```python
# ✅ GOOD: Enforce regional endpoint in presigned URLs
from s3_vpc_endpoint_example import create_s3_client_with_gateway_endpoint

s3_client = create_s3_client_with_gateway_endpoint(region='us-east-1', use_regional_endpoint=True)
url = s3_client.generate_presigned_url(...)
# URL will be: https://bucket.s3.us-east-1.amazonaws.com/key  (includes region!)
```

**For Interface VPC Endpoints:**
```python
# ✅ BEST: Use endpoint_url to ensure VPC endpoint routing
from s3_vpc_endpoint_example import create_s3_client_with_interface_endpoint

s3_client = create_s3_client_with_interface_endpoint(vpce_id='vpce-xxxxx', region='us-east-1')
url = s3_client.generate_presigned_url(...)
# URL will be: https://bucket.bucket.vpce-xxxxx.s3.us-east-1.vpce.amazonaws.com/key
```

### Example Usage
```python
from s3_vpc_endpoint_example import create_s3_client_with_gateway_endpoint

# Always specify region and use_regional_endpoint=True
s3_client = create_s3_client_with_gateway_endpoint(region='us-east-1', use_regional_endpoint=True)
s3_client.upload_file('file.txt', 'my-bucket', 'file.txt')

# Presigned URLs will now include the region
url = s3_client.generate_presigned_url('get_object', Params={'Bucket': 'my-bucket', 'Key': 'file.txt'})
```

### Terraform Configuration Required
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.s3"
  route_table_ids = [aws_route_table.private.id]
}
```

---

## 2. Transfer Acceleration (`s3_transfer_acceleration_example.py`)

### What It Does
Routes S3 traffic through CloudFront's global network of edge locations for faster transfers over long distances.

### Traffic Flow
```
Your App → Nearest CloudFront Edge → AWS Backbone → S3 Bucket
```

### When to Use
- ✅ Clients geographically distant from S3 bucket region
- ✅ Large file uploads/downloads from remote locations
- ✅ Need speed improvement of 50-500%
- ✅ Public internet access (not using Direct Connect privately)
- ❌ Not suitable for VPC-only traffic

### Key Features
- Uses `bucket-name.s3-accelerate.amazonaws.com` endpoint
- Automatic routing to nearest CloudFront edge location
- Can improve transfer speeds significantly
- Only charged when it actually accelerates (vs standard S3)
- Requires DNS-compliant bucket names (no periods)

### Example Usage
```python
from s3_transfer_acceleration_example import create_s3_client_with_acceleration

s3_client = create_s3_client_with_acceleration()
s3_client.upload_file('large_file.dat', 'my-bucket', 'large_file.dat')
```

### Terraform Configuration Required
```hcl
resource "aws_s3_bucket_accelerate_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  status = "Enabled"
}
```

### Cost Consideration
- +$0.04 per GB for uploads (US, Europe, Japan)
- +$0.08 per GB for uploads (other regions)
- Only charged when acceleration provides benefit

---

## 3. Multi-Region Access Points / MRAP (`s3_mrap_example.py`)

### What It Does
Provides a single global endpoint that automatically routes requests to the nearest or lowest-latency S3 bucket across multiple regions.

### Traffic Flow
```
Your App → MRAP Global Endpoint → Automatic Routing → Nearest S3 Bucket
                                                      ↓
                                         [us-east-1, eu-west-1, ap-southeast-1]
```

### When to Use
- ✅ Global applications with users in multiple regions
- ✅ Multi-region disaster recovery (active-active)
- ✅ Automatic failover between regions
- ✅ Simplified multi-region architecture
- ✅ Need consistent low latency globally

### Key Features
- Single global endpoint for multiple regional buckets
- Automatic routing to optimal region
- Supports cross-region replication
- Can work with VPC endpoints and Direct Connect
- Requires S3 versioning on all buckets
- Takes up to 24 hours to create/delete

### Example Usage
```python
from s3_mrap_example import create_s3_client_with_mrap, get_mrap_arn

ACCOUNT_ID = "123456789012"
MRAP_ALIAS = "your-mrap-alias"  # From AWS console or API

s3_client = create_s3_client_with_mrap()
mrap_arn = get_mrap_arn(ACCOUNT_ID, MRAP_ALIAS)

# Use MRAP ARN as bucket parameter
s3_client.upload_file('file.txt', mrap_arn, 'file.txt')
```

### Terraform Configuration Required
```hcl
resource "aws_s3control_multi_region_access_point" "main" {
  details {
    name = "my-global-access-point"
    
    region { bucket = aws_s3_bucket.us_east.id }
    region { bucket = aws_s3_bucket.eu_west.id }
  }
}
```

---

## Comparison Matrix

### Direct Connect + Presigned URLs

Your original question about Direct Connect and presigned URLs:

| Configuration | Private via Direct Connect? | Presigned URL Behavior |
|--------------|----------------------------|------------------------|
| Standard S3 + Direct Connect Public VIF | ⚠️ Uses public IP space | Works but routes through public endpoint |
| **VPC Endpoint + Direct Connect Private VIF** | ✅ Fully private AWS backbone | Works, stays on AWS backbone |
| Transfer Acceleration | ❌ Uses public internet/CloudFront | Routes through CloudFront edges |
| MRAP | ⚠️ Can use VPC endpoints | Routes to nearest region automatically |

### Performance Characteristics

| Scenario | Recommended Configuration |
|----------|--------------------------|
| Internal AWS apps (same region) | VPC Endpoint (Gateway) |
| On-prem via Direct Connect | VPC Endpoint + Private VIF |
| Distant client uploads | Transfer Acceleration |
| Global app, multi-region | MRAP |
| Cost-sensitive, single region | VPC Endpoint |
| DR/failover requirement | MRAP with replication |

---

## Getting Started

### Prerequisites
```bash
pip install boto3 botocore
```

### 🚀 Quick Tests: Check Your Current Setup

**Test 1: Check if presigned URLs include regional endpoints**

```bash
python test_presigned_url_endpoint.py your-bucket-name test-file.txt us-east-1
```

This shows if your presigned URLs use regional or global endpoints.

**Test 2: Verify traffic actually uses VPC endpoint (not internet)**

```bash
# Run from EC2 instance in your VPC
python verify_vpc_endpoint_routing.py your-bucket-name i-your-instance-id us-east-1
```

This verifies if `https://bucket.s3.amazonaws.com` routes through VPC endpoint or internet.

### 1. Test VPC Endpoint Configuration
```python
python s3_vpc_endpoint_example.py
# Uncomment the examples you want to run
```

### 2. Test Transfer Acceleration
```python
python s3_transfer_acceleration_example.py
# Make sure bucket has acceleration enabled first
```

### 3. Test MRAP
```python
python s3_mrap_example.py
# Note: MRAP creation takes up to 24 hours
```

---

## Best Practices

### For VPC Endpoints
1. Use Gateway endpoints for S3 (free)
2. Configure route tables properly
3. Use with Direct Connect Private VIF for fully private path
4. Set VPC endpoint policies for additional security

### For Transfer Acceleration
1. Test speed improvement before committing
2. Use for uploads > 1 GB over long distances
3. Monitor costs (only charged when it helps)
4. Bucket names must be DNS-compliant

### For MRAP
1. Enable versioning on all buckets
2. Configure bidirectional replication
3. Use S3 Replication Time Control (RTC) for predictability
4. Plan for 24-hour creation time
5. Monitor replication lag

---

## Security Considerations

### VPC Endpoint
- ✅ Fully private, no internet exposure
- ✅ VPC endpoint policies for access control
- ✅ Works with VPC Flow Logs
- ✅ Compatible with AWS PrivateLink

### Transfer Acceleration
- ⚠️ Uses public internet (CloudFront)
- ⚠️ Presigned URLs still expose access via HTTPS
- ✅ TLS encryption in transit
- ⚠️ Not suitable for compliance requiring private-only access

### MRAP
- ✅ Can use VPC endpoints for private access
- ✅ Centralized policy management
- ✅ Supports cross-account access
- ⚠️ More complex IAM permissions required

---

## Cost Optimization

| Feature | Cost Impact |
|---------|------------|
| VPC Gateway Endpoint | Free |
| VPC Interface Endpoint | ~$0.01/hour + data processing |
| Transfer Acceleration | +$0.04-0.08/GB (only when faster) |
| MRAP | Additional routing charges |
| Cross-region replication | Standard data transfer pricing |

---

## Troubleshooting

### VPC Endpoint Issues

#### ❌ Presigned URLs Not Using Regional Endpoint
**Problem**: Developer specifies region in S3 client, but presigned URL uses `s3.amazonaws.com` (no region).

**Symptoms**:
- Traffic bypasses VPC endpoint
- Goes over public internet instead of Direct Connect Private VIF
- Inconsistent behavior across regions

**Solution**:
```python
# Check your presigned URL format
url = s3_client.generate_presigned_url(...)
print(url)

# If URL is: https://bucket.s3.amazonaws.com/key
# ❌ BAD: Legacy endpoint, no region

# If URL is: https://bucket.s3.us-east-1.amazonaws.com/key
# ✅ GOOD: Regional endpoint included

# Fix: Use create_s3_client_with_gateway_endpoint(region='us-east-1', use_regional_endpoint=True)
```

#### Other VPC Endpoint Issues
- Check route tables include VPC endpoint
- Verify security groups allow S3 traffic (port 443)
- Confirm VPC endpoint policy allows access
- Check VPC Flow Logs for connection attempts
- Verify DNS resolution within VPC

### Transfer Acceleration Issues
- Bucket name must be DNS-compliant (no periods)
- Feature must be enabled on bucket
- Test with speed comparison tool
- May not accelerate for nearby regions
- Not compatible with VPC-only private access

### MRAP Issues
- Allow up to 24 hours for creation
- Verify all buckets have versioning enabled
- Check S3 Control API permissions
- Use ARN format (not bucket name)
- Ensure replication is configured properly

---

## Additional Resources

- [AWS Direct Connect Documentation](https://docs.aws.amazon.com/directconnect/)
- [VPC Endpoints for S3](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- [S3 Transfer Acceleration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/transfer-acceleration.html)
- [Multi-Region Access Points](https://docs.aws.amazon.com/AmazonS3/latest/userguide/MultiRegionAccessPoints.html)

---

## Questions?

For your specific use case with Direct Connect:
- **Private traffic only**: Use VPC Endpoint with Private VIF
- **Fastest global access**: Use MRAP with VPC endpoints
- **Fastest long-distance**: Use Transfer Acceleration (but goes via public internet)

---

## 📚 Documentation Files

This folder contains:

### Documentation
1. **`README.md`** (this file) - Overview of all three configurations
2. **`QUICKSTART.md`** - Quick reference guide for developers
3. **`DIRECT_CONNECT_EXPLAINED.md`** - Deep dive on Direct Connect + presigned URLs issue
4. **`verify_vpc_endpoint_traffic.md`** - How to verify traffic uses VPC endpoint (not internet)

### Testing Scripts
5. **`test_presigned_url_endpoint.py`** - Check if presigned URLs include regional endpoints
6. **`verify_vpc_endpoint_routing.py`** - Verify traffic routes through VPC endpoint

### Code Examples
7. **`s3_vpc_endpoint_example.py`** - VPC Endpoint configuration examples
8. **`s3_transfer_acceleration_example.py`** - Transfer Acceleration examples
9. **`s3_mrap_example.py`** - Multi-Region Access Point examples

### Which file should you read?

- **Have Direct Connect?** → Read `DIRECT_CONNECT_EXPLAINED.md` first!
- **Need quick reference?** → Read `QUICKSTART.md`
- **Want to verify VPC endpoint routing?** → Read `verify_vpc_endpoint_traffic.md`
- **Want to test current setup?** → Run `python test_presigned_url_endpoint.py`
- **Want to verify traffic path?** → Run `python verify_vpc_endpoint_routing.py`
- **Want all details?** → Read this `README.md`

Feel free to modify and adapt these examples for your specific requirements!

