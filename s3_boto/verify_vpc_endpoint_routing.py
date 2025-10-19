#!/usr/bin/env python3
"""
Verify if S3 requests go through VPC Endpoint or Internet Gateway.

This script performs multiple checks to determine if your S3 traffic
is routed through a Gateway VPC Endpoint (private) or Internet Gateway (public).

Run this from an EC2 instance in your VPC for accurate results.
"""

import boto3
import socket
import subprocess
import sys
from urllib.parse import urlparse

def check_route_tables(instance_id, region='us-east-1'):
    """Check if instance's route table has VPC endpoint configured."""
    print("\n" + "="*80)
    print("1️⃣  ROUTE TABLE VERIFICATION")
    print("="*80)
    
    ec2 = boto3.client('ec2', region_name=region)
    
    try:
        # Get instance details
        instances = ec2.describe_instances(InstanceIds=[instance_id])
        subnet_id = instances['Reservations'][0]['Instances'][0]['SubnetId']
        vpc_id = instances['Reservations'][0]['Instances'][0]['VpcId']
        
        print(f"\nInstance: {instance_id}")
        print(f"Subnet: {subnet_id}")
        print(f"VPC: {vpc_id}")
        
        # Get route table for subnet
        route_tables = ec2.describe_route_tables(
            Filters=[
                {'Name': 'association.subnet-id', 'Values': [subnet_id]}
            ]
        )
        
        if not route_tables['RouteTables']:
            # Try VPC main route table
            route_tables = ec2.describe_route_tables(
                Filters=[
                    {'Name': 'vpc-id', 'Values': [vpc_id]},
                    {'Name': 'association.main', 'Values': ['true']}
                ]
            )
        
        if route_tables['RouteTables']:
            rt = route_tables['RouteTables'][0]
            print(f"\nRoute Table: {rt['RouteTableId']}")
            
            # Check for VPC endpoint routes
            vpce_routes = [
                r for r in rt['Routes']
                if r.get('GatewayId', '').startswith('vpce-')
            ]
            
            if vpce_routes:
                print("\n✅ VPC ENDPOINT ROUTES FOUND:")
                for route in vpce_routes:
                    dest = route.get('DestinationPrefixListId', 'unknown')
                    gateway = route.get('GatewayId', 'unknown')
                    print(f"   {dest} → {gateway}")
                return True
            else:
                print("\n❌ NO VPC ENDPOINT ROUTES FOUND")
                print("   S3 traffic will use Internet Gateway")
                return False
        else:
            print("\n❌ Could not find route table")
            return False
            
    except Exception as e:
        print(f"\n❌ Error checking route tables: {e}")
        return False


def check_vpc_endpoints(region='us-east-1'):
    """Check if VPC has S3 Gateway endpoints configured."""
    print("\n" + "="*80)
    print("2️⃣  VPC ENDPOINT CONFIGURATION")
    print("="*80)
    
    ec2 = boto3.client('ec2', region_name=region)
    
    try:
        vpc_endpoints = ec2.describe_vpc_endpoints(
            Filters=[
                {'Name': 'service-name', 'Values': [f'com.amazonaws.{region}.s3']}
            ]
        )
        
        if vpc_endpoints['VpcEndpoints']:
            print("\n✅ S3 VPC ENDPOINTS FOUND:")
            for vpce in vpc_endpoints['VpcEndpoints']:
                print(f"\n   Endpoint ID: {vpce['VpcEndpointId']}")
                print(f"   Type: {vpce.get('VpcEndpointType', 'Gateway')}")
                print(f"   State: {vpce['State']}")
                print(f"   VPC: {vpce['VpcId']}")
                if 'RouteTableIds' in vpce and vpce['RouteTableIds']:
                    print(f"   Route Tables: {', '.join(vpce['RouteTableIds'])}")
            return True
        else:
            print("\n❌ NO S3 VPC ENDPOINTS FOUND")
            print("   Create a Gateway VPC Endpoint for S3")
            return False
            
    except Exception as e:
        print(f"\n❌ Error checking VPC endpoints: {e}")
        return False


