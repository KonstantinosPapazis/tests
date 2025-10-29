data "aws_sns_topic" "rds" {
  name = "${var.aws_region_short_code}-${var.aws_account_alias}-sns-rds-svc-cloudwatch-event-topic"
}

locals {
  rds_major_version        = split(".", var.rds_engine_version)[0]
  target_rds_major_version = var.target_rds_family_name != null ? regex("\\d+$", var.target_rds_family_name) : null
  engine                   = replace(var.engine, "aurora-", "")
  tags = merge(
    var.tags,
    tomap({ "service-name" : "rds-service" }),
    tomap({ "application-name" : var.application_name })
  )
  performance_insights_kms_key_id = var.performance_insights_kms_key_id != null ? var.performance_insights_kms_key_id : var.kms_key_arn
  acu_default_alarm = { "acu-reached-max-alarm" = {
    "alarm_name" : "acu-reached-max-alarm",
    "comparison_operator" : "GreaterThanOrEqualToThreshold",
    "evaluation_periods" : 5,
    "datapoints_to_alarm" : 3,
    "metric_name" : "ServerlessDatabaseCapacity",
    "namespace" : "AWS/RDS"
    "period" : 300,
    "statistic" : "Average",
    "threshold" : 1,
    "treat_missing_data" : "ignore",
    "alarm_description" : "Serverless ACU reached max allowed capacity",
    "actions_enabled" : "true",
  } }
  default_cloudwatch_alarms = var.engine_mode == "serverless" || var.instance_class == "db.serverless" ? merge(
    var.default_cloudwatch_alarms,
    local.acu_default_alarm
  ) : var.default_cloudwatch_alarms
}


module "meta" {
  source            = "git::ssh://git@bitbucket.mycompany.com:7999/vc/vc-terraform-names.git?ref=v3.3.7" 
  resource_owner    = var.resource_owner
  aws_account_alias = var.aws_account_alias
  primary_name      = var.application_name
  secondary_name    = var.secondary_name
  billing_entity    = var.billing_entity
  billing_domain    = var.billing_domain
  security_domain   = var.security_domain
  tags              = local.tags
}



module "deepmerge" {
  source = "cloudposse/config/yaml//modules/deepmerge"
  maps = [
    local.default_cloudwatch_alarms,
    var.cloudwatch_alarms_config_override
  ]
}

moved {
  from = aws_rds_cluster_parameter_group.parameter_group
  to   = aws_rds_cluster_parameter_group.parameter_group[0]
}

resource "aws_rds_cluster_parameter_group" "parameter_group" {
  count       = var.db_cluster_parameter_group_name != null ? 0 : 1
  name        = "${module.meta.rds_name_prefix}-${local.rds_major_version}-cluster-param-group"
  family      = var.rds_family_name
  description = "${local.rds_major_version} Cluster parameter group for ${module.meta.rds_name_prefix}-cluster"
  dynamic "parameter" {
    for_each = var.cluster_parameter_group_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", null)
    }
  }
  tags = merge(module.meta.tags,
    tomap({ "name" : "${module.meta.rds_name_prefix}-${local.rds_major_version}-cluster-param-group" })
  )
  lifecycle {
    ignore_changes = [
      name,
      description,
    ]
    create_before_destroy = true
  }
}

# Target parameter group for blue/green deployments (major version upgrades)
resource "aws_rds_cluster_parameter_group" "target_parameter_group" {
  count       = var.create_target_parameter_group && var.target_rds_family_name != null ? 1 : 0
  name        = "${module.meta.rds_name_prefix}-${local.target_rds_major_version}-cluster-param-group"
  family      = var.target_rds_family_name
  description = "Target cluster parameter group for ${module.meta.rds_name_prefix}-cluster blue/green deployment to version ${local.target_rds_major_version}"

  dynamic "parameter" {
    for_each = length(var.target_cluster_parameter_group_parameters) > 0 ? var.target_cluster_parameter_group_parameters : var.cluster_parameter_group_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", null)
    }
  }

  tags = merge(module.meta.tags,
    tomap({ "name" : "${module.meta.rds_name_prefix}-${local.target_rds_major_version}-cluster-param-group" })
  )

  lifecycle {
    create_before_destroy = true
  }
}

moved {
  from = aws_db_subnet_group.database_subnet_group
  to   = aws_db_subnet_group.database_subnet_group[0]
}

resource "aws_db_subnet_group" "database_subnet_group" {
  count       = var.db_subnet_group_name != null ? 0 : 1
  name        = "${module.meta.rds_name_prefix}-subnet-group"
  description = "For Aurora ${local.engine} cluster ${var.database_name}"
  subnet_ids = [
    var.trusted_vpc_az1_database_subnet_id,
    var.trusted_vpc_az2_database_subnet_id,
    var.trusted_vpc_az3_database_subnet_id
  ]
  tags = module.meta.tags
}




resource "aws_cloudwatch_log_group" "rds" {
  count             = length(var.enabled_cloudwatch_logs_exports) > 0 ? 1 : 0
  name              = "/aws/rds/cluster/${module.meta.rds_name_prefix}-cluster/postgresql"
  retention_in_days = 7
  kms_key_id        = var.kms_key_arn
  tags = merge(
    module.meta.tags
  )
}

