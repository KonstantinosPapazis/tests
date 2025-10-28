##############################################
# Aurora PostgreSQL Parameter Groups Module
# Optimized parameter groups for production use
##############################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

##############################################
# DB Cluster Parameter Group
# Cluster-level parameters that apply to all instances
##############################################

resource "aws_rds_cluster_parameter_group" "main" {
  name_prefix = "${var.name_prefix}-cluster-pg-"
  family      = var.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${var.name_prefix}"

  # Logging and Monitoring
  parameter {
    name  = "log_statement"
    value = var.log_statement
  }

  parameter {
    name  = "log_min_duration_statement"
    value = var.log_min_duration_statement
  }

  parameter {
    name  = "log_connections"
    value = var.log_connections ? "1" : "0"
  }

  parameter {
    name  = "log_disconnections"
    value = var.log_disconnections ? "1" : "0"
  }

  parameter {
    name  = "log_lock_waits"
    value = var.log_lock_waits ? "1" : "0"
  }

  parameter {
    name  = "log_temp_files"
    value = var.log_temp_files
  }

  # Query and Performance Tuning
  parameter {
    name  = "shared_preload_libraries"
    value = var.shared_preload_libraries
  }

  parameter {
    name  = "pg_stat_statements.track"
    value = "all"
  }

  parameter {
    name  = "pg_stat_statements.max"
    value = "10000"
  }

  # Autovacuum Configuration
  parameter {
    name  = "autovacuum_max_workers"
    value = var.autovacuum_max_workers
  }

  parameter {
    name  = "autovacuum_naptime"
    value = var.autovacuum_naptime
  }

  # Connection Settings
  parameter {
    name  = "max_connections"
    value = "LEAST({DBInstanceClassMemory/9531392},5000)"
    apply_method = "pending-reboot"
  }

  # Replication Settings
  parameter {
    name  = "max_replication_slots"
    value = var.max_replication_slots
  }

  parameter {
    name  = "max_wal_senders"
    value = var.max_wal_senders
  }

  # Timezone
  parameter {
    name  = "timezone"
    value = var.timezone
  }

  # SSL/TLS
  parameter {
    name  = "rds.force_ssl"
    value = var.force_ssl ? "1" : "0"
  }

  # Logical Replication (if needed)
  dynamic "parameter" {
    for_each = var.enable_logical_replication ? [1] : []
    content {
      name         = "rds.logical_replication"
      value        = "1"
      apply_method = "pending-reboot"
    }
  }

  # Additional custom parameters
  dynamic "parameter" {
    for_each = var.additional_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-cluster-parameter-group"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

##############################################
# DB Parameter Group (Instance-level)
# Parameters specific to individual instances
##############################################

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.name_prefix}-instance-pg-"
  family      = var.parameter_group_family
  description = "Aurora PostgreSQL instance parameter group for ${var.name_prefix}"

  # Memory Configuration
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/10922}"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "effective_cache_size"
    value = "{DBInstanceClassMemory*3/4/8192}"
    apply_method = "immediate"
  }

  parameter {
    name  = "work_mem"
    value = var.work_mem
  }

  parameter {
    name  = "maintenance_work_mem"
    value = var.maintenance_work_mem
  }

  # Query Planner
  parameter {
    name  = "random_page_cost"
    value = var.random_page_cost
  }

  parameter {
    name  = "effective_io_concurrency"
    value = var.effective_io_concurrency
  }

  # Checkpoints and WAL
  parameter {
    name  = "checkpoint_timeout"
    value = var.checkpoint_timeout
  }

  parameter {
    name  = "checkpoint_completion_target"
    value = var.checkpoint_completion_target
  }

  # Statement Timeout
  parameter {
    name  = "statement_timeout"
    value = var.statement_timeout
  }

  parameter {
    name  = "idle_in_transaction_session_timeout"
    value = var.idle_in_transaction_timeout
  }

  # Additional custom parameters
  dynamic "parameter" {
    for_each = var.additional_instance_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-instance-parameter-group"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

