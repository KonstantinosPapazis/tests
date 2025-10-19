# How to Verify S3 Traffic Goes Through VPC Endpoint (Not Internet)

## The Question

You have a URL like: `https://my-bucket.s3.amazonaws.com/file.jpg`

This uses the **global endpoint** (no region). How do you verify it's using your Gateway VPC Endpoint and NOT going through the public internet?

---

## Method 1: Check VPC Flow Logs (Most Reliable)

### Step 1: Enable VPC Flow Logs (if not already enabled)

```bash
# Enable VPC Flow Logs for your VPC
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::ACCOUNT-ID:role/VPCFlowLogsRole
```

Or via Terraform:

```hcl
resource "aws_flow_log" "vpc" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
}
```

### Step 2: Make a request and check Flow Logs

```bash
# From your EC2 instance, download a file
curl -o /tmp/test.jpg "https://my-bucket.s3.amazonaws.com/file.jpg"

# Wait 1-2 minutes for logs to appear, then check
aws logs filter-log-events \
  --log-group-name /aws/vpc/flowlogs \
  --start-time $(($(date +%s) - 300))000 \
  --filter-pattern "[version, account, eni, source, destination, srcport, destport=443, protocol=6, packets, bytes, start, end, action=ACCEPT, status]" \
  --query 'events[*].message' \
  --output text
```

### Step 3: Interpret the Results

Look for the **destination IP** in the flow logs:

```
2 123456789012 eni-xxxxx 10.0.1.50 52.219.XX.XX 54321 443 6 15 8000 1234567890 1234567891 ACCEPT OK
                          ^^^^^^^^  ^^^^^^^^^^^
                          Source    Destination IP
```

**Check the destination IP range:**

```bash
# Get S3 prefix list (IPs used by S3 in your region)
aws ec2 describe-prefix-lists \
  --filters "Name=prefix-list-name,Values=com.amazonaws.us-east-1.s3" \
  --query 'PrefixLists[0].Cidrs' \
  --output table

# Output example:
# ----------------------
# |                    |
# |  52.216.0.0/15     |  ← These are S3 IPs in the prefix list
# |  54.231.0.0/16     |
# |  3.5.0.0/19        |
# ----------------------
```

**✅ If destination IP is in the S3 prefix list** → Traffic uses VPC Endpoint (private)
**❌ If destination IP is NOT in prefix list** → Traffic uses Internet Gateway (public)

---

## Method 2: Check Route Tables

### Verify VPC Endpoint is in Route Tables

```bash
# List your VPC endpoints
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.us-east-1.s3" \
  --query 'VpcEndpoints[*].[VpcEndpointId,State,RouteTableIds]' \
  --output table

# Example output:
# vpce-xxxxx  available  ['rtb-xxxxx', 'rtb-yyyyy']
```

### Check if your subnet's route table has the VPC endpoint

```bash
# Find your EC2 instance's subnet
INSTANCE_ID="i-xxxxx"
SUBNET_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].SubnetId' \
  --output text)

echo "Instance subnet: $SUBNET_ID"

# Get the route table for this subnet
ROUTE_TABLE_ID=$(aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'RouteTables[0].RouteTableId' \
  --output text)

echo "Route table: $ROUTE_TABLE_ID"

# Check if VPC endpoint is in this route table
aws ec2 describe-route-tables \
  --route-table-ids $ROUTE_TABLE_ID \
  --query 'RouteTables[0].Routes[*].[DestinationPrefixListId,GatewayId]' \
  --output table

# Look for entries like:
# pl-xxxxx (prefix list ID)  vpce-xxxxx (VPC endpoint ID)
```

**✅ If you see `pl-xxxxx → vpce-xxxxx`** → Traffic will use VPC Endpoint
**❌ If no prefix list entry** → Traffic will use Internet Gateway

---

## Method 3: DNS Resolution Test

From your EC2 instance, check what IPs S3 domains resolve to:

```bash
# SSH to your EC2 instance
ssh ec2-user@your-ec2-instance

# Test DNS resolution for both endpoints
echo "=== Global Endpoint ==="
nslookup my-bucket.s3.amazonaws.com

echo -e "\n=== Regional Endpoint ==="
nslookup my-bucket.s3.us-east-1.amazonaws.com

# Better: Use dig for more details
dig my-bucket.s3.amazonaws.com +short
dig my-bucket.s3.us-east-1.amazonaws.com +short
```