def check_s3_prefix_list(region='us-east-1'):
    """Get S3 prefix list for IP verification."""
    print("\n" + "="*80)
    print("3️⃣  S3 PREFIX LIST")
    print("="*80)
    
    ec2 = boto3.client('ec2', region_name=region)
    
    try:
        prefix_lists = ec2.describe_prefix_lists(
            Filters=[
                {'Name': 'prefix-list-name', 'Values': [f'com.amazonaws.{region}.s3']}
            ]
        )
        
        if prefix_lists['PrefixLists']:
            pl = prefix_lists['PrefixLists'][0]
            print(f"\nPrefix List ID: {pl['PrefixListId']}")
            print(f"Prefix List Name: {pl['PrefixListName']}")
            print(f"\nIP Ranges (CIDRs):")
            for cidr in pl['Cidrs']:
                print(f"   {cidr}")
            return pl['Cidrs']
        else:
            print("\n❌ Could not fetch S3 prefix list")
            return []
            
    except Exception as e:
        print(f"\n❌ Error fetching prefix list: {e}")
        return []


def test_dns_resolution(bucket_name, region='us-east-1'):
    """Test DNS resolution for S3 endpoints."""
    print("\n" + "="*80)
    print("4️⃣  DNS RESOLUTION TEST")
    print("="*80)
    
    endpoints = {
        'Global Endpoint': f'{bucket_name}.s3.amazonaws.com',
        'Regional Endpoint': f'{bucket_name}.s3.{region}.amazonaws.com'
    }
    
    for name, hostname in endpoints.items():
        print(f"\n{name}: {hostname}")
        try:
            ip_addresses = socket.gethostbyname_ex(hostname)[2]
            for ip in ip_addresses:
                print(f"   → {ip}")
        except Exception as e:
            print(f"   ❌ Resolution failed: {e}")


def test_traceroute(bucket_name, region='us-east-1'):
    """Test network path using traceroute."""
    print("\n" + "="*80)
    print("5️⃣  TRACEROUTE TEST")
    print("="*80)
    print("\n(Testing network path - this indicates routing behavior)")
    
    endpoints = {
        'Global': f'{bucket_name}.s3.amazonaws.com',
        'Regional': f'{bucket_name}.s3.{region}.amazonaws.com'
    }
    
    for name, hostname in endpoints.items():
        print(f"\n{name} Endpoint: {hostname}")
        try:
            result = subprocess.run(
                ['traceroute', '-m', '5', '-w', '1', hostname],
                capture_output=True,
                text=True,
                timeout=15
            )
            
            lines = [l.strip() for l in result.stdout.split('\n') if l.strip()][:6]
            
            if lines:
                for line in lines:
                    print(f"   {line}")
                
                # Count hops
                hop_count = len([l for l in lines if l and l[0].isdigit()])
                
                print(f"\n   Hop count: {hop_count}")
                if hop_count <= 3:
                    print("   ✅ Few hops - likely using VPC endpoint")
                elif hop_count > 3:
                    print("   ⚠️  Many hops - might be using internet gateway")
            else:
                print("   ⚠️  No traceroute output")
                
        except subprocess.TimeoutExpired:
            print("   ⚠️  Traceroute timed out")
        except FileNotFoundError:
            print("   ⚠️  traceroute not installed (run: sudo yum install traceroute)")
        except Exception as e:
            print(f"   ⚠️  Traceroute failed: {e}")


def test_connectivity(bucket_name, region='us-east-1'):
    """Test actual connectivity to S3."""
    print("\n" + "="*80)
    print("6️⃣  CONNECTIVITY TEST")
    print("="*80)
    
    s3_client = boto3.client('s3', region_name=region)
    
    print(f"\nTesting connection to bucket: {bucket_name}")
    try:
        response = s3_client.head_bucket(Bucket=bucket_name)
        print("   ✅ Successfully connected to S3")
        print(f"   Request ID: {response['ResponseMetadata']['RequestId']}")
        return True
    except Exception as e:
        print(f"   ⚠️  Connection test: {e}")
        return False


