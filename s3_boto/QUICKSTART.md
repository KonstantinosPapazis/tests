# S3 VPC Endpoint + Direct Connect - Quick Start Guide

## ⚠️ CRITICAL ISSUE: Regional Endpoints in Presigned URLs

### The Problem

When developers create an S3 client with a specific region, boto3 may still generate presigned URLs using the **legacy global endpoint** (`s3.amazonaws.com`) instead of the **regional endpoint** (`s3.region.amazonaws.com`).

This causes:
- ❌ Traffic bypasses VPC endpoint
- ❌ Goes over public internet instead of Direct Connect Private VIF
- ❌ Defeats the purpose of VPC endpoints for private connectivity

### Quick Test

Run this to check your current setup:

```python
import boto3

# Your current code (probably)
s3_client = boto3.client('s3', region_name='us-east-1')
url = s3_client.generate_presigned_url(
    'get_object',
    Params={'Bucket': 'my-bucket', 'Key': 'test.txt'},
    ExpiresIn=3600
)
print(f"URL: {url}")

# Check if region is in the URL
if 'us-east-1' not in url:
    print("❌ PROBLEM: Regional endpoint NOT in URL!")
    print("   Traffic may bypass VPC endpoint and Direct Connect!")
else:
    print("✅ OK: Regional endpoint in URL")
```

---

## Solution 1: Gateway VPC Endpoint (Recommended)

### For Direct Connect Private Connectivity

```python
import boto3
from botocore.config import Config

def create_s3_client_for_vpc_endpoint(region='us-east-1'):
    """
    Create S3 client that generates presigned URLs with regional endpoints.
    This ensures traffic routes through VPC endpoint and Direct Connect Private VIF.
    """
    s3_client = boto3.client(
        's3',
        region_name=region,
        config=Config(
            signature_version='s3v4',
            s3={
                'addressing_style': 'virtual',
                'use_dualstack_endpoint': False  # Force regional endpoint
            }
        )
    )
    return s3_client

# Usage
s3_client = create_s3_client_for_vpc_endpoint(region='us-east-1')

# Regular operations
s3_client.upload_file('local.txt', 'my-bucket', 'remote.txt')
s3_client.download_file('my-bucket', 'remote.txt', 'local.txt')

# Presigned URLs will now include the region
presigned_url = s3_client.generate_presigned_url(
    'get_object',
    Params={'Bucket': 'my-bucket', 'Key': 'remote.txt'},
    ExpiresIn=3600
)
print(f"Presigned URL: {presigned_url}")
# Output: https://my-bucket.s3.us-east-1.amazonaws.com/remote.txt?...
```

### Verification

```python
def verify_presigned_url_endpoint(url, expected_region):
    """Verify presigned URL uses regional endpoint"""
    if expected_region in url:
        print(f"✅ Presigned URL uses regional endpoint: {expected_region}")
        return True
    elif 's3.amazonaws.com' in url:
        print(f"❌ WARNING: Presigned URL uses legacy endpoint (no region)")
        print(f"   This may bypass VPC endpoint!")
        return False
    return False

# Check your URLs
url = s3_client.generate_presigned_url('get_object', Params={'Bucket': 'my-bucket', 'Key': 'test.txt'})
verify_presigned_url_endpoint(url, 'us-east-1')
```

---

## Solution 2: Interface VPC Endpoint (Advanced)

For Interface VPC Endpoints, you **MUST** specify the `endpoint_url`:

```python
import boto3
from botocore.config import Config

def create_s3_client_with_interface_endpoint(vpce_id, region='us-east-1'):
    """
    Create S3 client for Interface VPC Endpoint.
    Presigned URLs will include the VPC endpoint hostname.
    """
    endpoint_url = f'https://bucket.vpce-{vpce_id}.s3.{region}.vpce.amazonaws.com'
    
    s3_client = boto3.client(
        's3',
        region_name=region,
        endpoint_url=endpoint_url,  # CRITICAL: Ensures presigned URLs use VPC endpoint
        config=Config(
            signature_version='s3v4',
            s3={'addressing_style': 'path'}
        )
    )
    return s3_client

# Usage (replace with your VPC Endpoint ID)
VPCE_ID = 'vpce-1234567890abcdef0'
s3_client = create_s3_client_with_interface_endpoint(VPCE_ID, region='us-east-1')

# Presigned URLs will use the Interface VPC Endpoint
presigned_url = s3_client.generate_presigned_url(
    'get_object',
    Params={'Bucket': 'my-bucket', 'Key': 'test.txt'},
    ExpiresIn=3600
)
print(f"Presigned URL: {presigned_url}")
# Output: https://my-bucket.bucket.vpce-xxxxx.s3.us-east-1.vpce.amazonaws.com/test.txt?...
```

---

## Traffic Flow Comparison

### ❌ Without Regional Endpoint Configuration

```
Client → presigned URL (s3.amazonaws.com)
      → DNS resolves to PUBLIC S3 endpoint
      → Traffic goes over PUBLIC INTERNET
      → Bypasses VPC endpoint
      → Bypasses Direct Connect Private VIF
```

### ✅ With Regional Endpoint Configuration

