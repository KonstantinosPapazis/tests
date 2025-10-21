# Boto3 Configuration for MRAP with Presigned URLs

## Your Use Case: Automatic Geographic Routing

**Current Setup:**
- 📦 Developers upload images to `eu-west-2` bucket
- 📦 Images replicate to `us-east-2` bucket
- 🔗 Developers create presigned URLs for downloads

**Problem:**
- All users download from same bucket (usually `eu-west-2`)
- US users experience higher latency
- Manually routing users is complex

**Solution with MRAP:**
- ✅ Generate **ONE presigned URL** using MRAP ARN
- ✅ European users automatically download from `eu-west-2`
- ✅ US users automatically download from `us-east-2`
- ✅ No application logic needed - AWS handles routing!

---

## Prerequisites

After running `terraform apply`, you'll have:
- ✅ Versioning enabled on both buckets
- ✅ Replication from `eu-west-2` → `us-east-2`
- ✅ Multi-Region Access Point created

**Get these from Terraform outputs:**
```bash
terraform output mrap_alias      # e.g., "abc123xyz.mrap"
terraform output account_id      # e.g., "123456789012"
terraform output boto3_mrap_arn  # The complete ARN to use
```

---

## Step 1: Update Your S3 Client Configuration

**CRITICAL**: You MUST enable `use_arn_region` for MRAP to work!

```python
import boto3
from botocore.config import Config

def create_s3_client_with_mrap():
    """
    Create S3 client that supports MRAP.
    
    ⚠️ IMPORTANT: Must enable use_arn_region!
    """
    return boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,      # REQUIRED for MRAP!
                'addressing_style': 'virtual'
            }
        )
    )
```

---

## Step 2: Change How You Generate Presigned URLs

This is the **main change** developers need to make!

### ❌ OLD WAY (Bucket-Specific URLs)

```python
# OLD: Direct bucket presigned URL
s3_client = boto3.client('s3')

# This always downloads from eu-west-2, even for US users!
presigned_url = s3_client.generate_presigned_url(
    'get_object',
    Params={
        'Bucket': 'my-bucket-eu-west-2',  # Hardcoded bucket
        'Key': 'images/photo.jpg'
    },
    ExpiresIn=3600
)
# Result: https://my-bucket-eu-west-2.s3.eu-west-2.amazonaws.com/images/photo.jpg?...
# ❌ Problem: US users get slow downloads from EU bucket
```

### ✅ NEW WAY (MRAP URLs - Automatic Routing)

```python
# NEW: MRAP presigned URL with automatic routing
from botocore.config import Config
import boto3

# Step 1: Create MRAP-enabled client
s3_client = boto3.client(
    's3',
    config=Config(
        signature_version='s3v4',
        s3={'use_arn_region': True}  # REQUIRED!
    )
)

# Step 2: Get MRAP ARN from Terraform output
ACCOUNT_ID = "123456789012"      # terraform output account_id
MRAP_ALIAS = "abc123xyz.mrap"    # terraform output mrap_alias
mrap_arn = f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}"

# Step 3: Generate presigned URL using MRAP ARN
presigned_url = s3_client.generate_presigned_url(
    'get_object',
    Params={
        'Bucket': mrap_arn,  # Use MRAP ARN instead of bucket name!
        'Key': 'images/photo.jpg'
    },
    ExpiresIn=3600
)
# Result: https://abc123xyz.mrap.accesspoint.s3-global.amazonaws.com/images/photo.jpg?...
# ✅ Benefit: AWS automatically routes users to nearest bucket!
```

---

## Step 3: Complete Developer Code Example

Here's the complete code your developers need to use:

```python
#!/usr/bin/env python3
"""
Example: Generate presigned URLs with MRAP for automatic geographic routing

Usage:
    1. Developer uploads image to eu-west-2 (as before)
    2. Developer generates presigned URL using MRAP ARN
    3. EU users → download from eu-west-2 (low latency)
    4. US users → download from us-east-2 (low latency)
"""
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============================================================================
# Configuration (from Terraform outputs)
# ============================================================================

ACCOUNT_ID = "123456789012"      # terraform output account_id
MRAP_ALIAS = "abc123xyz.mrap"    # terraform output mrap_alias

# Or get the complete ARN directly
# MRAP_ARN = "arn:aws:s3::123456789012:accesspoint/abc123xyz.mrap"

# ============================================================================
# S3 Client Configuration
# ============================================================================

def create_s3_client():
    """
    Create S3 client configured for MRAP operations.
    
    This client can:
    - Upload to regular buckets (eu-west-2)
    - Generate presigned URLs using MRAP ARN
    """
    return boto3.client(
        's3',
        region_name='eu-west-2',  # Default region for uploads
        config=Config(
            signature_version='s3v4',
            s3={
                'use_arn_region': True,      # Required for MRAP!
                'addressing_style': 'virtual'
            }
        )
    )

def get_mrap_arn():
    """Get MRAP ARN from configuration"""
    return f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}"

# ============================================================================
# Developer Functions
# ============================================================================

def upload_image(bucket_name, image_path, object_key):
    """
    Upload image to EU bucket (as before).
    
    Developers continue uploading to eu-west-2.
    Replication happens automatically to us-east-2.
    
    Args:
        bucket_name: 'my-bucket-eu-west-2'
        image_path: Local file path to upload
        object_key: S3 key (e.g., 'images/photo.jpg')
    """
    s3_client = create_s3_client()
    
    try:
        s3_client.upload_file(
            Filename=image_path,
            Bucket=bucket_name,  # Still upload to specific bucket
            Key=object_key,
            ExtraArgs={
                'ContentType': 'image/jpeg',  # Set appropriate content type
                'CacheControl': 'max-age=31536000'  # Optional: caching
            }
        )
        logger.info(f"✓ Uploaded {image_path} to {bucket_name}/{object_key}")
        logger.info(f"  Replication to us-east-2 will complete within 15 minutes")
        return True
    except ClientError as e:
        logger.error(f"Error uploading: {e}")
        return False

def generate_presigned_url_with_mrap(object_key, expiration=3600):
    """
    Generate presigned URL using MRAP for automatic geographic routing.
    
    This is the KEY CHANGE for developers!
    
    Args:
        object_key: S3 key (e.g., 'images/photo.jpg')
        expiration: URL expiration in seconds (default: 1 hour)
    
    Returns:
        str: Presigned URL that automatically routes to nearest region
    
    Example:
        >>> url = generate_presigned_url_with_mrap('images/photo.jpg')
        >>> # EU user clicks URL → downloads from eu-west-2
        >>> # US user clicks URL → downloads from us-east-2
    """
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': mrap_arn,  # Use MRAP ARN, not bucket name!
                'Key': object_key
            },
            ExpiresIn=expiration
        )
        
        logger.info(f"✓ Generated presigned URL for {object_key}")
        logger.info(f"  URL: {presigned_url}")
        logger.info(f"  This URL will automatically route users to nearest region:")
        logger.info(f"    - EU users → eu-west-2")
        logger.info(f"    - US users → us-east-2")
        
        return presigned_url
    
    except ClientError as e:
        logger.error(f"Error generating presigned URL: {e}")
        raise

def generate_presigned_url_for_upload(object_key, expiration=3600):
    """
    Generate presigned URL for uploads using MRAP.
    
    Optional: If you want users to upload directly.
    
    Args:
        object_key: S3 key where user will upload
        expiration: URL expiration in seconds
    
    Returns:
        str: Presigned upload URL
    """
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    try:
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': mrap_arn,
                'Key': object_key,
                'ContentType': 'image/jpeg'
            },
            ExpiresIn=expiration
        )
        
        logger.info(f"✓ Generated upload presigned URL for {object_key}")
        return presigned_url
    
    except ClientError as e:
        logger.error(f"Error generating upload URL: {e}")
        raise

# ============================================================================
# Example Usage: Typical Developer Workflow
# ============================================================================

def developer_workflow_example():
    """
    Complete example of developer workflow with MRAP.
    """
    
    # Configuration
    EU_BUCKET = "my-bucket-eu-west-2"
    IMAGE_PATH = "./photo.jpg"
    OBJECT_KEY = "images/user123/profile.jpg"
    
    # Step 1: Developer uploads image to EU bucket (as before)
    logger.info("Step 1: Uploading image to eu-west-2...")
    upload_success = upload_image(EU_BUCKET, IMAGE_PATH, OBJECT_KEY)
    
    if not upload_success:
        logger.error("Upload failed!")
        return
    
    # Step 2: Generate presigned URL using MRAP (NEW!)
    logger.info("\nStep 2: Generating presigned URL with MRAP...")
    presigned_url = generate_presigned_url_with_mrap(OBJECT_KEY, expiration=3600)
    
    # Step 3: Return URL to application/users
    logger.info("\nStep 3: Use this URL in your application:")
    logger.info(f"  URL: {presigned_url}")
    logger.info("\n✓ Done! Users will automatically download from nearest region:")
    logger.info("  - EU users: eu-west-2 (low latency)")
    logger.info("  - US users: us-east-2 (low latency)")
    
    return presigned_url

# ============================================================================
# Batch Processing Example
# ============================================================================

def generate_presigned_urls_batch(object_keys, expiration=3600):
    """
    Generate presigned URLs for multiple objects.
    
    Useful for: gallery views, listing pages, etc.
    
    Args:
        object_keys: List of S3 keys
        expiration: URL expiration in seconds
    
    Returns:
        dict: Mapping of object_key → presigned_url
    """
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    urls = {}
    
    for key in object_keys:
        try:
            url = s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': mrap_arn, 'Key': key},
                ExpiresIn=expiration
            )
            urls[key] = url
            logger.info(f"✓ Generated URL for {key}")
        except ClientError as e:
            logger.error(f"Failed to generate URL for {key}: {e}")
            urls[key] = None
    
    return urls

# ============================================================================
# Comparison: Old vs New
# ============================================================================

def compare_old_vs_new(object_key):
    """
    Show the difference between old and new approach.
    """
    s3_client_old = boto3.client('s3', region_name='eu-west-2')
    s3_client_new = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    print("=" * 80)
    print("COMPARISON: Old vs New Presigned URL Generation")
    print("=" * 80)
    
    # Old way
    print("\n❌ OLD WAY (bucket-specific):")
    old_url = s3_client_old.generate_presigned_url(
        'get_object',
        Params={'Bucket': 'my-bucket-eu-west-2', 'Key': object_key},
        ExpiresIn=3600
    )
    print(f"URL: {old_url}")
    print("Result: ALL users download from eu-west-2")
    print("  - EU users: Low latency ✓")
    print("  - US users: High latency ✗")
    
    # New way
    print("\n✅ NEW WAY (MRAP with automatic routing):")
    new_url = s3_client_new.generate_presigned_url(
        'get_object',
        Params={'Bucket': mrap_arn, 'Key': object_key},
        ExpiresIn=3600
    )
    print(f"URL: {new_url}")
    print("Result: Users download from NEAREST region (automatic!)")
    print("  - EU users: Download from eu-west-2 (low latency) ✓")
    print("  - US users: Download from us-east-2 (low latency) ✓")
    
    print("\n" + "=" * 80)

# ============================================================================
# Main
# ============================================================================

if __name__ == "__main__":
    print("\n🌍 MRAP Presigned URLs - Geographic Routing Example\n")
    
    # Example 1: Complete developer workflow
    print("Example 1: Complete Developer Workflow")
    print("-" * 80)
    # developer_workflow_example()
    
    # Example 2: Just generate presigned URL for existing object
    print("\n\nExample 2: Generate Presigned URL (existing object)")
    print("-" * 80)
    # url = generate_presigned_url_with_mrap('images/photo.jpg')
    # print(f"Presigned URL: {url}")
    
    # Example 3: Batch generate URLs
    print("\n\nExample 3: Batch Generate URLs")
    print("-" * 80)
    # image_keys = ['images/img1.jpg', 'images/img2.jpg', 'images/img3.jpg']
    # urls = generate_presigned_urls_batch(image_keys)
    # for key, url in urls.items():
    #     print(f"{key}: {url}")
    
    # Example 4: Compare old vs new
    print("\n\nExample 4: Compare Old vs New Approach")
    print("-" * 80)
    # compare_old_vs_new('images/photo.jpg')
    
    print("\n✓ Examples ready. Uncomment the examples you want to test.\n")
```

