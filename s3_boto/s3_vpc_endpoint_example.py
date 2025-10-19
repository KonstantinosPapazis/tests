"""
S3 with VPC Endpoint - Boto3 Example

This example shows how to configure boto3 to use S3 through a VPC endpoint,
ensuring traffic flows through AWS backbone via Direct Connect (Private VIF)
instead of the public internet.

Prerequisites:
- VPC Endpoint for S3 created (Gateway or Interface type)
- EC2/Lambda running in VPC with proper security groups
- Route tables configured to use VPC endpoint
"""

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ==============================================================================
# OPTION 1: Using Gateway VPC Endpoint (Most Common)
# ==============================================================================
def create_s3_client_with_gateway_endpoint(region='us-east-1', use_regional_endpoint=True):
    """
    Gateway VPC endpoints automatically route S3 traffic privately.
    No special endpoint URL needed - just ensure your VPC has the endpoint configured.
    
    Args:
        region: AWS region (e.g., 'us-east-1')
        use_regional_endpoint: If True, forces regional endpoint in presigned URLs
                              (e.g., s3.us-east-1.amazonaws.com instead of s3.amazonaws.com)
    
    IMPORTANT CLARIFICATION:
    - Gateway VPC Endpoints work at the ROUTE TABLE level using prefix lists
    - They intercept traffic for BOTH global (s3.amazonaws.com) and regional endpoints
    - HOWEVER: For Direct Connect Private VIF, using regional endpoints is CRITICAL
    
    Why regional endpoints matter:
    1. Global endpoint (s3.amazonaws.com) may resolve to public IP ranges
    2. Regional endpoint (s3.region.amazonaws.com) ensures proper VPC routing
    3. With Direct Connect, this determines Private VIF vs Public VIF usage
    4. Clarity: Makes it explicit which region you're accessing
    
    The developer's mistake was likely:
    - Not specifying region at all, OR
    - Boto3 defaulting to global endpoint in some SDK versions/configurations
    """
    # Standard boto3 client - will automatically use Gateway VPC Endpoint
    # if your EC2/Lambda is in a VPC with a Gateway Endpoint for S3
    
    s3_config = {
        'addressing_style': 'virtual'  # virtual-hosted-style for better compatibility
    }
    
    # Force regional endpoint for presigned URLs
    # NOTE: Setting use_dualstack_endpoint=False helps, but boto3's behavior
    # can vary based on SDK version and bucket location
    if use_regional_endpoint:
        s3_config['use_dualstack_endpoint'] = False
        # Endpoint will be: https://bucket-name.s3.region.amazonaws.com
    
    s3_client = boto3.client(
        's3',
        region_name=region,
        config=Config(
            signature_version='s3v4',
            s3=s3_config
        )
    )
    return s3_client


# ==============================================================================
# OPTION 2: Using Interface VPC Endpoint (PrivateLink)
# ==============================================================================
def create_s3_client_with_interface_endpoint(vpce_id, region='us-east-1'):
    """
    Interface VPC endpoints require explicit endpoint URL configuration.
    
    IMPORTANT: When you specify endpoint_url, ALL requests including presigned URLs
    will use this endpoint. This ensures traffic goes through the Interface VPC endpoint.
    
    Args:
        vpce_id: Your VPC Endpoint ID (e.g., 'vpce-1234567890abcdef0')
        region: AWS region
    """
    # Interface endpoint URL format - this will be used in presigned URLs too
    endpoint_url = f'https://bucket.vpce-{vpce_id}.s3.{region}.vpce.amazonaws.com'
    
    s3_client = boto3.client(
        's3',
        region_name=region,
        endpoint_url=endpoint_url,  # CRITICAL: This makes presigned URLs use VPC endpoint
        config=Config(
            signature_version='s3v4',
            s3={'addressing_style': 'path'}
        )
    )
    return s3_client


# ==============================================================================
# Generate Presigned URLs with VPC Endpoint
# ==============================================================================
def generate_presigned_url_via_vpc_endpoint(bucket_name, object_key, region='us-east-1', expiration=3600):
    """
    Generate presigned URLs that work through VPC endpoint.
    
    CRITICAL ISSUE: By default, boto3 may generate presigned URLs with:
    - https://bucket-name.s3.amazonaws.com/key (legacy global endpoint)
    - https://bucket-name.s3.us-east-1.amazonaws.com/key (regional endpoint)
    
    For Gateway VPC Endpoints:
    - Presigned URLs will use public endpoint format, but requests from within
      the VPC will automatically route through the VPC endpoint due to route tables.
    - The regional endpoint format is recommended for clarity.
    
    For Interface VPC Endpoints:
    - MUST specify endpoint_url when creating client to ensure presigned URLs
      contain the VPC endpoint hostname.
    """
    # Always specify region to ensure regional endpoint in presigned URLs
    s3_client = create_s3_client_with_gateway_endpoint(region=region, use_regional_endpoint=True)
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': bucket_name,
                'Key': object_key
            },
            ExpiresIn=expiration
        )
        logger.info(f"Generated presigned URL with regional endpoint: {presigned_url}")
        
        # Verify the URL contains the region
        if region not in presigned_url and 's3.amazonaws.com' in presigned_url:
            logger.warning(f"⚠️  Presigned URL using legacy endpoint without region!")
            logger.warning(f"   This may not route through VPC endpoint properly.")
            logger.warning(f"   URL: {presigned_url}")
        
        return presigned_url
    except ClientError as e:
        logger.error(f"Error generating presigned URL: {e}")
        raise


