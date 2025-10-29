terraform {
  source = "../rds_module"
}



inputs = {
  rds_aurora_version              = "v2_serverless"
  database_name                   = "invbg"
  rds_family_name                 = "aurora-postgresql13"
  rds_engine_version              = "13.20"
  scaling_config_min_capacity     = 1  # Minimum 1 ACU required for logical replication
  scaling_config_max_capacity     = 2
  scaling_config_auto_pause       = false  # Disable auto-pause when using logical replication
  scaling_config_timeout_action   = "ForceApplyCapacityChange"
  backup_plan_tag                 = "default-rds-group1"
  engine_mode                     = "provisioned"
  engine                          = "aurora-postgresql"
  instance_class                  = "db.serverless"
  allow_major_version_upgrade     = true
  promotion_tier                  = 1
  apply_modifications_immediately = false  # For safety: in-place changes wait for maintenance window; blue/green deployments ignore this setting
  application_name                = "inv-bg"
  billing_entity                  = "my-cloud"
  billing_domain                  = "my-cloud"
  security_domain                 = "my-cloud"
  resource_owner                  = "my-cloud"
  kms_key_arn                           = "arn:aws:kms:eu-west-2:12345678912:key/123456-2345-55gt-aaaa-ase457hjk"
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  monitoring_interval                   = 60
  database_skip_final_snapshot          = true
  copy_tags_to_snapshot                 = true
  # enabled_cloudwatch_logs_exports omitted - logs collected directly by Datadog to avoid duplicate costs
  # If you need CloudWatch logs for AWS-native monitoring, uncomment:
  # enabled_cloudwatch_logs_exports     = ["postgresql"]
  # db_cluster_parameter_group_name removed to create custom parameter group with logical replication
  data_classification                   = "confidential"
  application_owner                     = "kospa@gmail.com"
  create_target_parameter_group = true 
  target_rds_family_name        = "aurora-postgresql14"
  cluster_parameter_group_parameters = [
    {
      "apply_method" = "pending-reboot"
      "name"         = "rds.logical_replication"
      "value"        = "1"
    }
  ]
}

include {
  path = find_in_parent_folders()
}
