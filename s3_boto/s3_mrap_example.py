"""
S3 Multi-Region Access Points (MRAP) - Boto3 Example

This example shows how to configure boto3 to use S3 Multi-Region Access Points,
which provide a global endpoint for accessing S3 data across multiple regions
with automatic routing to the nearest or lowest-latency region.

Prerequisites:
- S3 buckets in multiple AWS regions
- Multi-Region Access Point created and configured
- Appropriate IAM permissions for MRAP operations
- S3 Control API access

Key Benefits:
- Single global endpoint for multi-region access
- Automatic routing to nearest region
- Active-active configuration for disaster recovery
- Cross-region replication support
- Simplified application architecture

Use Cases:
- Global applications with users in multiple regions
- Multi-region disaster recovery
- Low-latency access from anywhere
- Cross-region failover scenarios
"""

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
import logging
import json
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ==============================================================================
# Create Multi-Region Access Point
# ==============================================================================
def create_multi_region_access_point(account_id, mrap_name, bucket_configs):
    """
    Create a Multi-Region Access Point.
    
    Args:
        account_id: AWS Account ID
        mrap_name: Name for the MRAP (must be globally unique in your account)
        bucket_configs: List of dicts with bucket names and regions
            Example: [
                {'bucket': 'my-bucket-us-east-1', 'region': 'us-east-1'},
                {'bucket': 'my-bucket-eu-west-1', 'region': 'eu-west-1'}
            ]
    """
    s3control_client = boto3.client('s3control')
    
    # Format regions for MRAP
    regions = []
    for config in bucket_configs:
        regions.append({
            'Bucket': f"arn:aws:s3::{account_id}:bucket/{config['bucket']}",
            'BucketAccountId': account_id
        })
    
    try:
        response = s3control_client.create_multi_region_access_point(
            AccountId=account_id,
            ClientToken=f"{mrap_name}-{int(time.time())}",  # Idempotency token
            Details={
                'Name': mrap_name,
                'PublicAccessBlock': {
                    'BlockPublicAcls': True,
                    'IgnorePublicAcls': True,
                    'BlockPublicPolicy': True,
                    'RestrictPublicBuckets': True
                },
                'Regions': regions
            }
        )
        
        request_token = response['RequestTokenARN']
        logger.info(f"MRAP creation initiated. Request token: {request_token}")
        logger.info("Note: MRAP creation can take up to 24 hours to complete")
        
        return request_token
    except ClientError as e:
        logger.error(f"Error creating MRAP: {e}")
        raise


def get_mrap_status(account_id, mrap_name):
    """Check the status of a Multi-Region Access Point"""
    s3control_client = boto3.client('s3control')
    
    try:
        response = s3control_client.get_multi_region_access_point(
            AccountId=account_id,
            Name=mrap_name
        )
        
        mrap = response['AccessPoint']
        status = mrap['Status']
        alias = mrap.get('Alias', 'N/A')
        
        logger.info(f"MRAP Name: {mrap_name}")
        logger.info(f"Status: {status}")
        logger.info(f"Alias: {alias}")
        logger.info(f"Created: {mrap.get('CreatedAt', 'N/A')}")
        
        return {
            'status': status,
            'alias': alias,
            'regions': mrap.get('Regions', [])
        }
    except ClientError as e:
        logger.error(f"Error getting MRAP status: {e}")
        raise


def list_multi_region_access_points(account_id):
    """List all Multi-Region Access Points in the account"""
    s3control_client = boto3.client('s3control')
    
    try:
        response = s3control_client.list_multi_region_access_points(
            AccountId=account_id
        )
        
        mraps = response.get('AccessPoints', [])
        logger.info(f"Found {len(mraps)} Multi-Region Access Points:")
        
        for mrap in mraps:
            logger.info(f"  - {mrap['Name']}: {mrap['Status']} (Alias: {mrap.get('Alias', 'N/A')})")
        
        return mraps
    except ClientError as e:
        logger.error(f"Error listing MRAPs: {e}")
        raise


# ==============================================================================
# Use Multi-Region Access Point for S3 Operations
# ==============================================================================
def create_s3_client_with_mrap():
    """
    Create boto3 S3 client configured to use Multi-Region Access Points.
    
    Important: Must use S3 ARN format for MRAP operations.
    """
    s3_client = boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,  # Required for MRAP
                'addressing_style': 'virtual'
            }
        )
    )
    return s3_client