```
Client (in VPC) → presigned URL (s3.us-east-1.amazonaws.com)
                → DNS resolves based on VPC route tables
                → Traffic routes through VPC GATEWAY ENDPOINT
                → Goes over AWS PRIVATE BACKBONE
                → Uses Direct Connect Private VIF to on-premises
```

### ✅ With Interface VPC Endpoint

```
Client (in VPC) → presigned URL (vpce-xxxxx.s3.us-east-1.vpce.amazonaws.com)
                → DNS resolves to Interface VPC Endpoint ENI
                → Traffic routes through INTERFACE VPC ENDPOINT (PrivateLink)
                → Fully private, never leaves AWS network
                → Uses Direct Connect Private VIF to on-premises
```

---

## Infrastructure Requirements

### 1. Gateway VPC Endpoint (Free)

```hcl
# Terraform configuration
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.us-east-1.s3"
  
  route_table_ids = [
    aws_route_table.private.id
  ]
  
  tags = {
    Name = "s3-gateway-vpc-endpoint"
  }
}
```

### 2. Interface VPC Endpoint (~$0.01/hour + data)

```hcl
resource "aws_vpc_endpoint" "s3_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type   = "Interface"
  
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]
  
  security_group_ids = [
    aws_security_group.vpc_endpoint.id
  ]
  
  private_dns_enabled = true
  
  tags = {
    Name = "s3-interface-vpc-endpoint"
  }
}

# Security group for Interface endpoint
resource "aws_security_group" "vpc_endpoint" {
  name_description = "Allow S3 traffic to Interface VPC Endpoint"
  vpc_id          = aws_vpc.main.id
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

### 3. Direct Connect Private VIF

```hcl
resource "aws_dx_private_virtual_interface" "main" {
  connection_id = aws_dx_connection.main.id
  
  name           = "s3-private-vif"
  vlan           = 100
  address_family = "ipv4"
  bgp_asn        = 65000
  
  # Connect to VPC via Virtual Private Gateway
  vpn_gateway_id = aws_vpn_gateway.main.id
}
```

---

## Checklist for Your Application

- [ ] VPC Gateway Endpoint or Interface Endpoint for S3 created
- [ ] Route tables configured (for Gateway endpoint)
- [ ] Security groups allow HTTPS/443 (for Interface endpoint)
- [ ] Direct Connect Private VIF connected to VPC
- [ ] S3 client created with regional endpoint configuration
- [ ] Presigned URLs verified to include region or VPC endpoint
- [ ] Tested traffic flow through VPC endpoint (VPC Flow Logs)
- [ ] Verified requests stay on AWS backbone (no public internet)

---

## Testing Your Setup

### 1. Check Presigned URL Format

```python
from s3_vpc_endpoint_example import demonstrate_regional_endpoint_issue

# Run the demonstration
demonstrate_regional_endpoint_issue('my-bucket', 'test.txt', 'us-east-1')
```

### 2. Verify VPC Flow Logs

Check VPC Flow Logs to confirm traffic is using VPC endpoint:

```bash
# Look for traffic to S3 prefix list (for Gateway endpoint)
aws ec2 describe-prefix-lists --filters "Name=prefix-list-name,Values=com.amazonaws.us-east-1.s3"

# Check VPC endpoint metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/VPC \
  --metric-name BytesTransferred \
  --dimensions Name=VpcEndpointId,Value=vpce-xxxxx \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

### 3. Test from EC2 Instance

```bash
# SSH to EC2 instance in VPC
ssh ec2-user@<instance-ip>

# Test S3 connectivity
aws s3 ls s3://my-bucket/

# Check which endpoint is being used
aws s3 ls s3://my-bucket/ --debug 2>&1 | grep -i endpoint

# For Gateway endpoints, you should see regional endpoint
# For Interface endpoints, you should see VPC endpoint hostname
```

---

## Common Mistakes

### ❌ Mistake 1: Not specifying region in S3 client
```python
s3_client = boto3.client('s3')  # BAD: No region specified
```

### ❌ Mistake 2: Using default client configuration
```python
s3_client = boto3.client('s3', region_name='us-east-1')  # BAD: May use legacy endpoint
```

### ❌ Mistake 3: Not verifying presigned URL format
```python
url = s3_client.generate_presigned_url(...)
# Never checking if 'region' is in the URL
```

### ✅ Correct Approach
```python
from s3_vpc_endpoint_example import create_s3_client_with_gateway_endpoint

s3_client = create_s3_client_with_gateway_endpoint(region='us-east-1', use_regional_endpoint=True)
url = s3_client.generate_presigned_url(...)

# Always verify
assert 'us-east-1' in url, "Regional endpoint not in presigned URL!"
```

---

## Need Help?

1. Review the full examples in `s3_vpc_endpoint_example.py`
2. Check the detailed README.md
3. Run the demonstration: `python s3_vpc_endpoint_example.py` (uncomment Example 0)

## Quick Links

- **VPC Endpoints**: [AWS Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- **Direct Connect**: [AWS Documentation](https://docs.aws.amazon.com/directconnect/)
- **S3 Access Points**: [AWS Documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-points.html)

