"""
S3 Transfer Acceleration - Boto3 Example

This example shows how to configure boto3 to use S3 Transfer Acceleration,
which routes traffic through CloudFront edge locations for faster transfers
over long distances.

Prerequisites:
- S3 Transfer Acceleration enabled on your bucket
- Bucket name must be DNS-compliant (no periods, lowercase, etc.)
- Not available for all regions

Use Cases:
- Uploading/downloading large files from distant geographic locations
- Faster transfers when clients are far from the S3 bucket region
- Can improve transfer speeds by 50-500% depending on distance

Note: Transfer Acceleration uses public internet through CloudFront edge locations,
NOT Direct Connect private backbone.
"""

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
import logging
import time
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ==============================================================================
# Enable Transfer Acceleration on Bucket
# ==============================================================================
def enable_transfer_acceleration(bucket_name):
    """
    Enable S3 Transfer Acceleration on a bucket.
    This is a one-time configuration step.
    """
    s3_client = boto3.client('s3')
    
    try:
        s3_client.put_bucket_accelerate_configuration(
            Bucket=bucket_name,
            AccelerateConfiguration={
                'Status': 'Enabled'
            }
        )
        logger.info(f"Transfer Acceleration enabled on bucket: {bucket_name}")
        return True
    except ClientError as e:
        logger.error(f"Error enabling Transfer Acceleration: {e}")
        raise


def get_transfer_acceleration_status(bucket_name):
    """Check if Transfer Acceleration is enabled on a bucket"""
    s3_client = boto3.client('s3')
    
    try:
        response = s3_client.get_bucket_accelerate_configuration(
            Bucket=bucket_name
        )
        status = response.get('Status', 'Suspended')
        logger.info(f"Transfer Acceleration status for {bucket_name}: {status}")
        return status
    except ClientError as e:
        logger.error(f"Error checking Transfer Acceleration status: {e}")
        return None


# ==============================================================================
# Create S3 Client with Transfer Acceleration
# ==============================================================================
def create_s3_client_with_acceleration(region='us-east-1'):
    """
    Create boto3 S3 client configured to use Transfer Acceleration.
    
    The key is setting 'use_accelerate_endpoint': True in the config.
    This changes the endpoint from:
      https://bucket-name.s3.amazonaws.com
    to:
      https://bucket-name.s3-accelerate.amazonaws.com
    """
    s3_client = boto3.client(
        's3',
        region_name=region,
        config=Config(
            signature_version='s3v4',
            s3={
                'use_accelerate_endpoint': True,
                'addressing_style': 'virtual'  # Required for acceleration
            }
        )
    )
    return s3_client


# ==============================================================================
# Upload Operations with Transfer Acceleration
# ==============================================================================
def upload_file_with_acceleration(bucket_name, file_path, object_key, show_progress=True):
    """
    Upload file using S3 Transfer Acceleration.
    
    Args:
        bucket_name: Target S3 bucket (must have acceleration enabled)
        file_path: Local file path to upload
        object_key: S3 object key (destination path)
        show_progress: Show upload progress
    """
    s3_client = create_s3_client_with_acceleration()
    
    if show_progress:
        from boto3.s3.transfer import TransferConfig
        
        # Configure multipart upload settings
        config = TransferConfig(
            multipart_threshold=1024 * 25,  # 25 MB
            max_concurrency=10,
            multipart_chunksize=1024 * 25,
            use_threads=True
        )
        
        # Progress callback
        class ProgressPercentage:
            def __init__(self, filename):
                self._filename = filename
                self._size = float(Path(filename).stat().st_size)
                self._seen_so_far = 0
                self._lock = __import__('threading').Lock()
                
            def __call__(self, bytes_amount):
                with self._lock:
                    self._seen_so_far += bytes_amount
                    percentage = (self._seen_so_far / self._size) * 100
                    print(f"\r{self._filename}: {self._seen_so_far} / {self._size:.0f} ({percentage:.2f}%)", end='')
        
        try:
            s3_client.upload_file(
                file_path,
                bucket_name,
                object_key,
                Config=config,
                Callback=ProgressPercentage(file_path)
            )
            print()  # New line after progress
            logger.info(f"Successfully uploaded {file_path} to s3://{bucket_name}/{object_key} via Transfer Acceleration")
        except ClientError as e:
            logger.error(f"Error uploading file: {e}")
            raise
    else:
        try:
            s3_client.upload_file(file_path, bucket_name, object_key)
            logger.info(f"Successfully uploaded {file_path} to s3://{bucket_name}/{object_key}")
        except ClientError as e:
            logger.error(f"Error uploading file: {e}")
            raise