def generate_presigned_url_with_interface_endpoint(bucket_name, object_key, vpce_id, region='us-east-1', expiration=3600):
    """
    Generate presigned URLs specifically for Interface VPC Endpoints.
    
    The generated URL will look like:
    https://bucket-name.bucket.vpce-xxxxx.s3.region.vpce.amazonaws.com/key
    
    This ensures the presigned URL routes through your Interface VPC endpoint.
    """
    s3_client = create_s3_client_with_interface_endpoint(vpce_id=vpce_id, region=region)
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': bucket_name,
                'Key': object_key
            },
            ExpiresIn=expiration
        )
        logger.info(f"Generated Interface VPC Endpoint presigned URL: {presigned_url}")
        
        # Verify the URL contains the VPC endpoint
        if 'vpce' not in presigned_url:
            logger.error(f"❌ Presigned URL does NOT contain VPC endpoint!")
            logger.error(f"   This will NOT route through Interface VPC endpoint.")
        else:
            logger.info(f"✓ Presigned URL correctly uses Interface VPC endpoint")
        
        return presigned_url
    except ClientError as e:
        logger.error(f"Error generating presigned URL: {e}")
        raise


# ==============================================================================
# Upload/Download Operations via VPC Endpoint
# ==============================================================================
def upload_file_via_vpc_endpoint(bucket_name, file_path, object_key):
    """Upload file to S3 via VPC endpoint"""
    s3_client = create_s3_client_with_gateway_endpoint()
    
    try:
        s3_client.upload_file(file_path, bucket_name, object_key)
        logger.info(f"Successfully uploaded {file_path} to s3://{bucket_name}/{object_key}")
    except ClientError as e:
        logger.error(f"Error uploading file: {e}")
        raise


def download_file_via_vpc_endpoint(bucket_name, object_key, download_path):
    """Download file from S3 via VPC endpoint"""
    s3_client = create_s3_client_with_gateway_endpoint()
    
    try:
        s3_client.download_file(bucket_name, object_key, download_path)
        logger.info(f"Successfully downloaded s3://{bucket_name}/{object_key} to {download_path}")
    except ClientError as e:
        logger.error(f"Error downloading file: {e}")
        raise


# ==============================================================================
# Verify VPC Endpoint Usage
# ==============================================================================
def verify_vpc_endpoint_usage():
    """
    Check if requests are going through VPC endpoint.
    
    Note: You can verify by:
    1. Checking VPC Flow Logs
    2. Monitoring VPC Endpoint metrics in CloudWatch
    3. Using boto3 debug logging to see endpoint resolution
    """
    import os
    
    # Enable debug logging to see endpoint resolution
    boto3.set_stream_logger('boto3.resources', logging.DEBUG)
    
    s3_client = create_s3_client_with_gateway_endpoint()
    
    try:
        # Make a simple API call
        response = s3_client.list_buckets()
        logger.info(f"Successfully connected to S3. Found {len(response['Buckets'])} buckets")
        
        # Check environment for VPC endpoint DNS
        vpce_dns = os.environ.get('AWS_S3_VPCE_DNS')
        if vpce_dns:
            logger.info(f"Using VPC Endpoint DNS: {vpce_dns}")
        
    except ClientError as e:
        logger.error(f"Error connecting to S3: {e}")
        raise


# ==============================================================================
# Resource-based Operations with VPC Endpoint
# ==============================================================================
def use_s3_resource_with_vpc_endpoint(bucket_name):
    """Using boto3 S3 resource instead of client"""
    s3_resource = boto3.resource(
        's3',
        region_name='us-east-1',
        config=Config(
            signature_version='s3v4'
        )
    )
    
    bucket = s3_resource.Bucket(bucket_name)
    
    # List objects
    logger.info(f"Listing objects in {bucket_name}:")
    for obj in bucket.objects.limit(10):
        logger.info(f"  - {obj.key} ({obj.size} bytes)")