def print_summary(has_route, has_vpce):
    """Print summary and recommendations."""
    print("\n" + "="*80)
    print("📊 SUMMARY")
    print("="*80)
    
    if has_route and has_vpce:
        print("\n✅ ✅ ✅  EXCELLENT - VPC ENDPOINT IS CONFIGURED AND ACTIVE")
        print("\nYour S3 traffic is using the VPC Gateway Endpoint:")
        print("   • Both global and regional endpoints will use VPC endpoint")
        print("   • Traffic stays on AWS private backbone")
        print("   • Does NOT go through public internet")
        print("   • Works with Direct Connect Private VIF")
        print("\nFor the URL: https://my-bucket.s3.amazonaws.com/file.jpg")
        print("   ✅ Will route through VPC endpoint (private)")
        print("   ✅ Will NOT go through internet gateway (public)")
        
    elif has_vpce and not has_route:
        print("\n⚠️  VPC ENDPOINT EXISTS BUT NOT IN YOUR ROUTE TABLE")
        print("\nAction required:")
        print("   1. Add VPC endpoint to your subnet's route table")
        print("   2. Or check if you're using the wrong subnet/VPC")
        
    elif not has_vpce:
        print("\n❌  NO VPC ENDPOINT FOUND")
        print("\nYour S3 traffic is going through Internet Gateway:")
        print("   • Uses public internet")
        print("   • Not using AWS private backbone")
        print("   • May incur NAT gateway charges")
        print("\nTo fix:")
        print("   1. Create a Gateway VPC Endpoint for S3")
        print("   2. Add it to your route tables")
    
    print("\n" + "="*80)
    print("VERIFICATION METHODS")
    print("="*80)
    print("\n100% Definitive proof requires VPC Flow Logs:")
    print("   1. Enable VPC Flow Logs if not already enabled")
    print("   2. Make a request to S3")
    print("   3. Check Flow Logs for destination IPs")
    print("   4. Verify IPs are in S3 prefix list")
    print("\nFor instructions, see: verify_vpc_endpoint_traffic.md")
    print("="*80 + "\n")


def main():
    """Main verification script."""
    print("\n" + "="*80)
    print("S3 VPC ENDPOINT TRAFFIC VERIFICATION")
    print("="*80)
    print("\nThis script checks if S3 traffic uses VPC Endpoint or Internet Gateway")
    
    if len(sys.argv) < 2:
        print("\n❌ Missing required arguments")
        print("\nUsage:")
        print("   python verify_vpc_endpoint_routing.py <bucket-name> [instance-id] [region]")
        print("\nExample:")
        print("   python verify_vpc_endpoint_routing.py my-bucket i-1234567890abcdef0 us-east-1")
        print("\nNote: instance-id is optional but recommended for route table checks")
        sys.exit(1)
    
    bucket_name = sys.argv[1]
    instance_id = sys.argv[2] if len(sys.argv) > 2 else None
    region = sys.argv[3] if len(sys.argv) > 3 else 'us-east-1'
    
    print(f"\nTesting configuration:")
    print(f"   Bucket: {bucket_name}")
    print(f"   Instance: {instance_id or '(not provided)'}")
    print(f"   Region: {region}")
    
    # Run checks
    has_route = False
    if instance_id:
        has_route = check_route_tables(instance_id, region)
    else:
        print("\n⚠️  Skipping route table check (no instance ID provided)")
    
    has_vpce = check_vpc_endpoints(region)
    check_s3_prefix_list(region)
    test_dns_resolution(bucket_name, region)
    test_traceroute(bucket_name, region)
    test_connectivity(bucket_name, region)
    
    # Print summary
    print_summary(has_route, has_vpce)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)