---

## Step 4: Test the Configuration

### Check MRAP Status

```python
import boto3

def check_mrap_status(account_id, mrap_name):
    """
    Check if MRAP is ready (can take up to 24 hours).
    
    Args:
        account_id: Your AWS account ID
        mrap_name: MRAP name from terraform (e.g., 'my-global-access-point')
    """
    s3control = boto3.client('s3control')
    
    response = s3control.get_multi_region_access_point(
        AccountId=account_id,
        Name=mrap_name
    )
    
    status = response['AccessPoint']['Status']
    alias = response['AccessPoint'].get('Alias', 'N/A')
    
    print(f"MRAP Name: {mrap_name}")
    print(f"Status: {status}")
    print(f"Alias: {alias}")
    
    if status == 'READY':
        print("✓ MRAP is READY! You can start using it.")
    else:
        print(f"⚠️ MRAP is {status}. Please wait (can take up to 24 hours).")
    
    return status, alias

# Usage
check_mrap_status("123456789012", "my-global-access-point")
```

### Test Upload and Download Flow

```python
def test_mrap_flow():
    """
    Test complete flow: upload → replicate → generate presigned URL
    """
    import time
    
    EU_BUCKET = "my-bucket-eu-west-2"
    TEST_KEY = "test/mrap-test.txt"
    TEST_CONTENT = b"Testing MRAP automatic routing!"
    
    s3_client = create_s3_client()
    mrap_arn = get_mrap_arn()
    
    # 1. Upload to EU bucket
    print("1. Uploading test file to eu-west-2...")
    s3_client.put_object(
        Bucket=EU_BUCKET,
        Key=TEST_KEY,
        Body=TEST_CONTENT
    )
    print("✓ Upload complete")
    
    # 2. Wait for replication (usually takes a few minutes)
    print("\n2. Waiting 30 seconds for replication to us-east-2...")
    time.sleep(30)
    
    # 3. Generate MRAP presigned URL
    print("\n3. Generating presigned URL with MRAP...")
    url = s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': mrap_arn, 'Key': TEST_KEY},
        ExpiresIn=300
    )
    print(f"✓ Presigned URL: {url}")
    
    # 4. Test download via MRAP
    print("\n4. Testing download via MRAP...")
    response = s3_client.get_object(Bucket=mrap_arn, Key=TEST_KEY)
    content = response['Body'].read()
    
    if content == TEST_CONTENT:
        print("✓ Download successful!")
        print(f"  Content: {content.decode('utf-8')}")
        print("\n✓ MRAP is working correctly!")
    else:
        print("✗ Content mismatch!")
    
    print("\n" + "=" * 80)
    print("You can now use MRAP presigned URLs in production!")
    print("Users will automatically download from nearest region.")
    print("=" * 80)

# Run test
# test_mrap_flow()
```