def get_mrap_arn(account_id, mrap_alias):
    """
    Construct the MRAP ARN from account ID and alias.
    
    Args:
        account_id: AWS Account ID
        mrap_alias: MRAP alias (from get_mrap_status)
    
    Returns:
        MRAP ARN in format: arn:aws:s3::account-id:accesspoint/mrap-alias
    """
    return f"arn:aws:s3::{account_id}:accesspoint/{mrap_alias}"


# ==============================================================================
# Upload/Download Operations via MRAP
# ==============================================================================
def upload_file_via_mrap(mrap_arn, object_key, file_path):
    """
    Upload file using Multi-Region Access Point.
    
    Args:
        mrap_arn: The MRAP ARN (use get_mrap_arn to construct)
        object_key: S3 object key
        file_path: Local file path to upload
    """
    s3_client = create_s3_client_with_mrap()
    
    try:
        # Note: Use MRAP ARN as the "bucket" parameter
        s3_client.upload_file(
            Filename=file_path,
            Bucket=mrap_arn,
            Key=object_key
        )
        logger.info(f"Successfully uploaded {file_path} via MRAP to {object_key}")
    except ClientError as e:
        logger.error(f"Error uploading via MRAP: {e}")
        raise


def download_file_via_mrap(mrap_arn, object_key, download_path):
    """Download file using Multi-Region Access Point"""
    s3_client = create_s3_client_with_mrap()
    
    try:
        s3_client.download_file(
            Bucket=mrap_arn,
            Key=object_key,
            Filename=download_path
        )
        logger.info(f"Successfully downloaded {object_key} via MRAP to {download_path}")
    except ClientError as e:
        logger.error(f"Error downloading via MRAP: {e}")
        raise


def put_object_via_mrap(mrap_arn, object_key, data):
    """Put object using MRAP"""
    s3_client = create_s3_client_with_mrap()
    
    try:
        response = s3_client.put_object(
            Bucket=mrap_arn,
            Key=object_key,
            Body=data
        )
        logger.info(f"Successfully put object {object_key} via MRAP")
        return response
    except ClientError as e:
        logger.error(f"Error putting object via MRAP: {e}")
        raise


def get_object_via_mrap(mrap_arn, object_key):
    """Get object using MRAP"""
    s3_client = create_s3_client_with_mrap()
    
    try:
        response = s3_client.get_object(
            Bucket=mrap_arn,
            Key=object_key
        )
        data = response['Body'].read()
        logger.info(f"Successfully retrieved {object_key} via MRAP ({len(data)} bytes)")
        return data
    except ClientError as e:
        logger.error(f"Error getting object via MRAP: {e}")
        raise


def list_objects_via_mrap(mrap_arn, prefix=''):
    """List objects using MRAP"""
    s3_client = create_s3_client_with_mrap()
    
    try:
        response = s3_client.list_objects_v2(
            Bucket=mrap_arn,
            Prefix=prefix,
            MaxKeys=100
        )
        
        objects = response.get('Contents', [])
        logger.info(f"Found {len(objects)} objects via MRAP with prefix '{prefix}':")
        
        for obj in objects[:10]:  # Show first 10
            logger.info(f"  - {obj['Key']} ({obj['Size']} bytes)")
        
        return objects
    except ClientError as e:
        logger.error(f"Error listing objects via MRAP: {e}")
        raise


# ==============================================================================
# Generate Presigned URLs with MRAP
# ==============================================================================
def generate_presigned_url_with_mrap(mrap_arn, object_key, expiration=3600):
    """
    Generate presigned URL using MRAP.
    
    Note: Presigned URLs with MRAP will route to the optimal region automatically.
    """
    s3_client = create_s3_client_with_mrap()
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': mrap_arn,
                'Key': object_key
            },
            ExpiresIn=expiration
        )
        logger.info(f"Generated MRAP presigned URL: {presigned_url}")
        return presigned_url
    except ClientError as e:
        logger.error(f"Error generating MRAP presigned URL: {e}")
        raise