def upload_large_file_with_acceleration(bucket_name, file_path, object_key):
    """
    Upload large files with optimized multipart settings for Transfer Acceleration.
    """
    from boto3.s3.transfer import TransferConfig
    
    s3_client = create_s3_client_with_acceleration()
    
    # Optimized config for large files
    config = TransferConfig(
        multipart_threshold=1024 * 100,  # 100 MB
        max_concurrency=20,  # More concurrent uploads
        multipart_chunksize=1024 * 100,  # 100 MB chunks
        use_threads=True,
        max_bandwidth=None  # No bandwidth limit
    )
    
    try:
        start_time = time.time()
        s3_client.upload_file(
            file_path,
            bucket_name,
            object_key,
            Config=config
        )
        elapsed_time = time.time() - start_time
        file_size = Path(file_path).stat().st_size / (1024 * 1024)  # MB
        speed = file_size / elapsed_time if elapsed_time > 0 else 0
        
        logger.info(f"Uploaded {file_size:.2f} MB in {elapsed_time:.2f}s ({speed:.2f} MB/s)")
    except ClientError as e:
        logger.error(f"Error uploading large file: {e}")
        raise


# ==============================================================================
# Download Operations with Transfer Acceleration
# ==============================================================================
def download_file_with_acceleration(bucket_name, object_key, download_path):
    """Download file using S3 Transfer Acceleration"""
    s3_client = create_s3_client_with_acceleration()
    
    try:
        start_time = time.time()
        s3_client.download_file(bucket_name, object_key, download_path)
        elapsed_time = time.time() - start_time
        
        file_size = Path(download_path).stat().st_size / (1024 * 1024)  # MB
        speed = file_size / elapsed_time if elapsed_time > 0 else 0
        
        logger.info(f"Downloaded {file_size:.2f} MB in {elapsed_time:.2f}s ({speed:.2f} MB/s)")
    except ClientError as e:
        logger.error(f"Error downloading file: {e}")
        raise


# ==============================================================================
# Generate Presigned URLs with Transfer Acceleration
# ==============================================================================
def generate_presigned_url_with_acceleration(bucket_name, object_key, expiration=3600, operation='get_object'):
    """
    Generate presigned URLs using Transfer Acceleration endpoint.
    
    The URL will use the accelerated endpoint:
    https://bucket-name.s3-accelerate.amazonaws.com/...
    """
    s3_client = create_s3_client_with_acceleration()
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            operation,
            Params={
                'Bucket': bucket_name,
                'Key': object_key
            },
            ExpiresIn=expiration
        )
        logger.info(f"Generated accelerated presigned URL: {presigned_url}")
        return presigned_url
    except ClientError as e:
        logger.error(f"Error generating presigned URL: {e}")
        raise


def generate_presigned_post_with_acceleration(bucket_name, object_key, expiration=3600):
    """
    Generate presigned POST for direct browser uploads via Transfer Acceleration.
    """
    s3_client = create_s3_client_with_acceleration()
    
    try:
        response = s3_client.generate_presigned_post(
            Bucket=bucket_name,
            Key=object_key,
            ExpiresIn=expiration
        )
        logger.info(f"Generated presigned POST with acceleration")
        return response
    except ClientError as e:
        logger.error(f"Error generating presigned POST: {e}")
        raise


# ==============================================================================
# Compare Transfer Speeds: Standard vs Accelerated
# ==============================================================================
def compare_transfer_speeds(bucket_name, file_path, object_key):
    """
    Compare upload speeds between standard and accelerated endpoints.
    """
    from boto3.s3.transfer import TransferConfig
    
    config = TransferConfig(
        multipart_threshold=1024 * 25,
        max_concurrency=10,
        use_threads=True
    )
    
    # Standard endpoint
    standard_client = boto3.client('s3', region_name='us-east-1')
    start = time.time()
    try:
        standard_client.upload_file(file_path, bucket_name, f"standard_{object_key}", Config=config)
        standard_time = time.time() - start
        logger.info(f"Standard endpoint upload time: {standard_time:.2f}s")
    except ClientError as e:
        logger.error(f"Standard upload failed: {e}")
        standard_time = None
    
    # Accelerated endpoint
    accelerated_client = create_s3_client_with_acceleration()
    start = time.time()
    try:
        accelerated_client.upload_file(file_path, bucket_name, f"accelerated_{object_key}", Config=config)
        accelerated_time = time.time() - start
        logger.info(f"Accelerated endpoint upload time: {accelerated_time:.2f}s")
    except ClientError as e:
        logger.error(f"Accelerated upload failed: {e}")
        accelerated_time = None
    
    # Compare
    if standard_time and accelerated_time:
        improvement = ((standard_time - accelerated_time) / standard_time) * 100
        logger.info(f"Transfer Acceleration improvement: {improvement:.1f}%")
        return improvement
    
    return None