---

## Migration Strategy for Developers

### Phase 1: Preparation (Before Terraform Apply)

1. ✅ Review current code that generates presigned URLs
2. ✅ Identify all places where `generate_presigned_url` is called
3. ✅ Plan code changes

### Phase 2: Infrastructure (Terraform)

```bash
cd mrap/
terraform init
terraform plan
terraform apply
```

Wait up to 24 hours for MRAP to become READY.

### Phase 3: Code Migration

**Create helper module** (e.g., `s3_utils.py`):

```python
# s3_utils.py
import boto3
from botocore.config import Config
import os

# Configuration (from environment or config file)
ACCOUNT_ID = os.getenv('AWS_ACCOUNT_ID', '123456789012')
MRAP_ALIAS = os.getenv('MRAP_ALIAS', 'abc123xyz.mrap')
USE_MRAP = os.getenv('USE_MRAP', 'true').lower() == 'true'

def get_s3_client():
    """Get S3 client with MRAP support"""
    return boto3.client(
        's3',
        config=Config(
            signature_version='s3v4',
            s3={'use_arn_region': True}
        )
    )

def get_bucket_or_mrap_arn(bucket_name):
    """
    Return MRAP ARN if enabled, otherwise return bucket name.
    
    This allows gradual migration!
    """
    if USE_MRAP:
        return f"arn:aws:s3::{ACCOUNT_ID}:accesspoint/{MRAP_ALIAS}"
    else:
        return bucket_name

def generate_download_url(object_key, expiration=3600):
    """
    Generate presigned URL for download.
    
    Uses MRAP if enabled, otherwise falls back to direct bucket access.
    """
    s3_client = get_s3_client()
    bucket = get_bucket_or_mrap_arn('my-bucket-eu-west-2')
    
    return s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket, 'Key': object_key},
        ExpiresIn=expiration
    )
```