# ==============================================================================
# MRAP Policy Management
# ==============================================================================
def put_mrap_policy(account_id, mrap_name, policy_document):
    """
    Attach a policy to a Multi-Region Access Point.
    
    Args:
        account_id: AWS Account ID
        mrap_name: MRAP name
        policy_document: Policy document as dict
    """
    s3control_client = boto3.client('s3control')
    
    try:
        response = s3control_client.put_multi_region_access_point_policy(
            AccountId=account_id,
            ClientToken=f"{mrap_name}-policy-{int(time.time())}",
            Details={
                'Name': mrap_name,
                'Policy': json.dumps(policy_document)
            }
        )
        logger.info(f"MRAP policy update initiated: {response['RequestTokenARN']}")
        return response['RequestTokenARN']
    except ClientError as e:
        logger.error(f"Error putting MRAP policy: {e}")
        raise


def get_mrap_policy(account_id, mrap_name):
    """Get the policy attached to a Multi-Region Access Point"""
    s3control_client = boto3.client('s3control')
    
    try:
        response = s3control_client.get_multi_region_access_point_policy(
            AccountId=account_id,
            Name=mrap_name
        )
        
        policy = response['Policy']
        logger.info(f"MRAP Policy for {mrap_name}:")
        logger.info(json.dumps(json.loads(policy['Policy']), indent=2))
        
        return json.loads(policy['Policy'])
    except ClientError as e:
        logger.error(f"Error getting MRAP policy: {e}")
        raise


# ==============================================================================
# MRAP with Replication
# ==============================================================================
def setup_mrap_replication(account_id, source_bucket, dest_bucket, role_arn):
    """
    Configure S3 Replication for use with MRAP.
    
    Note: MRAP works best with bidirectional replication between buckets.
    """
    s3_client = boto3.client('s3')
    
    replication_config = {
        'Role': role_arn,
        'Rules': [
            {
                'ID': 'mrap-replication-rule',
                'Status': 'Enabled',
                'Priority': 1,
                'Filter': {},
                'Destination': {
                    'Bucket': f'arn:aws:s3:::{dest_bucket}',
                    'ReplicationTime': {
                        'Status': 'Enabled',
                        'Time': {'Minutes': 15}
                    },
                    'Metrics': {
                        'Status': 'Enabled',
                        'EventThreshold': {'Minutes': 15}
                    }
                },
                'DeleteMarkerReplication': {'Status': 'Enabled'}
            }
        ]
    }
    
    try:
        s3_client.put_bucket_replication(
            Bucket=source_bucket,
            ReplicationConfiguration=replication_config
        )
        logger.info(f"Replication configured from {source_bucket} to {dest_bucket}")
    except ClientError as e:
        logger.error(f"Error configuring replication: {e}")
        raise


# ==============================================================================
# Delete Multi-Region Access Point
# ==============================================================================
def delete_multi_region_access_point(account_id, mrap_name):
    """
    Delete a Multi-Region Access Point.
    
    Note: Deletion can take several hours to complete.
    """
    s3control_client = boto3.client('s3control')
    
    try:
        response = s3control_client.delete_multi_region_access_point(
            AccountId=account_id,
            ClientToken=f"{mrap_name}-delete-{int(time.time())}",
            Details={'Name': mrap_name}
        )
        logger.info(f"MRAP deletion initiated: {response['RequestTokenARN']}")
        return response['RequestTokenARN']
    except ClientError as e:
        logger.error(f"Error deleting MRAP: {e}")
        raise