**Check if resolved IPs are in S3 prefix list:**

```bash
# Get prefix list CIDRs
S3_CIDRS=$(aws ec2 describe-prefix-lists \
  --region us-east-1 \
  --filters "Name=prefix-list-name,Values=com.amazonaws.us-east-1.s3" \
  --query 'PrefixLists[0].Cidrs[]' \
  --output text)

echo "S3 Prefix List CIDRs:"
echo "$S3_CIDRS"

# Resolve S3 endpoint
S3_IP=$(dig +short my-bucket.s3.amazonaws.com | head -1)
echo -e "\nS3 endpoint resolves to: $S3_IP"

# Check if IP is in any CIDR range
# (You can use tools like ipcalc or write a script)
```

**Note**: For Gateway VPC Endpoints, DNS resolution is the same, but routing is different (handled at route table level).

---

## Method 4: Network Trace (tcpdump/Wireshark)

From your EC2 instance, capture traffic to see the actual network path:

```bash
# Install tcpdump if needed
sudo yum install -y tcpdump

# Capture HTTPS traffic to S3
sudo tcpdump -i any -n 'host my-bucket.s3.amazonaws.com or port 443' -w /tmp/s3-traffic.pcap

# In another terminal, make the S3 request
curl -o /tmp/test.jpg "https://my-bucket.s3.amazonaws.com/file.jpg"

# Stop tcpdump (Ctrl+C)

# Analyze the capture
sudo tcpdump -r /tmp/s3-traffic.pcap -n | head -20
```

**What to look for:**
- Check destination IPs
- Compare against S3 prefix list
- Look for local (VPC) routing vs external routing

---

## Method 5: Traceroute Analysis

```bash
# From EC2 instance
sudo yum install -y traceroute

# Trace route to global endpoint
traceroute my-bucket.s3.amazonaws.com

# Trace route to regional endpoint
traceroute my-bucket.s3.us-east-1.amazonaws.com
```

**Interpretation:**

```bash
# ✅ VPC Endpoint routing (minimal hops):
traceroute to my-bucket.s3.amazonaws.com (52.219.XX.XX)
 1  * * *                              # Local gateway
 2  52.219.XX.XX  1.234 ms             # S3 IP directly

# ❌ Internet Gateway routing (many hops):
traceroute to my-bucket.s3.amazonaws.com (54.231.XX.XX)
 1  10.0.1.1  0.5 ms                   # VPC gateway
 2  172.16.0.1  1.2 ms                 # Internet gateway
 3  external-ip-1  5.4 ms              # Public internet
 4  external-ip-2  8.3 ms              # Public internet
 5  ... multiple hops ...
 10 54.231.XX.XX  15.2 ms              # S3 IP
```

**Key indicators of VPC Endpoint:**
- Very few hops (1-3)
- Low latency (< 2ms)
- All IPs in AWS private ranges

**Key indicators of Internet Gateway:**
- Many hops (5-15)
- Higher latency (10-50ms)
- External IPs visible

---

## Method 6: CloudWatch Metrics

Check VPC Endpoint metrics in CloudWatch:

```bash
# Get bytes transferred through VPC endpoint
aws cloudwatch get-metric-statistics \
  --namespace AWS/VPC \
  --metric-name BytesTransferred \
  --dimensions Name=VpcEndpointId,Value=vpce-xxxxx \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-east-1

# Get packet count
aws cloudwatch get-metric-statistics \
  --namespace AWS/VPC \
  --metric-name PacketsTransferred \
  --dimensions Name=VpcEndpointId,Value=vpce-xxxxx \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-east-1
```

**✅ If you see traffic in VPC endpoint metrics** → Using VPC Endpoint
**❌ If no traffic in VPC endpoint metrics** → Using Internet Gateway

---

## Method 7: S3 Access Logs Analysis

Enable S3 server access logging and check the requester IP:

```bash
# Enable S3 access logging
aws s3api put-bucket-logging \
  --bucket my-bucket \
  --bucket-logging-status '{
    "LoggingEnabled": {
      "TargetBucket": "my-logs-bucket",
      "TargetPrefix": "s3-access-logs/"
    }
  }'

# After making requests, check the logs
aws s3 cp s3://my-logs-bucket/s3-access-logs/ . --recursive

# Look at the logs
cat s3-access-logs/* | grep "file.jpg"
```

**Example log entry:**
```
79a59df900b949e55d96a1e698fbacedfd6e09d98eacf8f8d5218e7cd47ef2be my-bucket [06/Feb/2024:00:00:01 +0000] 10.0.1.50 ...
                                                                                                              ^^^^^^^^
                                                                                                              Source IP
```

**✅ If source IP is private (10.x.x.x, 172.16-31.x.x, 192.168.x.x)** → VPC Endpoint
**❌ If source IP is public** → Internet Gateway

---

## Method 8: Python Script to Test Everything

Here's a comprehensive test script:

```python
#!/usr/bin/env python3
"""
Test if S3 requests go through VPC Endpoint or Internet.
Run this from an EC2 instance in your VPC.
"""

import boto3
import socket
import subprocess
import requests
from urllib.parse import urlparse

def check_vpc_endpoint_routing(bucket_name, region='us-east-1'):
    """
    Comprehensive check if S3 traffic uses VPC endpoint.
    """
    print("="*80)
    print("S3 VPC ENDPOINT TRAFFIC VERIFICATION")
    print("="*80)
    
    # Test both endpoints
    endpoints = {
        'global': f'https://{bucket_name}.s3.amazonaws.com',
        'regional': f'https://{bucket_name}.s3.{region}.amazonaws.com'
    }
    
    ec2 = boto3.client('ec2', region_name=region)
    
    # Get S3 prefix list
    print("\n1️⃣  Fetching S3 Prefix List...")
    prefix_lists = ec2.describe_prefix_lists(
        Filters=[{'Name': 'prefix-list-name', 'Values': [f'com.amazonaws.{region}.s3']}]
    )
    
    if prefix_lists['PrefixLists']:
        s3_cidrs = prefix_lists['PrefixLists'][0]['Cidrs']
        print(f"   S3 Prefix List CIDRs: {', '.join(s3_cidrs)}")
    else:
        print("   ⚠️  Could not fetch S3 prefix list")
        s3_cidrs = []
    
    # Check VPC endpoints
    print("\n2️⃣  Checking VPC Endpoints...")
    vpc_endpoints = ec2.describe_vpc_endpoints(
        Filters=[{'Name': 'service-name', 'Values': [f'com.amazonaws.{region}.s3']}]
    )
    
    if vpc_endpoints['VpcEndpoints']:
        for vpce in vpc_endpoints['VpcEndpoints']:
            print(f"   VPC Endpoint: {vpce['VpcEndpointId']}")
            print(f"   State: {vpce['State']}")
            print(f"   Route Tables: {', '.join(vpce['RouteTableIds'])}")
    else:
        print("   ❌ NO VPC ENDPOINT FOUND!")
        return
    
    # Test DNS resolution
    print("\n3️⃣  Testing DNS Resolution...")
    for endpoint_type, url in endpoints.items():
        hostname = urlparse(url).netloc
        try:
            ip_addresses = socket.gethostbyname_ex(hostname)[2]
            print(f"\n   {endpoint_type.upper()} endpoint ({hostname}):")
            for ip in ip_addresses:
                print(f"   → {ip}")
                
                # Check if IP is in S3 prefix list (simplified check)
                in_prefix_list = any(
                    ip.startswith(cidr.split('/')[0].rsplit('.', 1)[0])
                    for cidr in s3_cidrs
                )
                if in_prefix_list:
                    print(f"      ✅ IP in S3 prefix list (likely VPC endpoint)")
                else:
                    print(f"      ⚠️  IP not obviously in S3 prefix list")
        except Exception as e:
            print(f"   ❌ Error resolving {hostname}: {e}")
    
    # Test connectivity
    print("\n4️⃣  Testing Connectivity...")
    for endpoint_type, url in endpoints.items():
        try:
            response = requests.head(f"{url}/", timeout=5)
            print(f"   {endpoint_type.upper()}: ✅ Reachable (Status: {response.status_code})")
        except Exception as e:
            print(f"   {endpoint_type.upper()}: ❌ Error: {e}")
    
    # Traceroute test
    print("\n5️⃣  Traceroute Test...")
    print("   (Running traceroute to check network path)")
    
    for endpoint_type, url in endpoints.items():
        hostname = urlparse(url).netloc
        print(f"\n   {endpoint_type.upper()} endpoint:")
        try:
            result = subprocess.run(
                ['traceroute', '-m', '5', '-w', '1', hostname],
                capture_output=True,
                text=True,
                timeout=10
            )
            lines = result.stdout.split('\n')[:6]
            for line in lines:
                if line.strip():
                    print(f"   {line}")
            
            # Analyze hop count
            hop_count = len([l for l in lines if l.strip() and l[0].isdigit()])
            if hop_count <= 3:
                print(f"   ✅ Few hops ({hop_count}) - likely VPC endpoint")
            else:
                print(f"   ⚠️  Many hops ({hop_count}) - might be internet routing")
        except Exception as e:
            print(f"   ⚠️  Traceroute failed: {e}")
    
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)
    print("\nTo be CERTAIN traffic uses VPC endpoint:")
    print("1. Check VPC Flow Logs after making real requests")
    print("2. Verify destination IPs are in S3 prefix list")
    print("3. Check CloudWatch metrics for VPC endpoint traffic")
    print("\nFor Gateway VPC Endpoints:")
    print("- Both global and regional endpoints should work")
    print("- Traffic is routed based on route tables, not DNS")
    print("- Flow Logs are the definitive proof")
    print("="*80 + "\n")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) < 2:
        print("Usage: python verify_vpc_endpoint_traffic.py <bucket-name> [region]")
        print("\nExample: python verify_vpc_endpoint_traffic.py my-bucket us-east-1")
        sys.exit(1)
    
    bucket_name = sys.argv[1]
    region = sys.argv[2] if len(sys.argv) > 2 else 'us-east-1'
    
    check_vpc_endpoint_routing(bucket_name, region)
```