# ==============================================================================
# Test Transfer Acceleration Connectivity
# ==============================================================================
def test_acceleration_connectivity(bucket_name):
    """
    Test if Transfer Acceleration is working properly.
    AWS provides a speed comparison tool endpoint.
    """
    s3_client = create_s3_client_with_acceleration()
    
    try:
        # Simple head request to verify connectivity
        response = s3_client.head_bucket(Bucket=bucket_name)
        logger.info(f"Successfully connected to {bucket_name} via Transfer Acceleration")
        logger.info(f"Request ID: {response['ResponseMetadata']['RequestId']}")
        
        # Check if endpoint is actually accelerated
        http_headers = response['ResponseMetadata'].get('HTTPHeaders', {})
        server = http_headers.get('server', '')
        logger.info(f"Server: {server}")
        
        return True
    except ClientError as e:
        logger.error(f"Transfer Acceleration connectivity test failed: {e}")
        return False


# ==============================================================================
# Example Usage
# ==============================================================================
if __name__ == "__main__":
    # Configuration
    BUCKET_NAME = "your-bucket-name"  # Must be DNS-compliant
    OBJECT_KEY = "test-file.dat"
    LOCAL_FILE = "./local_file.txt"
    
    print("\n=== S3 Transfer Acceleration Examples ===\n")
    
    # Example 1: Enable Transfer Acceleration
    print("Example 1: Enable Transfer Acceleration")
    # enable_transfer_acceleration(BUCKET_NAME)
    # status = get_transfer_acceleration_status(BUCKET_NAME)
    # print(f"Status: {status}\n")
    
    # Example 2: Upload with acceleration
    print("Example 2: Upload with Transfer Acceleration")
    # upload_file_with_acceleration(BUCKET_NAME, LOCAL_FILE, OBJECT_KEY)
    
    # Example 3: Download with acceleration
    print("Example 3: Download with Transfer Acceleration")
    # download_file_with_acceleration(BUCKET_NAME, OBJECT_KEY, "./downloaded_file.txt")
    
    # Example 4: Generate presigned URL
    print("Example 4: Generate Presigned URL with Acceleration")
    # url = generate_presigned_url_with_acceleration(BUCKET_NAME, OBJECT_KEY)
    # print(f"Presigned URL: {url}\n")
    
    # Example 5: Compare speeds
    print("Example 5: Compare Transfer Speeds")
    # improvement = compare_transfer_speeds(BUCKET_NAME, LOCAL_FILE, OBJECT_KEY)
    
    # Example 6: Test connectivity
    print("Example 6: Test Transfer Acceleration Connectivity")
    # test_acceleration_connectivity(BUCKET_NAME)
    
    print("\n✓ All examples loaded. Uncomment specific examples to test.")


# ==============================================================================
# Terraform/Terragrunt Configuration for Transfer Acceleration
# ==============================================================================
"""
Add to your S3 bucket Terraform configuration:

resource "aws_s3_bucket" "main" {
  bucket = "your-bucket-name"  # Must be DNS-compliant (no periods)
}

# Enable Transfer Acceleration
resource "aws_s3_bucket_accelerate_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  status = "Enabled"
}

# Important: Bucket naming requirements for Transfer Acceleration
# - Must not contain periods (.)
# - Must be between 3 and 63 characters
# - Must be lowercase
# - Must be DNS-compliant
# - Cannot be formatted as an IP address (e.g., 192.168.1.1)

# Cost consideration
# Transfer Acceleration has additional costs:
# - $0.04 per GB for uploads (US, Europe, Japan)
# - $0.08 per GB for uploads (other regions)
# - Downloads are same as standard S3 data transfer pricing
# - Only charged when acceleration provides speed improvement

# CloudWatch Metrics
resource "aws_cloudwatch_metric_alarm" "transfer_acceleration_bytes" {
  alarm_name          = "s3-transfer-acceleration-usage"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BytesTransferred"
  namespace           = "AWS/S3"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "1073741824"  # 1 GB
  alarm_description   = "Monitor Transfer Acceleration usage"
  
  dimensions = {
    BucketName = aws_s3_bucket.main.id
  }
}
"""