# ==============================================================================
# Example Usage
# ==============================================================================
if __name__ == "__main__":
    # Configuration
    ACCOUNT_ID = "123456789012"  # Your AWS Account ID
    MRAP_NAME = "my-global-access-point"
    MRAP_ALIAS = "mrap-alias-from-aws"  # Get this from get_mrap_status
    
    print("\n=== S3 Multi-Region Access Point Examples ===\n")
    
    # Example 1: Create MRAP
    print("Example 1: Create Multi-Region Access Point")
    # bucket_configs = [
    #     {'bucket': 'my-bucket-us-east-1', 'region': 'us-east-1'},
    #     {'bucket': 'my-bucket-eu-west-1', 'region': 'eu-west-1'},
    #     {'bucket': 'my-bucket-ap-southeast-1', 'region': 'ap-southeast-1'}
    # ]
    # create_multi_region_access_point(ACCOUNT_ID, MRAP_NAME, bucket_configs)
    
    # Example 2: Check MRAP status
    print("\nExample 2: Check MRAP Status")
    # status = get_mrap_status(ACCOUNT_ID, MRAP_NAME)
    # MRAP_ALIAS = status['alias']  # Save alias for operations
    
    # Example 3: List all MRAPs
    print("\nExample 3: List Multi-Region Access Points")
    # list_multi_region_access_points(ACCOUNT_ID)
    
    # Example 4: Upload via MRAP
    print("\nExample 4: Upload File via MRAP")
    # mrap_arn = get_mrap_arn(ACCOUNT_ID, MRAP_ALIAS)
    # upload_file_via_mrap(mrap_arn, "test-file.txt", "./local_file.txt")
    
    # Example 5: Download via MRAP
    print("\nExample 5: Download File via MRAP")
    # download_file_via_mrap(mrap_arn, "test-file.txt", "./downloaded_file.txt")
    
    # Example 6: List objects via MRAP
    print("\nExample 6: List Objects via MRAP")
    # list_objects_via_mrap(mrap_arn, prefix="documents/")
    
    # Example 7: Generate presigned URL
    print("\nExample 7: Generate Presigned URL with MRAP")
    # url = generate_presigned_url_with_mrap(mrap_arn, "test-file.txt")
    # print(f"Presigned URL: {url}")
    
    # Example 8: Set MRAP policy
    print("\nExample 8: Set MRAP Policy")
    # policy = {
    #     "Version": "2012-10-17",
    #     "Statement": [
    #         {
    #             "Effect": "Allow",
    #             "Principal": {"AWS": f"arn:aws:iam::{ACCOUNT_ID}:root"},
    #             "Action": ["s3:GetObject", "s3:PutObject"],
    #             "Resource": f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}/object/*"
    #         }
    #     ]
    # }
    # put_mrap_policy(ACCOUNT_ID, MRAP_NAME, policy)
    
    print("\n✓ All examples loaded. Uncomment specific examples to test.")


# ==============================================================================
# Terraform/Terragrunt Configuration for MRAP
# ==============================================================================
"""
To create MRAP with Terraform, you need buckets in multiple regions and replication configured:

# Buckets in multiple regions
resource "aws_s3_bucket" "us_east" {
  provider = aws.us_east_1
  bucket   = "my-mrap-bucket-us-east-1"
}

resource "aws_s3_bucket" "eu_west" {
  provider = aws.eu_west_1
  bucket   = "my-mrap-bucket-eu-west-1"
}

# Enable versioning (required for MRAP)
resource "aws_s3_bucket_versioning" "us_east" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "eu_west" {
  provider = aws.eu_west_1
  bucket   = aws_s3_bucket.eu_west.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Multi-Region Access Point
resource "aws_s3control_multi_region_access_point" "main" {
  details {
    name = "my-global-access-point"
    
    region {
      bucket = aws_s3_bucket.us_east.id
    }
    
    region {
      bucket = aws_s3_bucket.eu_west.id
    }
    
    public_access_block {
      block_public_acls       = true
      block_public_policy     = true
      ignore_public_acls      = true
      restrict_public_buckets = true
    }
  }
}

# IAM role for replication
resource "aws_iam_role" "replication" {
  name = "s3-mrap-replication-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# Replication policy
resource "aws_iam_role_policy" "replication" {
  role = aws_iam_role.replication.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.us_east.arn,
          aws_s3_bucket.eu_west.arn
        ]
      },
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.us_east.arn}/*",
          "${aws_s3_bucket.eu_west.arn}/*"
        ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.us_east.arn}/*",
          "${aws_s3_bucket.eu_west.arn}/*"
        ]
      }
    ]
  })
}

# Bidirectional replication
resource "aws_s3_bucket_replication_configuration" "us_to_eu" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.us_east.id
  role     = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-to-eu"
    status = "Enabled"
    
    destination {
      bucket        = aws_s3_bucket.eu_west.arn
      storage_class = "STANDARD"
      
      replication_time {
        status = "Enabled"
        time {
          minutes = 15
        }
      }
      
      metrics {
        status = "Enabled"
        event_threshold {
          minutes = 15
        }
      }
    }
  }
}

# Output the MRAP alias
output "mrap_alias" {
  value = aws_s3control_multi_region_access_point.main.alias
  description = "Use this alias to construct the MRAP ARN"
}

output "mrap_arn" {
  value = aws_s3control_multi_region_access_point.main.arn
}

# Important Notes:
# - MRAP creation can take up to 24 hours
# - All buckets must have versioning enabled
# - Bidirectional replication recommended for active-active
# - Use S3 Replication Time Control (S3 RTC) for predictable replication
# - MRAP has additional costs for request routing
"""

