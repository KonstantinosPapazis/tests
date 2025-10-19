#!/usr/bin/env python3
"""
Quick test to check if your presigned URLs include regional endpoints.

Run this script to see what your current boto3 configuration generates.
"""

import boto3
from botocore.config import Config
import sys

def test_presigned_url_endpoint(bucket_name, object_key, region='us-east-1'):
    """
    Test presigned URL generation with different configurations.
    """
    print("="*80)
    print("PRESIGNED URL ENDPOINT TEST")
    print("="*80)
    print(f"\nTesting with:")
    print(f"  Bucket: {bucket_name}")
    print(f"  Key: {object_key}")
    print(f"  Region: {region}")
    print("\n" + "-"*80)
    
    # Test 1: Default boto3 client (what developers typically do)
    print("\n1️⃣  DEFAULT BOTO3 CLIENT")
    print("   Code: boto3.client('s3', region_name='us-east-1')")
    try:
        s3_default = boto3.client('s3', region_name=region)
        url_default = s3_default.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket_name, 'Key': object_key},
            ExpiresIn=3600
        )
        print(f"\n   Generated URL:\n   {url_default}\n")
        
        if region in url_default:
            print(f"   ✅ GOOD: Regional endpoint detected (contains '{region}')")
            print(f"   Traffic will use VPC endpoint and Direct Connect Private VIF")
        elif 's3.amazonaws.com' in url_default:
            print(f"   ⚠️  WARNING: Global endpoint detected (no region in URL)")
            print(f"   Traffic may use Public VIF or public internet")
            print(f"   Recommendation: Use explicit regional endpoint configuration")
        else:
            print(f"   ❓ UNKNOWN: Unexpected URL format")
    except Exception as e:
        print(f"   ❌ ERROR: {e}")
    
    print("\n" + "-"*80)
    
    # Test 2: Explicit configuration (recommended)
    print("\n2️⃣  RECOMMENDED CONFIGURATION")
    print("   Code: boto3.client('s3', region_name='us-east-1', config=Config(...))")
    try:
        s3_configured = boto3.client(
            's3',
            region_name=region,
            config=Config(
                signature_version='s3v4',
                s3={
                    'addressing_style': 'virtual',
                    'use_dualstack_endpoint': False
                }
            )
        )
        url_configured = s3_configured.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket_name, 'Key': object_key},
            ExpiresIn=3600
        )
        print(f"\n   Generated URL:\n   {url_configured}\n")
        
        if region in url_configured:
            print(f"   ✅ EXCELLENT: Regional endpoint confirmed")
            print(f"   Format: bucket.s3.{region}.amazonaws.com")
        else:
            print(f"   ⚠️  WARNING: Regional endpoint not detected")
    except Exception as e:
        print(f"   ❌ ERROR: {e}")
    
    print("\n" + "-"*80)
    
    # Test 3: Check boto3 version
    print("\n3️⃣  ENVIRONMENT INFO")
    print(f"   Python version: {sys.version.split()[0]}")
    print(f"   Boto3 version: {boto3.__version__}")
    
    # Version-specific notes
    boto3_version = boto3.__version__
    major, minor = map(int, boto3_version.split('.')[:2])
    
    if major < 1 or (major == 1 and minor < 20):
        print(f"\n   ⚠️  You're using boto3 {boto3_version}")
        print(f"   Older versions often default to global endpoint")
        print(f"   Recommendation: Upgrade to latest boto3 (pip install --upgrade boto3)")
    else:
        print(f"\n   ✅ Boto3 version {boto3_version} is recent")
        print(f"   Should use regional endpoints by default")
    
    print("\n" + "="*80)
    print("SUMMARY")
    print("="*80)
    
    # Compare results
    urls_match = url_default == url_configured
    both_regional = (region in url_default) and (region in url_configured)
    
    if both_regional:
        print("\n✅ EXCELLENT: Both configurations use regional endpoints")
        print("   Your current code is likely working correctly!")
        print("   Traffic will use VPC endpoint and Direct Connect Private VIF")
    elif region in url_configured and region not in url_default:
        print("\n⚠️  ACTION REQUIRED: Default client uses global endpoint")
        print("   You SHOULD update your code to use explicit configuration")
        print("   This ensures traffic uses Direct Connect Private VIF")
        print("\n   Recommended fix:")
        print("   ┌─────────────────────────────────────────────────────────┐")
        print("   │ from s3_vpc_endpoint_example import \\                  │")
        print("   │     create_s3_client_with_gateway_endpoint             │")
        print("   │                                                         │")
        print("   │ s3_client = create_s3_client_with_gateway_endpoint(    │")
        print(f"   │     region='{region}',                                  │")
        print("   │     use_regional_endpoint=True                          │")
        print("   │ )                                                       │")
        print("   └─────────────────────────────────────────────────────────┘")
    else:
        print("\n❓ UNEXPECTED: Please review URL formats above")
    
    print("\n" + "="*80 + "\n")
    
    return {
        'default_url': url_default,
        'configured_url': url_configured,
        'default_has_region': region in url_default,
        'configured_has_region': region in url_configured,
        'boto3_version': boto3.__version__
    }


if __name__ == "__main__":
    print("\n" + "="*80)
    print("S3 PRESIGNED URL ENDPOINT CHECKER")
    print("="*80)
    print("\nThis script tests whether your presigned URLs include regional endpoints.")
    print("Regional endpoints are CRITICAL for Direct Connect Private VIF routing.\n")
    
    # Get inputs
    if len(sys.argv) >= 3:
        bucket_name = sys.argv[1]
        object_key = sys.argv[2]
        region = sys.argv[3] if len(sys.argv) >= 4 else 'us-east-1'
    else:
        print("Usage: python test_presigned_url_endpoint.py <bucket-name> <object-key> [region]")
        print("\nUsing example values for demonstration...")
        bucket_name = "my-test-bucket"
        object_key = "test-file.txt"
        region = "us-east-1"
        print(f"\nNOTE: Bucket doesn't need to exist - we're only testing URL generation.")
        print(f"      No actual AWS API calls will be made.\n")
    
    # Run the test
    try:
        results = test_presigned_url_endpoint(bucket_name, object_key, region)
        
        # Exit code
        if results['default_has_region'] and results['configured_has_region']:
            sys.exit(0)  # Success
        else:
            sys.exit(1)  # Action required
            
    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        print("\nMake sure boto3 is installed: pip install boto3")
        sys.exit(2)

