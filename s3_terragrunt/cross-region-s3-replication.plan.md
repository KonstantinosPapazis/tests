<!-- 1430ed8d-a572-4ce8-8f0b-c14e6f552543 652ebd2b-52ca-4fd0-8c8c-50de9697f919 -->
# Cross-Region S3 Replication with Terragrunt

## Approach

Use Terragrunt's `dependency` blocks to reference outputs from one region's Terraform state in another region's configuration. This allows passing the bucket name and KMS ARN from us-west-2 to eu-west-2 (and vice versa for bi-directional replication).

## Implementation

### 1. Create Directory Structure

Set up the folder hierarchy matching your company's pattern:

- `cloud_repo/dev/eu-west-2/s3/terragrunt.hcl`
- `cloud_repo/dev/us-west-2/s3/terragrunt.hcl`

### 2. Create Example Terraform Module

Create a sample S3 module at `cloud_repo/modules/s3/` with:

- **Inputs**: bucket name, replication configuration (destination bucket, KMS ARN)
- **Outputs**: bucket name, KMS ARN for cross-region reference

### 3. Configure us-west-2 S3 (Primary)

Create `cloud_repo/dev/us-west-2/s3/terragrunt.hcl`:

- Reference the S3 module
- Add dependency on eu-west-2 for bi-directional replication
- Pass replication variables (destination bucket from eu-west-2)
- Define inputs for bucket configuration

### 4. Configure eu-west-2 S3 (Replica)

Create `cloud_repo/dev/eu-west-2/s3/terragrunt.hcl`:

- Add `dependency` block pointing to `../../us-west-2/s3`
- Use `dependency.us_west_2.outputs.bucket_name` and `dependency.us_west_2.outputs.kms_arn`
- Pass these as inputs to the replication configuration
- Configure mock outputs for dependency resolution during plan

### 5. Add Root Configuration (Optional)

Create `cloud_repo/terragrunt.hcl` with shared remote state configuration.

## Key Concepts

**Dependency Block**: References another Terragrunt configuration's outputs

```hcl
dependency "us_west_2" {
  config_path = "../../us-west-2/s3"
}
```

**Mock Outputs**: Allows `terragrunt plan` to work before dependencies are applied

```hcl
mock_outputs = {
  bucket_name = "mock-bucket"
  kms_arn = "arn:aws:kms:us-west-2:123456789:key/mock"
}
```

**Using Dependency Outputs**:

```hcl
inputs = {
  replication_destination_bucket = dependency.us_west_2.outputs.bucket_name
  replication_kms_arn = dependency.us_west_2.outputs.kms_arn
}
```

### To-dos

- [x] Create folder structure for cloud_repo with dev/region/s3 hierarchy
- [x] Create example Terraform S3 module with replication support and outputs
- [x] Create us-west-2 S3 terragrunt.hcl with outputs and optional dependency
- [x] Create eu-west-2 S3 terragrunt.hcl with dependency block referencing us-west-2
- [x] Create root terragrunt.hcl with shared configuration example
- [x] Create README explaining the pattern and usage instructions