**Update application code:**

```python
# Before
from old_s3_utils import generate_url
url = generate_url('images/photo.jpg')

# After (same interface!)
from s3_utils import generate_download_url
url = generate_download_url('images/photo.jpg')
```

### Phase 4: Testing

1. Enable MRAP: `USE_MRAP=true`
2. Test from different locations (EU and US)
3. Verify automatic routing works
4. Monitor CloudWatch metrics

### Phase 5: Rollout

1. Deploy code changes (with MRAP disabled initially)
2. Enable MRAP via environment variable
3. Monitor for issues
4. Rollback if needed (change `USE_MRAP=false`)

---

## FAQ

### Q: Do uploads also route automatically?

**A:** Yes! If you upload using MRAP ARN, AWS routes to the nearest region. However, for your use case, you can continue uploading directly to `eu-west-2` and only use MRAP for presigned URLs.

```python
# Option 1: Upload to specific bucket (current approach - works fine)
s3_client.upload_file('photo.jpg', 'my-bucket-eu-west-2', 'images/photo.jpg')

# Option 2: Upload via MRAP (also works - routes automatically)
s3_client.upload_file('photo.jpg', mrap_arn, 'images/photo.jpg')
```

### Q: How long does replication take?

**A:** With S3 Replication Time Control (RTC) enabled in Terraform, replication completes within 15 minutes. Without RTC, it usually takes minutes but is not guaranteed.

### Q: What if the US bucket doesn't have the object yet?

**A:** MRAP is smart! If a user requests an object that hasn't replicated yet, MRAP will fetch it from the source bucket (eu-west-2) and serve it. Once replication completes, future requests use the local copy.

### Q: Can I still access buckets directly?

**A:** Yes! Direct bucket access still works. MRAP is additive - it doesn't break existing access patterns.

### Q: What about object metadata and permissions?

**A:** Replication copies everything: object data, metadata, tags, and ACLs (if configured). Presigned URLs work the same way whether using bucket name or MRAP ARN.

### Q: What's the cost impact?

**A:** 
- MRAP routing: ~$0.0005 per 1,000 requests
- Replication: Standard cross-region transfer costs (~$0.02/GB)
- S3 RTC: Additional ~$0.015/GB

For most use cases, the improved user experience justifies the cost.

---

## Troubleshooting

### Error: "The ARN is not supported for this operation"

**Cause:** Missing `use_arn_region: True` in client config

**Fix:**
```python
s3_client = boto3.client(
    's3',
    config=Config(s3={'use_arn_region': True})
)
```

### Error: "MultiRegionAccessPointNotReady"

**Cause:** MRAP is still being created (can take up to 24 hours)

**Fix:** Check status:
```bash
terraform output mrap_status
```

Wait until status is `READY`.

### Presigned URLs return 403 Forbidden

**Cause:** IAM permissions issue

**Fix:** Ensure your IAM user/role has:
```json
{
  "Effect": "Allow",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3::ACCOUNT_ID:accesspoint/MRAP_ALIAS/object/*"
}
```

### Objects not replicating

**Check:**
1. Is versioning enabled? `terraform output bucket_names` then check versioning
2. Is replication rule active? Check AWS Console → S3 → Bucket → Replication
3. Check CloudWatch metrics for replication lag

---

## Summary

**Key Changes for Developers:**

1. ✅ Use `create_s3_client()` with `use_arn_region: True`
2. ✅ Use MRAP ARN instead of bucket name in presigned URLs
3. ✅ Everything else stays the same!

**Result:**
- 🇪🇺 European users: Fast downloads from `eu-west-2`
- 🇺🇸 US users: Fast downloads from `us-east-2`
- 🌍 Automatic routing based on user location
- 🎯 One presigned URL works for everyone!

**Next Steps:**
1. Wait for `terraform apply` to complete (up to 24 hours)
2. Get MRAP alias from `terraform output`
3. Update code to use MRAP ARN
4. Test and deploy!