# ==============================================================================
# Demonstrate Regional Endpoint Issue in Presigned URLs
# ==============================================================================
def demonstrate_regional_endpoint_issue(bucket_name, object_key, region='us-east-1'):
    """
    COMMON ISSUE: Demonstrates how presigned URLs may not include regional endpoint.
    
    This is the problem mentioned by the user:
    - Developer specifies region when creating S3 client
    - But presigned URL might use legacy s3.amazonaws.com (no region)
    - This can cause issues with VPC endpoints and Direct Connect routing
    """
    print("\n" + "="*80)
    print("DEMONSTRATION: Regional Endpoint in Presigned URLs")
    print("="*80)
    
    # BAD: Client without explicit regional endpoint configuration
    print("\n❌ BAD: Default client (may use legacy endpoint)")
    s3_client_bad = boto3.client('s3', region_name=region)
    url_bad = s3_client_bad.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket_name, 'Key': object_key},
        ExpiresIn=3600
    )
    print(f"URL: {url_bad}")
    if region not in url_bad:
        print(f"⚠️  WARNING: Region '{region}' NOT in URL! Using legacy endpoint.")
    
    # GOOD: Client with regional endpoint enforced
    print("\n✅ GOOD: Client with regional endpoint enforced")
    s3_client_good = create_s3_client_with_gateway_endpoint(region=region, use_regional_endpoint=True)
    url_good = s3_client_good.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket_name, 'Key': object_key},
        ExpiresIn=3600
    )
    print(f"URL: {url_good}")
    if region in url_good:
        print(f"✓ Confirmed: Region '{region}' is in URL!")
    
    # BEST: For Interface VPC Endpoint
    print("\n✅ BEST: Interface VPC Endpoint (fully private)")
    print("For Interface endpoints, you MUST specify endpoint_url:")
    print("Example: endpoint_url='https://bucket.vpce-xxxxx.s3.us-east-1.vpce.amazonaws.com'")
    print("This ensures presigned URLs route through the private Interface endpoint.")
    
    print("\n" + "="*80)
    print("SUMMARY:")
    print("1. Always specify region when creating S3 client")
    print("2. Use use_regional_endpoint=True for Gateway VPC endpoints")
    print("3. Use endpoint_url parameter for Interface VPC endpoints")
    print("4. Verify presigned URLs contain expected endpoint before using")
    print("="*80 + "\n")
    
    return {
        'legacy_url': url_bad,
        'regional_url': url_good,
        'has_region_in_bad': region in url_bad,
        'has_region_in_good': region in url_good
    }


# ==============================================================================
# Example Usage
# ==============================================================================
if __name__ == "__main__":
    # Configuration
    BUCKET_NAME = "your-bucket-name"
    OBJECT_KEY = "example.txt"
    REGION = "us-east-1"
    
    print("\n" + "="*80)
    print("S3 VPC Endpoint Examples")
    print("="*80)
    
    # Example 0: DEMONSTRATE THE REGIONAL ENDPOINT ISSUE (IMPORTANT!)
    print("\n=== Example 0: Regional Endpoint Issue (MUST SEE!) ===")
    print("Uncomment to see the difference between URLs with/without regional endpoints:")
    # demonstrate_regional_endpoint_issue(BUCKET_NAME, OBJECT_KEY, REGION)
    
    # Example 1: Basic operations via Gateway VPC Endpoint
    print("\n=== Example 1: Gateway VPC Endpoint ===")
    # s3_client = create_s3_client_with_gateway_endpoint(region=REGION)
    # print(f"S3 Client created for region: {REGION}")
    
    # Example 2: Generate presigned URL with regional endpoint
    print("\n=== Example 2: Presigned URL with Regional Endpoint ===")
    # presigned_url = generate_presigned_url_via_vpc_endpoint(BUCKET_NAME, OBJECT_KEY, region=REGION)
    # print(f"Presigned URL: {presigned_url}")
    
    # Example 3: Presigned URL with Interface VPC Endpoint
    print("\n=== Example 3: Presigned URL with Interface VPC Endpoint ===")
    # VPCE_ID = "1234567890abcdef0"  # Replace with your VPC Endpoint ID
    # presigned_url = generate_presigned_url_with_interface_endpoint(
    #     BUCKET_NAME, OBJECT_KEY, VPCE_ID, region=REGION
    # )
    # print(f"Interface VPC Endpoint URL: {presigned_url}")
    
    # Example 4: Upload/Download
    print("\n=== Example 4: Upload/Download ===")
    # upload_file_via_vpc_endpoint(BUCKET_NAME, "./local_file.txt", OBJECT_KEY)
    # download_file_via_vpc_endpoint(BUCKET_NAME, OBJECT_KEY, "./downloaded_file.txt")
    
    # Example 5: Verify VPC endpoint usage
    print("\n=== Example 5: Verify VPC Endpoint ===")
    # verify_vpc_endpoint_usage()
    
    print("\n" + "="*80)
    print("✓ All examples loaded. Uncomment specific examples to test.")
    print("⚠️  IMPORTANT: Run Example 0 first to understand the regional endpoint issue!")
    print("="*80 + "\n")


# ==============================================================================
# Terraform/Terragrunt Configuration Notes
# ==============================================================================
"""
To enable VPC Endpoint for S3, add to your Terraform configuration:

# Gateway VPC Endpoint (Recommended for S3)
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${var.region}.s3"
  
  route_table_ids = [
    aws_route_table.private.id
  ]
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::your-bucket-name",
          "arn:aws:s3:::your-bucket-name/*"
        ]
      }
    ]
  })
  
  tags = {
    Name = "s3-vpc-endpoint"
  }
}

# Interface VPC Endpoint (Alternative for more control)
resource "aws_vpc_endpoint" "s3_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.s3"
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
"""