Save this as `verify_vpc_endpoint_traffic.py` and run from an EC2 instance:

```bash
python verify_vpc_endpoint_traffic.py my-bucket us-east-1
```

---

## Quick Answer to Your Question

For the URL `https://my-bucket.s3.amazonaws.com/file.jpg`:

### From EC2 in VPC with Gateway VPC Endpoint:

**Method 1 (Quickest):** Check route table
```bash
# Get your instance's route table
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=YOUR_SUBNET_ID" \
  --query 'RouteTables[0].Routes[?GatewayId && starts_with(GatewayId, `vpce-`)]' \
  --output table

# ✅ If you see vpce-xxxxx → Traffic uses VPC Endpoint
# ❌ If empty → Traffic uses Internet Gateway
```

**Method 2 (Most Reliable):** VPC Flow Logs
```bash
# Download the file
curl -o /tmp/test.jpg "https://my-bucket.s3.amazonaws.com/file.jpg"

# Wait 2 minutes, then check flow logs
aws logs tail /aws/vpc/flowlogs --since 5m --filter-pattern "443 6 ACCEPT"

# Look at destination IPs and compare to S3 prefix list
```

---

## The Answer

**YES**, `https://my-bucket.s3.amazonaws.com/file.jpg` (global endpoint) **WILL use your Gateway VPC Endpoint** if:

1. ✅ Gateway VPC Endpoint exists for S3
2. ✅ Your subnet's route table includes the VPC endpoint
3. ✅ Request originates from within the VPC

**Why?** Gateway VPC Endpoints work at the **route table level** using **prefix lists** that include ALL S3 IP ranges (both global and regional endpoints).

The endpoint URL format (global vs regional) **doesn't matter** for Gateway VPC Endpoints - the routing decision is made by the route table, not DNS!

---

## Recommended Verification Steps

1. **Quick check**: Verify route table has VPC endpoint
2. **Definitive proof**: Enable VPC Flow Logs and check destination IPs
3. **Performance test**: Compare latency (VPC endpoint should be 1-5ms)
4. **CloudWatch**: Check VPC endpoint metrics show traffic

The **VPC Flow Logs** method is the most reliable and definitive proof!