resource "aws_rds_cluster" "database_cluster" {
  depends_on = [
    aws_cloudwatch_log_group.rds
  ]
  snapshot_identifier             = var.snapshot_identifier
  engine                          = var.engine
  engine_mode                     = var.engine_mode
  engine_version                  = var.rds_engine_version
  cluster_identifier              = var.cluster_name_override != null ? var.cluster_name_override : "${module.meta.rds_name_prefix}-cluster"
  master_username                 = "adminmiscloud"
  master_password                 = var.rds_credentials[var.database_name]["password"]
  allow_major_version_upgrade     = var.allow_major_version_upgrade
  copy_tags_to_snapshot           = var.copy_tags_to_snapshot
  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

  dynamic "scaling_configuration" {
    for_each = var.engine_mode == "serverless" && var.rds_aurora_version == "v1_serverless" ? [1] : []
    content {
      max_capacity             = var.scaling_config_max_capacity
      min_capacity             = var.scaling_config_min_capacity
      auto_pause               = var.scaling_config_auto_pause
      seconds_until_auto_pause = var.scaling_config_seconds_until_auto_pause
      timeout_action           = var.scaling_config_timeout_action
    }
  }

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.instance_class == "db.serverless" && var.rds_aurora_version == "v2_serverless" ? [1] : []
    content {
      max_capacity = var.scaling_config_max_capacity
      min_capacity = var.scaling_config_min_capacity
    }
  }

  db_subnet_group_name = var.db_subnet_group_name != null ? var.db_subnet_group_name : aws_db_subnet_group.database_subnet_group[0].id
  vpc_security_group_ids = [
    var.general_access_security_group_id
  ]
  database_name                   = var.database_name
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name != null ? var.db_cluster_parameter_group_name : aws_rds_cluster_parameter_group.parameter_group[0].id
  storage_encrypted               = var.storage_encrypted
  kms_key_id                      = var.kms_key_arn
  backup_retention_period         = var.backup_retention_period
  apply_immediately               = var.apply_modifications_immediately
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.database_skip_final_snapshot
  final_snapshot_identifier       = var.database_skip_final_snapshot == false ? replace("${var.database_name}-cluster-db-final-snapshot", "_", "-") : null
  tags = merge(module.meta.tags,
    tomap({
      "rds-svc-backup-plan" = var.backup_plan_tag,
      "application_owner"   = var.application_owner,
      "data_classification" = var.data_classification
    })
  )
  lifecycle {
    ignore_changes = [
      database_name
    ]
  }
}

resource "aws_rds_cluster_instance" "v2_serverless_cluster_instance" {
  count                                 = var.instance_class == "db.serverless" && var.rds_aurora_version == "v2_serverless" ? var.instance_count : 0
  cluster_identifier                    = aws_rds_cluster.database_cluster.id
  identifier                            = "${aws_rds_cluster.database_cluster.id}-${count.index}"
  instance_class                        = var.instance_class
  engine                                = var.engine
  engine_version                        = var.rds_engine_version
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = local.performance_insights_kms_key_id
  ca_cert_identifier                    = var.ca_cert_identifier
  db_subnet_group_name                  = var.db_subnet_group_name != null ? var.db_subnet_group_name : aws_db_subnet_group.database_subnet_group[0].id
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.rds_monitoring_role_arn
  publicly_accessible                   = var.publicly_accessible
  apply_immediately                     = var.apply_modifications_immediately
  promotion_tier                        = var.promotion_tier

  tags = merge(module.meta.tags,
    tomap({
      "application_owner"   = var.application_owner,
      "data_classification" = var.data_classification
    })
  )

  lifecycle {
    ignore_changes = [
      # CA cert is automatically rotated by AWS - ignore to prevent drift
      ca_cert_identifier,
      # Engine version is auto-upgraded when auto_minor_version_upgrade = true
      # Sync manually after AWS upgrades by updating rds_engine_version variable
      engine_version,
    ]
  }
}


resource "aws_rds_cluster_instance" "provisioned_cluster_instance" {
  depends_on = [
    aws_rds_cluster.database_cluster
  ]
  for_each                              = toset(var.provisioned_database_availability_zones)
  cluster_identifier                    = aws_rds_cluster.database_cluster.id
  identifier                            = "${aws_rds_cluster.database_cluster.id}-${substr(each.key, length(each.key) - 1, 1)}"
  instance_class                        = var.instance_class
  engine                                = var.engine
  engine_version                        = var.rds_engine_version
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = local.performance_insights_kms_key_id
  ca_cert_identifier                    = var.ca_cert_identifier
  db_subnet_group_name                  = var.db_subnet_group_name != null ? var.db_subnet_group_name : aws_db_subnet_group.database_subnet_group[0].id
  availability_zone                     = each.key
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.rds_monitoring_role_arn
  publicly_accessible                   = var.publicly_accessible
  apply_immediately                     = var.apply_modifications_immediately
  promotion_tier                        = var.promotion_tier
  lifecycle {
    ignore_changes = [
      # CA cert is automatically rotated by AWS - ignore to prevent drift
      ca_cert_identifier,
      # Engine version is auto-upgraded when auto_minor_version_upgrade = true
      # Sync manually after AWS upgrades by updating rds_engine_version variable
      engine_version,
    ]
  }
  tags = merge(module.meta.tags,
    tomap({
      "application_owner"   = var.application_owner,
      "data_classification" = var.data_classification
    })
  )
}



