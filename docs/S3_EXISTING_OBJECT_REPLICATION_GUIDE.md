# S3 Existing Object Replication - Complete Guide

## Table of Contents
- [Overview](#overview)
- [Understanding the Problem](#understanding-the-problem)
- [Method 1: S3 Batch Replication (Recommended)](#method-1-s3-batch-replication-recommended)
- [Method 2: AWS CLI S3 Sync/Copy](#method-2-aws-cli-s3-synccopy)
- [Method 3: AWS DataSync](#method-3-aws-datasync)
- [Method 4: S3 Inventory + Lambda](#method-4-s3-inventory--lambda)
- [Method 5: Custom Python Script with boto3](#method-5-custom-python-script-with-boto3)
- [Method 6: rclone](#method-6-rclone)
- [Method Comparison](#method-comparison)
- [Troubleshooting](#troubleshooting)

---

## Overview

When you enable S3 replication on a bucket, **only new objects (uploaded after replication is enabled) are automatically replicated**. Existing objects in the bucket are not replicated unless you take additional steps.

This guide covers all available methods to replicate existing objects, with detailed steps for each approach.

---

## Understanding the Problem

### Why Don't Existing Objects Replicate?

S3 replication is triggered by new PUT operations. When you enable replication:
- ✅ New objects uploaded after replication is enabled → **Replicated automatically**
- ❌ Objects that existed before replication was enabled → **NOT replicated automatically**

### What is `existing_object_replication`?

The `existing_object_replication` configuration in S3:
- ✅ **Enables the capability** for existing object replication
- ✅ **Allows creation** of S3 Batch Replication jobs
- ❌ **Does NOT trigger** automatic replication by itself

**Important:** Simply adding `existing_object_replication` to your Terraform configuration and running `terraform apply` will NOT replicate existing objects. You must take additional action.

---

## Method 1: S3 Batch Replication (Recommended)

**Best for:** Official AWS-supported method, integrates with existing replication configuration

### Step 1: Update Terraform Configuration

Add `existing_object_replication` to your replication rule:

```hcl
resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.enable_replication ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.this]

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "replicate-specific-folder"
    status = "Enabled"

    # Optional: Filter for specific folder/prefix
    filter {
      prefix = "your-folder-name/"  # Replace with your folder path
    }

    destination {
      bucket        = var.replication_destination_bucket_arn
      storage_class = var.replication_storage_class

      encryption_configuration {
        replica_kms_key_id = var.replication_destination_kms_arn
      }
    }

    # Enable existing object replication
    existing_object_replication {
      status = "Enabled"
    }
  }
}
```

### Step 2: Apply Terraform Changes

```bash
cd /path/to/your/terraform
terraform plan
terraform apply
```

### Step 3: Create Batch Replication Job (Required)

#### Option A: Via AWS Console

1. Navigate to **S3 Console** → Select your source bucket
2. Go to **Management** tab → **Replication rules**
3. Select your replication rule
4. Click **"Create batch operations job"** or **"Replicate existing objects"**
5. Follow the wizard:
   - Choose the replication rule
   - Select scope (entire bucket or specific prefix)
   - Review job details
   - Confirm and create job
6. Monitor the job status in **S3 Batch Operations**

#### Option B: Via AWS CLI

First, create a manifest of objects to replicate (or let AWS generate it):

```bash
# Option 1: Let AWS generate the manifest automatically
aws s3control create-job \
  --account-id 123456789012 \
  --operation S3ReplicateObject={} \
  --manifest-generator S3JobManifestGenerator={EnableManifestOutput=true,SourceBucket=arn:aws:s3:::source-bucket,ManifestOutputLocation={Bucket=arn:aws:s3:::manifest-bucket,Prefix=manifests/},Filter={EligibleForReplication=true,ObjectReplicationStatuses=[NONE,FAILED]}} \
  --report Enabled=true,Bucket=arn:aws:s3:::report-bucket,Format=Report_CSV_20180820,Prefix=reports/ \
  --priority 10 \
  --role-arn arn:aws:iam::123456789012:role/BatchReplicationRole \
  --region us-east-1 \
  --no-confirmation-required
```

For specific prefix:
```bash
aws s3control create-job \
  --account-id 123456789012 \
  --operation S3ReplicateObject={} \
  --manifest-generator S3JobManifestGenerator={EnableManifestOutput=true,SourceBucket=arn:aws:s3:::source-bucket,ManifestOutputLocation={Bucket=arn:aws:s3:::manifest-bucket,Prefix=manifests/},Filter={EligibleForReplication=true,ObjectReplicationStatuses=[NONE,FAILED],KeyNameConstraint={MatchAnyPrefix=[your-folder-name/]}}} \
  --report Enabled=true,Bucket=arn:aws:s3:::report-bucket,Format=Report_CSV_20180820,Prefix=reports/ \
  --priority 10 \
  --role-arn arn:aws:iam::123456789012:role/BatchReplicationRole \
  --region us-east-1 \
  --no-confirmation-required
```

### Step 4: Monitor the Job

```bash
# Check job status
aws s3control describe-job \
  --account-id 123456789012 \
  --job-id <job-id-from-create-response> \
  --region us-east-1
```

### Pros & Cons

**Pros:**
- ✅ Official AWS-supported method
- ✅ Integrates with your existing replication configuration
- ✅ Maintains all metadata, tags, ACLs, and encryption
- ✅ Automatic retry for failed objects
- ✅ Detailed reporting and monitoring
- ✅ Handles large datasets efficiently

**Cons:**
- ❌ Requires additional IAM permissions for Batch Operations
- ❌ More complex setup than simple CLI sync
- ❌ Incurs S3 Batch Operations costs

**Cost:** S3 Batch Operations charges per object processed + standard S3 request and data transfer costs

---

## Method 2: AWS CLI S3 Sync/Copy

**Best for:** Small to medium datasets (<100GB, <10,000 objects), one-time migrations, quick solutions

### Step 1: Basic Sync Command

```bash
aws s3 sync s3://source-bucket/folder-name/ s3://destination-bucket/folder-name/ \
  --source-region us-east-1 \
  --region eu-west-1
```

### Step 2: Enhanced Sync with Logging

```bash
# Create a timestamped log file
LOG_FILE="s3-sync-$(date +%Y%m%d-%H%M%S).log"

# Run sync with logging
aws s3 sync s3://source-bucket/folder-name/ s3://destination-bucket/folder-name/ \
  --source-region us-east-1 \
  --region eu-west-1 \
  2>&1 | tee "$LOG_FILE"
```

### Step 3: Verify Before Syncing (Dry Run)

```bash
# Preview what will be synced without actually copying
aws s3 sync s3://source-bucket/folder-name/ s3://destination-bucket/folder-name/ \
  --dryrun
```

### Important Options

#### Size-Only Comparison (Faster)
```bash
aws s3 sync s3://source/folder/ s3://dest/folder/ \
  --size-only
```

#### Include/Exclude Patterns
```bash
# Only sync specific file types
aws s3 sync s3://source/folder/ s3://dest/folder/ \
  --include "*.jpg" \
  --include "*.png" \
  --exclude "*"

# Exclude specific patterns
aws s3 sync s3://source/folder/ s3://dest/folder/ \
  --exclude "*.tmp" \
  --exclude "temp/*"
```

#### Storage Class Selection
```bash
aws s3 sync s3://source/folder/ s3://dest/folder/ \
  --storage-class STANDARD_IA  # or GLACIER, INTELLIGENT_TIERING, etc.
```

### Resumability and Safety

#### ✅ Safe to Rerun

The `aws s3 sync` command is **idempotent** and **safe to rerun**:

- **Skips already copied objects** - Compares size and last modified timestamp
- **Only copies what's missing or changed** - No duplicate uploads
- **Resumes from where it left off** - No wasted effort

#### Rerun Examples

```bash
# First run - copies 500 objects, then fails
aws s3 sync s3://source-bucket/data/ s3://dest-bucket/data/
# (FAILED after 500 objects)

# Rerun - automatically skips the 500 already copied
aws s3 sync s3://source-bucket/data/ s3://dest-bucket/data/
# Skipped: 500 objects (already in sync)
# Copied: remaining objects ✓
```

#### Check What Still Needs Syncing

```bash
# Count objects that need syncing
aws s3 sync s3://source/folder/ s3://dest/folder/ --dryrun | wc -l

# List objects that need syncing
aws s3 sync s3://source/folder/ s3://dest/folder/ --dryrun
```

### Advanced Script with Retry Logic

Create a file called `s3-sync-with-retry.sh`:

```bash
#!/bin/bash

# Configuration
SOURCE="s3://source-bucket/folder-name/"
DEST="s3://destination-bucket/folder-name/"
SOURCE_REGION="us-east-1"
DEST_REGION="eu-west-1"
MAX_RETRIES=3
LOG_FILE="s3-sync-$(date +%Y%m%d-%H%M%S).log"

# Function to perform sync
perform_sync() {
  aws s3 sync "$SOURCE" "$DEST" \
    --source-region "$SOURCE_REGION" \
    --region "$DEST_REGION" \
    2>&1 | tee -a "$LOG_FILE"
  return ${PIPESTATUS[0]}
}

# Main retry loop
RETRY_COUNT=0
echo "Starting sync at $(date)" | tee "$LOG_FILE"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Sync attempt $((RETRY_COUNT + 1)) of $MAX_RETRIES" | tee -a "$LOG_FILE"
  
  if perform_sync; then
    echo "✓ Sync completed successfully at $(date)" | tee -a "$LOG_FILE"
    exit 0
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      WAIT_TIME=$((10 * RETRY_COUNT))
      echo "⚠ Sync failed, retrying in $WAIT_TIME seconds..." | tee -a "$LOG_FILE"
      sleep "$WAIT_TIME"
    fi
  fi
done

echo "✗ Sync failed after $MAX_RETRIES attempts at $(date)" | tee -a "$LOG_FILE"
exit 1
```

Make it executable and run:
```bash
chmod +x s3-sync-with-retry.sh
./s3-sync-with-retry.sh
```

### Common Failure Scenarios

| Failure Type | Safe to Rerun? | Action |
|-------------|----------------|--------|
| Network timeout | ✅ Yes | Rerun immediately |
| Permission error | ✅ Yes (after fix) | Fix IAM, then rerun |
| Rate limiting | ✅ Yes | Wait a few minutes, rerun |
| Script interrupted (Ctrl+C) | ✅ Yes | Rerun immediately |
| Partial upload | ✅ Yes | S3 verifies complete uploads |

### Pros & Cons

**Pros:**
- ✅ Simple and quick to set up
- ✅ Free (only pay for S3 requests and data transfer)
- ✅ Safe to rerun - idempotent
- ✅ Good for one-time migrations
- ✅ No additional infrastructure needed
- ✅ Built-in retry logic for individual objects

**Cons:**
- ❌ Single-threaded by default (slow for large datasets)
- ❌ No progress percentage (only object count)
- ❌ Must run from somewhere (EC2, laptop, Cloud Shell)
- ❌ Limited parallelization

**Cost:** Free (CLI tool), only pay for S3 requests and data transfer

**Recommended for:** Datasets under 100GB or 10,000 objects

---

## Method 3: AWS DataSync

**Best for:** Large datasets, ongoing synchronization needs, automated data transfer

### Step 1: Create Source Location

```bash
# Create source S3 location
aws datasync create-location-s3 \
  --s3-bucket-arn arn:aws:s3:::source-bucket \
  --s3-config BucketAccessRoleArn=arn:aws:iam::123456789012:role/DataSyncS3Role \
  --subdirectory /folder-name/ \
  --region us-east-1
```

Save the returned `LocationArn`.

### Step 2: Create Destination Location

```bash
# Create destination S3 location
aws datasync create-location-s3 \
  --s3-bucket-arn arn:aws:s3:::destination-bucket \
  --s3-config BucketAccessRoleArn=arn:aws:iam::123456789012:role/DataSyncS3Role \
  --subdirectory /folder-name/ \
  --region eu-west-1
```

Save the returned `LocationArn`.

### Step 3: Create DataSync Task

```bash
# Create task
aws datasync create-task \
  --source-location-arn arn:aws:datasync:us-east-1:123456789012:location/loc-xxxxx \
  --destination-location-arn arn:aws:datasync:eu-west-1:123456789012:location/loc-yyyyy \
  --name "s3-to-s3-folder-replication" \
  --cloud-watch-log-group-arn arn:aws:logs:us-east-1:123456789012:log-group:/aws/datasync \
  --options VerifyMode=POINT_IN_TIME_CONSISTENT,OverwriteMode=ALWAYS,Atime=BEST_EFFORT,Mtime=PRESERVE \
  --region us-east-1
```

### Step 4: Start Task Execution

```bash
# Start the task
aws datasync start-task-execution \
  --task-arn arn:aws:datasync:us-east-1:123456789012:task/task-xxxxx \
  --region us-east-1
```

### Step 5: Monitor Task

```bash
# Check task execution status
aws datasync describe-task-execution \
  --task-execution-arn arn:aws:datasync:us-east-1:123456789012:task/task-xxxxx/execution/exec-xxxxx \
  --region us-east-1
```

### Via AWS Console

1. Navigate to **AWS DataSync Console**
2. Click **Create task**
3. Configure source location:
   - Location type: **Amazon S3**
   - S3 bucket: Select your source bucket
   - Folder: Specify prefix/folder path
   - IAM role: Select or create role
4. Configure destination location (same process)
5. Configure task settings:
   - Verification mode: **Point-in-time consistent**
   - Data transfer configuration
   - Filters (include/exclude patterns)
6. Review and create task
7. Start task execution

### IAM Role for DataSync

DataSync needs an IAM role with S3 permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "datasync.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

With policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket",
        "arn:aws:s3:::destination-bucket"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
        "s3:GetObjectTagging",
        "s3:PutObjectTagging"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket/*",
        "arn:aws:s3:::destination-bucket/*"
      ]
    }
  ]
}
```

### Pros & Cons

**Pros:**
- ✅ Managed service - no infrastructure to maintain
- ✅ Automatic retries and error handling
- ✅ Built-in data validation
- ✅ Can schedule ongoing syncs
- ✅ Better performance than CLI for large datasets
- ✅ Detailed CloudWatch metrics and logging
- ✅ Can filter by prefix, modification time, etc.
- ✅ Bandwidth throttling available

**Cons:**
- ❌ Costs money per GB transferred
- ❌ Overkill for small one-time transfers
- ❌ Additional complexity vs. simple CLI

**Cost:** ~$0.0125 per GB scanned + standard S3 costs

**Recommended for:** Datasets over 100GB, ongoing sync needs, production workloads

---

## Method 4: S3 Inventory + Lambda

**Best for:** Very large datasets, automated approach, existing S3 infrastructure

### Architecture

1. S3 Inventory generates a manifest of objects (filtered by prefix)
2. S3 Event triggers Lambda when inventory is delivered
3. Lambda reads inventory and copies objects
4. (Optional) Use SQS for better scalability and retry logic

### Step 1: Enable S3 Inventory

```bash
# Create inventory configuration
aws s3api put-bucket-inventory-configuration \
  --bucket source-bucket \
  --id folder-inventory \
  --inventory-configuration '{
    "Destination": {
      "S3BucketDestination": {
        "AccountId": "123456789012",
        "Bucket": "arn:aws:s3:::inventory-bucket",
        "Format": "CSV",
        "Prefix": "inventory-reports/"
      }
    },
    "IsEnabled": true,
    "Filter": {
      "Prefix": "folder-name/"
    },
    "Id": "folder-inventory",
    "IncludedObjectVersions": "Current",
    "Schedule": {
      "Frequency": "Daily"
    }
  }'
```

### Step 2: Create Lambda Function

Create `copy-objects-from-inventory.py`:

```python
import boto3
import csv
import gzip
import urllib.parse
import os
from io import TextIOWrapper

s3_client = boto3.client('s3')

SOURCE_BUCKET = os.environ['SOURCE_BUCKET']
DEST_BUCKET = os.environ['DEST_BUCKET']

def lambda_handler(event, context):
    """
    Triggered by S3 inventory completion.
    Reads inventory CSV and copies each object.
    """
    
    # Get inventory file details from S3 event
    for record in event['Records']:
        inventory_bucket = record['s3']['bucket']['name']
        inventory_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing inventory: s3://{inventory_bucket}/{inventory_key}")
        
        # Download and process inventory file
        process_inventory_file(inventory_bucket, inventory_key)
    
    return {
        'statusCode': 200,
        'body': 'Inventory processed successfully'
    }

def process_inventory_file(bucket, key):
    """Process CSV inventory file and copy objects."""
    
    # Download inventory file
    response = s3_client.get_object(Bucket=bucket, Key=key)
    
    # Handle gzip compression if present
    if key.endswith('.gz'):
        with gzip.open(response['Body'], 'rt') as gz_file:
            reader = csv.reader(gz_file)
            copy_objects_from_csv(reader)
    else:
        reader = csv.reader(TextIOWrapper(response['Body'], encoding='utf-8'))
        copy_objects_from_csv(reader)

def copy_objects_from_csv(reader):
    """Read CSV and copy each object."""
    
    # Skip header row if present
    header = next(reader, None)
    
    copied_count = 0
    failed_count = 0
    
    for row in reader:
        try:
            # CSV columns: Bucket, Key, VersionId, IsLatest, IsDeleteMarker, Size, LastModifiedDate, ETag, StorageClass
            object_key = row[1]  # Key is typically second column
            
            # Copy object
            copy_source = {
                'Bucket': SOURCE_BUCKET,
                'Key': object_key
            }
            
            s3_client.copy_object(
                CopySource=copy_source,
                Bucket=DEST_BUCKET,
                Key=object_key
            )
            
            copied_count += 1
            
            if copied_count % 100 == 0:
                print(f"Copied {copied_count} objects...")
            
        except Exception as e:
            print(f"Error copying {object_key}: {str(e)}")
            failed_count += 1
    
    print(f"✓ Copied {copied_count} objects")
    print(f"✗ Failed {failed_count} objects")

```

### Step 3: Deploy Lambda with Required Permissions

Create IAM role for Lambda:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket",
        "arn:aws:s3:::source-bucket/*",
        "arn:aws:s3:::inventory-bucket",
        "arn:aws:s3:::inventory-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::destination-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

Deploy Lambda:
```bash
# Package Lambda
zip lambda-function.zip copy-objects-from-inventory.py

# Create Lambda function
aws lambda create-function \
  --function-name ProcessS3Inventory \
  --runtime python3.11 \
  --role arn:aws:iam::123456789012:role/LambdaS3CopyRole \
  --handler copy-objects-from-inventory.lambda_handler \
  --zip-file fileb://lambda-function.zip \
  --timeout 900 \
  --memory-size 512 \
  --environment Variables={SOURCE_BUCKET=source-bucket,DEST_BUCKET=destination-bucket}
```

### Step 4: Configure S3 Event Notification

```bash
# Add S3 event notification to trigger Lambda
aws s3api put-bucket-notification-configuration \
  --bucket inventory-bucket \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [
      {
        "Id": "InventoryTrigger",
        "LambdaFunctionArn": "arn:aws:lambda:us-east-1:123456789012:function:ProcessS3Inventory",
        "Events": ["s3:ObjectCreated:*"],
        "Filter": {
          "Key": {
            "FilterRules": [
              {
                "Name": "prefix",
                "Value": "inventory-reports/"
              },
              {
                "Name": "suffix",
                "Value": "manifest.json"
              }
            ]
          }
        }
      }
    ]
  }'
```

### Step 5: Wait for Inventory and Processing

- S3 Inventory runs daily (first report within 48 hours)
- Lambda triggers automatically when inventory is ready
- Monitor Lambda logs in CloudWatch

### Enhanced Version with SQS (For Large Datasets)

For better scalability, use SQS between inventory and Lambda:

1. Lambda reads inventory and sends object keys to SQS
2. Separate Lambda consumes SQS messages and copies objects
3. Benefits: Better error handling, parallelization, retry logic

### Pros & Cons

**Pros:**
- ✅ Automated and scalable
- ✅ Handles very large datasets
- ✅ Works well with existing S3 infrastructure
- ✅ Can process millions of objects
- ✅ Automatic retry with DLQ

**Cons:**
- ❌ More complex setup
- ❌ S3 Inventory has 24-48 hour delay
- ❌ Need to manage Lambda execution time limits
- ❌ Requires Lambda and potentially SQS

**Cost:** S3 Inventory cost (~$0.0025 per 1M objects listed) + Lambda execution costs

**Recommended for:** Very large datasets (millions of objects), automated workflows

---

## Method 5: Custom Python Script with boto3

**Best for:** Custom logic, parallel processing, specific filtering requirements

### Basic Script

Create `s3-parallel-copy.py`:

```python
#!/usr/bin/env python3
"""
Parallel S3 object copying script.
Copies objects from source to destination bucket with parallel processing.
"""

import boto3
from concurrent.futures import ThreadPoolExecutor, as_completed
from botocore.config import Config
from botocore.exceptions import ClientError
import argparse
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configure boto3 for better performance
config = Config(
    max_pool_connections=50,
    retries={
        'max_attempts': 3,
        'mode': 'adaptive'
    }
)

s3_client = boto3.client('s3', config=config)

def list_objects(bucket, prefix=''):
    """List all objects in bucket with given prefix."""
    logger.info(f"Listing objects in s3://{bucket}/{prefix}")
    
    objects = []
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=bucket, Prefix=prefix)
    
    for page in pages:
        if 'Contents' in page:
            objects.extend(page['Contents'])
    
    logger.info(f"Found {len(objects)} objects")
    return objects

def copy_object(source_bucket, dest_bucket, key, storage_class='STANDARD'):
    """Copy a single object from source to destination."""
    try:
        copy_source = {
            'Bucket': source_bucket,
            'Key': key
        }
        
        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=dest_bucket,
            Key=key,
            StorageClass=storage_class
        )
        
        return {'key': key, 'status': 'success'}
    
    except ClientError as e:
        logger.error(f"Error copying {key}: {e}")
        return {'key': key, 'status': 'failed', 'error': str(e)}

def copy_objects_parallel(source_bucket, dest_bucket, prefix='', max_workers=10, storage_class='STANDARD'):
    """Copy objects in parallel."""
    
    # List all objects
    objects = list_objects(source_bucket, prefix)
    
    if not objects:
        logger.warning("No objects found to copy")
        return
    
    # Copy objects in parallel
    copied = 0
    failed = 0
    
    logger.info(f"Starting parallel copy with {max_workers} workers...")
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all copy tasks
        futures = {
            executor.submit(copy_object, source_bucket, dest_bucket, obj['Key'], storage_class): obj
            for obj in objects
        }
        
        # Process completed tasks
        for future in as_completed(futures):
            result = future.result()
            
            if result['status'] == 'success':
                copied += 1
                if copied % 100 == 0:
                    logger.info(f"Progress: {copied}/{len(objects)} objects copied")
            else:
                failed += 1
                logger.error(f"Failed to copy: {result['key']}")
    
    # Summary
    logger.info("="*60)
    logger.info(f"✓ Successfully copied: {copied} objects")
    logger.info(f"✗ Failed: {failed} objects")
    logger.info(f"Total: {len(objects)} objects")
    logger.info("="*60)

def main():
    parser = argparse.ArgumentParser(
        description='Copy S3 objects in parallel from source to destination bucket'
    )
    parser.add_argument('--source-bucket', required=True, help='Source S3 bucket name')
    parser.add_argument('--dest-bucket', required=True, help='Destination S3 bucket name')
    parser.add_argument('--prefix', default='', help='Object prefix/folder to copy')
    parser.add_argument('--workers', type=int, default=10, help='Number of parallel workers (default: 10)')
    parser.add_argument('--storage-class', default='STANDARD', 
                       choices=['STANDARD', 'STANDARD_IA', 'INTELLIGENT_TIERING', 'ONEZONE_IA', 'GLACIER', 'DEEP_ARCHIVE'],
                       help='Destination storage class')
    
    args = parser.parse_args()
    
    logger.info(f"Starting S3 copy operation")
    logger.info(f"Source: s3://{args.source_bucket}/{args.prefix}")
    logger.info(f"Destination: s3://{args.dest_bucket}/{args.prefix}")
    logger.info(f"Workers: {args.workers}")
    logger.info(f"Storage Class: {args.storage_class}")
    
    start_time = datetime.now()
    
    copy_objects_parallel(
        args.source_bucket,
        args.dest_bucket,
        args.prefix,
        args.workers,
        args.storage_class
    )
    
    end_time = datetime.now()
    duration = end_time - start_time
    
    logger.info(f"Total time: {duration}")

if __name__ == '__main__':
    main()
```

### Usage

```bash
# Install boto3 if needed
pip install boto3

# Make script executable
chmod +x s3-parallel-copy.py

# Run the script
./s3-parallel-copy.py \
  --source-bucket source-bucket \
  --dest-bucket destination-bucket \
  --prefix folder-name/ \
  --workers 20 \
  --storage-class STANDARD_IA
```

### Enhanced Version with Progress Bar

Install tqdm:
```bash
pip install boto3 tqdm
```

Modified script with progress bar:

```python
from tqdm import tqdm

# In copy_objects_parallel function:
with ThreadPoolExecutor(max_workers=max_workers) as executor:
    futures = {
        executor.submit(copy_object, source_bucket, dest_bucket, obj['Key'], storage_class): obj
        for obj in objects
    }
    
    # Progress bar
    with tqdm(total=len(objects), desc="Copying objects", unit="obj") as pbar:
        for future in as_completed(futures):
            result = future.result()
            
            if result['status'] == 'success':
                copied += 1
            else:
                failed += 1
            
            pbar.update(1)
```

### Running from EC2 (Recommended)

For large transfers, run from an EC2 instance in the same region as source bucket:

```bash
# Launch EC2 instance (Amazon Linux 2)
# Attach IAM role with S3 permissions

# SSH to instance
ssh ec2-user@<instance-ip>

# Install Python 3 and pip
sudo yum install python3 pip -y

# Install dependencies
pip3 install boto3 tqdm

# Upload script
# Run in background with nohup
nohup python3 s3-parallel-copy.py \
  --source-bucket source-bucket \
  --dest-bucket destination-bucket \
  --prefix folder-name/ \
  --workers 50 \
  > copy.log 2>&1 &

# Monitor progress
tail -f copy.log
```

### Pros & Cons

**Pros:**
- ✅ Full control over the process
- ✅ Can add custom logic (filtering, transformation, etc.)
- ✅ Parallel processing for speed
- ✅ Progress tracking with tqdm
- ✅ Can run from EC2 in same region to avoid data transfer costs
- ✅ Retry logic built-in

**Cons:**
- ❌ Need to write and maintain code
- ❌ Need somewhere to run it
- ❌ Have to handle error cases
- ❌ May hit API rate limits with too many workers

**Cost:** Free (script), pay for S3 requests and data transfer. Running from EC2 in same region eliminates data transfer costs.

**Recommended for:** Medium to large datasets with custom requirements, when you need full control

---

## Method 6: rclone

**Best for:** Fast transfers, resume capability, excellent progress tracking

### Step 1: Install rclone

```bash
# Linux/macOS
curl https://rclone.org/install.sh | sudo bash

# macOS with Homebrew
brew install rclone

# Windows
# Download from https://rclone.org/downloads/
```

### Step 2: Configure rclone

```bash
# Start interactive configuration
rclone config

# Follow prompts:
# n) New remote
# name> source-s3
# Storage> s3
# provider> AWS
# env_auth> 1  (or provide access keys)
# region> us-east-1
# endpoint> (leave blank)
# location_constraint> (leave blank)
# acl> (leave blank for default)
# storage_class> (leave blank)
# [Accept remaining defaults]

# Repeat for destination
# n) New remote
# name> dest-s3
# [Same process for destination region]
```

### Step 3: Test Configuration

```bash
# List buckets
rclone lsd source-s3:

# List objects in bucket
rclone ls source-s3:source-bucket/folder-name/
```

### Step 4: Perform Sync

```bash
# Basic sync
rclone sync source-s3:source-bucket/folder-name dest-s3:destination-bucket/folder-name \
  --progress

# With more options
rclone sync source-s3:source-bucket/folder-name dest-s3:destination-bucket/folder-name \
  --transfers=20 \
  --checkers=40 \
  --progress \
  --stats=10s \
  --log-file=rclone-sync.log \
  --log-level=INFO
```

### Advanced Options

```bash
# Dry run first
rclone sync source-s3:source-bucket/folder-name dest-s3:destination-bucket/folder-name \
  --dry-run \
  --progress

# With bandwidth limit
rclone sync source-s3:source-bucket/folder-name dest-s3:destination-bucket/folder-name \
  --bwlimit=100M \
  --progress

# With file filtering
rclone sync source-s3:source-bucket/folder-name dest-s3:destination-bucket/folder-name \
  --include "*.jpg" \
  --include "*.png" \
  --progress

# With specific storage class
rclone sync source-s3:source-bucket/folder-name dest-s3:destination-bucket/folder-name \
  --s3-storage-class STANDARD_IA \
  --progress
```

### Resume Capability

rclone automatically resumes interrupted transfers:

```bash
# Run sync
rclone sync source-s3:bucket/folder dest-s3:bucket/folder --progress
# (Gets interrupted)

# Rerun same command - automatically resumes
rclone sync source-s3:bucket/folder dest-s3:bucket/folder --progress
# Only copies what's missing or changed
```

### Background Operation

```bash
# Run in background with nohup
nohup rclone sync source-s3:source-bucket/folder dest-s3:dest-bucket/folder \
  --transfers=20 \
  --progress \
  --log-file=rclone.log \
  > rclone-output.log 2>&1 &

# Monitor progress
tail -f rclone.log
```

### Configuration File Alternative

Instead of interactive config, create `~/.config/rclone/rclone.conf`:

```ini
[source-s3]
type = s3
provider = AWS
env_auth = true
region = us-east-1

[dest-s3]
type = s3
provider = AWS
env_auth = true
region = eu-west-1
```

### Pros & Cons

**Pros:**
- ✅ Very fast (optimized for cloud transfers)
- ✅ Excellent progress tracking
- ✅ Can resume interrupted transfers
- ✅ Free and open source
- ✅ Cross-cloud support (works with many cloud providers)
- ✅ Bandwidth throttling
- ✅ Extensive filtering options

**Cons:**
- ❌ External dependency
- ❌ Need to manage AWS credentials configuration
- ❌ Learning curve for advanced options

**Cost:** Free (tool), pay for S3 requests and data transfer

**Recommended for:** All dataset sizes, especially when you need fast reliable transfers with good progress tracking

---

## Method Comparison

| Method | Best For | Dataset Size | Complexity | Cost | Resume | Speed |
|--------|----------|--------------|------------|------|--------|-------|
| **S3 Batch Replication** | Official solution, production | Any size | Medium | Per object + requests | ✅ Yes | Fast |
| **AWS CLI sync** | Quick one-time migration | < 100GB | Low | Requests only | ✅ Yes | Medium |
| **AWS DataSync** | Ongoing sync, large datasets | > 100GB | Medium | Per GB scanned | ✅ Yes | Fast |
| **S3 Inventory + Lambda** | Automated, millions of objects | Very large | High | Inventory + Lambda | ✅ Yes | Medium |
| **boto3 Script** | Custom requirements | Medium-Large | Medium | Requests only | ⚠️ Manual | Fast (parallel) |
| **rclone** | Fast reliable transfers | Any size | Low | Requests only | ✅ Yes | Very Fast |

### Decision Tree

```
Do you need official AWS-supported method?
├─ Yes → S3 Batch Replication
└─ No
   ├─ Dataset < 100GB?
   │  ├─ Yes → AWS CLI sync or rclone
   │  └─ No
   │     ├─ Need ongoing sync?
   │     │  ├─ Yes → AWS DataSync
   │     │  └─ No
   │     │     ├─ Need custom logic?
   │     │     │  ├─ Yes → boto3 script
   │     │     │  └─ No → rclone
   │     └─ Millions of objects?
   │        └─ Yes → S3 Inventory + Lambda or S3 Batch Replication
```

---

## Troubleshooting

### Issue: "Access Denied" Errors

**Symptoms:**
```
An error occurred (AccessDenied) when calling the CopyObject operation
```

**Solution:**
1. Check source bucket permissions (s3:GetObject)
2. Check destination bucket permissions (s3:PutObject)
3. Verify IAM role/user has necessary permissions
4. Check bucket policies and ACLs

Required IAM permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": [
        "arn:aws:s3:::source-bucket",
        "arn:aws:s3:::source-bucket/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::destination-bucket/*"
    }
  ]
}
```

### Issue: KMS Encryption Errors

**Symptoms:**
```
The object is encrypted with a customer provided key...
```

**Solution:**
Add KMS permissions to IAM role:
```json
{
  "Effect": "Allow",
  "Action": [
    "kms:Decrypt"
  ],
  "Resource": "arn:aws:kms:region:account:key/source-key-id"
},
{
  "Effect": "Allow",
  "Action": [
    "kms:Encrypt",
    "kms:GenerateDataKey"
  ],
  "Resource": "arn:aws:kms:region:account:key/dest-key-id"
}
```

### Issue: Rate Limiting / Throttling

**Symptoms:**
```
SlowDown: Please reduce your request rate
```

**Solution:**
1. Reduce number of parallel workers
2. Add exponential backoff
3. Use rclone or DataSync (built-in rate limiting)
4. Request S3 rate limit increase from AWS Support

### Issue: Large Number of Objects

**Problem:** Listing millions of objects takes too long

**Solution:**
1. Use S3 Inventory instead of ListObjects
2. Use pagination efficiently
3. Consider S3 Batch Replication (handles at scale)

### Issue: Monitoring Progress

**Solutions:**

For AWS CLI:
```bash
# Count objects before
aws s3 ls s3://destination-bucket/folder/ --recursive | wc -l

# Run sync

# Count objects after
aws s3 ls s3://destination-bucket/folder/ --recursive | wc -l
```

For boto3 script: Add tqdm progress bar (see example above)

For rclone: Use `--progress` and `--stats=10s` flags

### Issue: Different Storage Classes

**Problem:** Want to copy to different storage class

**Solutions:**

AWS CLI:
```bash
aws s3 sync s3://source/folder/ s3://dest/folder/ \
  --storage-class STANDARD_IA
```

boto3: Use `StorageClass` parameter in `copy_object()`

rclone:
```bash
rclone sync source:bucket dest:bucket \
  --s3-storage-class INTELLIGENT_TIERING
```

### Issue: Copying to Different Regions

**Problem:** Cross-region data transfer costs

**Solution:**
1. Run copy command from EC2 in source region
2. Only pay for data transfer OUT from source region
3. No charge for data transfer IN to destination region
4. Consider AWS Transfer Family or DataSync for optimized transfer

### Issue: Versioned Objects

**Problem:** Multiple versions of objects exist

**Solution for specific versions:**
```bash
# List all versions
aws s3api list-object-versions --bucket source-bucket --prefix folder-name/

# Copy specific version
aws s3api copy-object \
  --copy-source source-bucket/key?versionId=VERSION_ID \
  --bucket destination-bucket \
  --key key
```

### Issue: Object Metadata Not Preserved

**Problem:** Metadata, tags, or ACLs not copied

**Solution:**

Use `--metadata-directive COPY`:
```bash
aws s3 cp s3://source/object s3://dest/object \
  --metadata-directive COPY \
  --tagging-directive COPY \
  --acl-directive COPY
```

For batch operations: S3 Batch Replication preserves all metadata automatically

---

## Best Practices

### 1. Always Test with Dry Run First

```bash
# AWS CLI
aws s3 sync s3://source/folder/ s3://dest/folder/ --dryrun

# rclone
rclone sync source:bucket dest:bucket --dry-run
```

### 2. Use Logging

```bash
# AWS CLI
aws s3 sync ... 2>&1 | tee sync-$(date +%Y%m%d).log

# rclone
rclone sync ... --log-file=rclone-$(date +%Y%m%d).log --log-level INFO
```

### 3. Monitor Costs

- Enable Cost Explorer
- Set up billing alerts
- Monitor data transfer costs (especially cross-region)
- Track S3 request costs (GET, PUT, LIST)

### 4. Consider Running from EC2 in Same Region

Benefits:
- No data transfer charges within same region
- Better network performance
- Can run long operations without interruption
- Use Instance Profile for credentials (no hardcoded keys)

### 5. Verify After Completion

```bash
# Count objects
aws s3 ls s3://source-bucket/folder/ --recursive | wc -l
aws s3 ls s3://dest-bucket/folder/ --recursive | wc -l

# Compare sizes
aws s3 ls s3://source-bucket/folder/ --recursive --summarize
aws s3 ls s3://dest-bucket/folder/ --recursive --summarize
```

### 6. Use Appropriate Storage Classes

Consider destination storage class based on access patterns:
- `STANDARD` - Frequent access
- `STANDARD_IA` - Infrequent access (cheaper storage, retrieval fee)
- `INTELLIGENT_TIERING` - Unknown access patterns
- `GLACIER` / `DEEP_ARCHIVE` - Long-term archival

### 7. Implement Error Handling

For scripts:
- Retry logic with exponential backoff
- Dead letter queue for failed objects
- Error logging with object keys
- Alert on failure thresholds

### 8. Security Best Practices

- Use IAM roles instead of access keys when possible
- Implement least privilege access
- Enable encryption in transit (HTTPS)
- Maintain encryption at rest
- Enable CloudTrail logging for audit
- Use VPC endpoints for S3 when running from EC2

---

## Additional Resources

### AWS Documentation
- [S3 Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)
- [S3 Batch Operations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/batch-ops.html)
- [AWS DataSync](https://docs.aws.amazon.com/datasync/latest/userguide/what-is-datasync.html)
- [S3 Inventory](https://docs.aws.amazon.com/AmazonS3/latest/userguide/storage-inventory.html)

### Tools Documentation
- [AWS CLI S3 Commands](https://docs.aws.amazon.com/cli/latest/reference/s3/)
- [boto3 S3 Documentation](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html)
- [rclone Documentation](https://rclone.org/docs/)

### Cost Calculators
- [AWS Pricing Calculator](https://calculator.aws/)
- [S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [DataSync Pricing](https://aws.amazon.com/datasync/pricing/)

---

## Summary

**Key Takeaways:**

1. ⚠️ **Simply adding `existing_object_replication` to Terraform is NOT enough** - you must take additional action to replicate existing objects

2. ✅ **Multiple methods available** - choose based on your dataset size, complexity needs, and budget

3. ✅ **Most methods are resumable** - safe to rerun if interrupted

4. ✅ **For quick one-time migrations**: Use AWS CLI sync or rclone

5. ✅ **For production/official support**: Use S3 Batch Replication

6. ✅ **For large ongoing needs**: Use AWS DataSync

7. ✅ **Always test first**: Use dry-run mode before actual copying

8. ✅ **Monitor costs**: Especially for cross-region data transfer

---

**Document Version:** 1.0  
**Last Updated:** October 27, 2025  
**Maintained by:** DevOps Team

