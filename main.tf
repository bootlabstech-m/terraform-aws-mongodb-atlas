# Use the existing MongoDB Atlas project (looked up by name).
data "mongodbatlas_project" "existing_project" {
  name = var.atlas_project_name
}

locals {
  # Atlas dedicated tiers in ascending order, used to validate autoscaling bounds.
  atlas_tiers = ["M10", "M20", "M30", "M40", "M50", "M60", "M80", "M140", "M200", "M250", "M300", "M400"]

  compute_scale_down = var.compute_auto_scaling_enabled && var.compute_scale_down_enabled

  cluster_tags = merge(
    {
      ProjectOwner = var.tag_project_owner
      BusinessUnit = var.tag_business_unit
      CostCenter   = var.tag_cost_center
      Application  = var.tag_application
      Cloud        = var.tag_cloud
      ProjectName  = coalesce(var.tag_project_name, var.atlas_project_name)
    },
    var.additional_tags
  )
}

# Create MongoDB Atlas Cluster on GCP in the existing project.
resource "mongodbatlas_advanced_cluster" "mongodb_cluster" {
  project_id   = data.mongodbatlas_project.existing_project.id
  name         = var.cluster_name
  cluster_type = "REPLICASET"

  # Cloud Backup (snapshots) and Continuous Cloud Backup (Point-in-Time Restore).
  backup_enabled = true
  pit_enabled    = var.pit_enabled

  tags = local.cluster_tags
  # Keep the configured specs stable in state so Atlas autoscaling does not cause plan drift.
  use_effective_fields = true

  replication_specs = [
    {
      region_configs = [
        {
          provider_name = "GCP"
          region_name   = var.gcp_region
          priority      = 7

          electable_specs = {
            instance_size = var.cluster_instance_size
            # Atlas replica sets always run 3 electable nodes; not exposed as an input.
            node_count   = 3
            disk_size_gb = var.disk_size_gb
          }

          auto_scaling = {
            compute_enabled            = var.compute_auto_scaling_enabled
            compute_scale_down_enabled = local.compute_scale_down
            compute_min_instance_size  = local.compute_scale_down ? var.compute_min_instance_size : null
            compute_max_instance_size  = var.compute_auto_scaling_enabled ? var.compute_max_instance_size : null
            disk_gb_enabled            = var.disk_auto_scaling_enabled
          }
        }
      ]
    }
  ]

  lifecycle {
    precondition {
      condition = !var.compute_auto_scaling_enabled || (
        index(local.atlas_tiers, var.compute_min_instance_size) <= index(local.atlas_tiers, var.cluster_instance_size) &&
        index(local.atlas_tiers, var.cluster_instance_size) <= index(local.atlas_tiers, var.compute_max_instance_size)
      )
      error_message = "With compute autoscaling enabled, cluster_instance_size must be between compute_min_instance_size and compute_max_instance_size."
    }
  }
}

# Create MongoDB Database User in the existing project.
resource "mongodbatlas_database_user" "mongodb_user" {
  username           = var.db_username
  password           = var.db_password
  project_id         = data.mongodbatlas_project.existing_project.id
  auth_database_name = "admin"

  roles {
    role_name     = "readWrite"
    database_name = "application"
  }
}

# Optional: allow your application IP to connect to Atlas.
# resource "mongodbatlas_project_ip_access_list" "gcp_access" {
#   project_id = data.mongodbatlas_project.existing_project.id
#   ip_address = "YOUR_GCP_APPLICATION_PUBLIC_IP"
#   comment    = "GCP application access"
# }

# ==================== Backup ====================

# Backup schedule: daily snapshots with configurable retention.
resource "mongodbatlas_cloud_backup_schedule" "backup" {
  project_id   = mongodbatlas_advanced_cluster.mongodb_cluster.project_id
  cluster_name = mongodbatlas_advanced_cluster.mongodb_cluster.name

  reference_hour_of_day    = var.backup_reference_hour_utc
  reference_minute_of_hour = 0

  # Point-in-Time Restore window (only used when pit_enabled = true).
  restore_window_days = var.pit_enabled ? var.pit_restore_window_days : null

  # Continuous Cloud Backup (PIT) requires an hourly policy item.
  dynamic "policy_item_hourly" {
    for_each = var.pit_enabled ? [1] : []
    content {
      frequency_interval = var.backup_hourly_interval_hours
      retention_unit     = "days"
      retention_value    = var.backup_hourly_retention_days
    }
  }

  policy_item_daily {
    frequency_interval = 1
    retention_unit     = "days"
    retention_value    = var.backup_daily_retention_days
  }

  lifecycle {
    precondition {
      condition     = !var.pit_enabled || var.pit_restore_window_days <= var.backup_daily_retention_days
      error_message = "pit_restore_window_days must be less than or equal to backup_daily_retention_days."
    }
    precondition {
      condition     = !var.pit_enabled || var.backup_hourly_retention_days <= var.backup_daily_retention_days
      error_message = "backup_hourly_retention_days must be less than or equal to backup_daily_retention_days."
    }
    precondition {
      condition     = !var.pit_enabled || var.pit_restore_window_days <= var.backup_hourly_retention_days
      error_message = "pit_restore_window_days must be less than or equal to backup_hourly_retention_days (Atlas rule)."
    }
  }
}

# ==================== Monitoring / Alerts ====================

locals {
  # Atlas host names start with the lower-case cluster name (e.g. mycluster-shard-00-00.xxxx.mongodb.net),
  # so host alerts are scoped to this cluster only, not other clusters in the shared project.
  cluster_host_prefix = "${lower(var.cluster_name)}-shard-"

  # Host metric alerts: metric name => threshold settings.
  metric_alerts = {
    cpu = {
      metric_name = "NORMALIZED_SYSTEM_CPU_USER"
      threshold   = var.alert_cpu_percent
      units       = "RAW"
      delay_min   = 0
    }
    disk = {
      metric_name = "DISK_PARTITION_SPACE_USED_DATA"
      threshold   = var.alert_disk_percent
      units       = "RAW"
      delay_min   = 0
    }
    connections = {
      metric_name = "CONNECTIONS_PERCENT"
      threshold   = var.alert_connections_percent
      units       = "RAW"
      delay_min   = 0
    }
    # Atlas requires a non-zero notification delay for replication lag.
    replication_lag = {
      metric_name = "OPLOG_SLAVE_LAG_MASTER_TIME"
      threshold   = var.alert_replication_lag_seconds
      units       = "SECONDS"
      delay_min   = var.alert_replication_lag_delay_min
    }
  }
}

resource "mongodbatlas_alert_configuration" "metric" {
  for_each = var.alerts_enabled ? local.metric_alerts : {}

  project_id = mongodbatlas_advanced_cluster.mongodb_cluster.project_id
  event_type = "OUTSIDE_METRIC_THRESHOLD"
  enabled    = true

  matcher {
    field_name = "HOSTNAME"
    operator   = "STARTS_WITH"
    value      = local.cluster_host_prefix
  }

  metric_threshold_config {
    metric_name = each.value.metric_name
    operator    = "GREATER_THAN"
    threshold   = each.value.threshold
    units       = each.value.units
    mode        = "AVERAGE"
  }

  notification {
    type_name     = "GROUP"
    roles         = ["GROUP_OWNER"]
    email_enabled = true
    sms_enabled   = false
    delay_min     = each.value.delay_min
    interval_min  = var.alert_interval_min
  }
}

# Critical CPU alert. Atlas alerts cannot filter on the current tier, so this fires at any tier;
# below the max tier, compute autoscaling normally scales up before CPU stays this high.
resource "mongodbatlas_alert_configuration" "cpu_critical" {
  count = var.alerts_enabled ? 1 : 0

  project_id        = mongodbatlas_advanced_cluster.mongodb_cluster.project_id
  event_type        = "OUTSIDE_METRIC_THRESHOLD"
  enabled           = true
  severity_override = "CRITICAL"

  matcher {
    field_name = "HOSTNAME"
    operator   = "STARTS_WITH"
    value      = local.cluster_host_prefix
  }

  metric_threshold_config {
    metric_name = "NORMALIZED_SYSTEM_CPU_USER"
    operator    = "GREATER_THAN"
    threshold   = var.alert_cpu_critical_percent
    units       = "RAW"
    mode        = "AVERAGE"
  }

  notification {
    type_name     = "GROUP"
    roles         = ["GROUP_OWNER"]
    email_enabled = true
    sms_enabled   = false
    delay_min     = 0
    interval_min  = var.alert_cpu_critical_interval_min
  }
}

# Fires when compute autoscaling needs to scale up but the cluster is already at compute_max_instance_size.
# This event type does not support matchers, so it covers all clusters in the project.
resource "mongodbatlas_alert_configuration" "max_tier_reached" {
  count = var.alerts_enabled && var.compute_auto_scaling_enabled ? 1 : 0

  project_id        = mongodbatlas_advanced_cluster.mongodb_cluster.project_id
  event_type        = "COMPUTE_AUTO_SCALE_MAX_INSTANCE_SIZE_FAIL_BASE"
  enabled           = true
  severity_override = "CRITICAL"

  notification {
    type_name     = "GROUP"
    roles         = ["GROUP_OWNER"]
    email_enabled = true
    sms_enabled   = false
    delay_min     = 0
    interval_min  = var.alert_cpu_critical_interval_min
  }
}

resource "mongodbatlas_alert_configuration" "host_down" {
  count = var.alerts_enabled ? 1 : 0

  project_id = mongodbatlas_advanced_cluster.mongodb_cluster.project_id
  event_type = "HOST_DOWN"
  enabled    = true

  matcher {
    field_name = "HOSTNAME"
    operator   = "STARTS_WITH"
    value      = local.cluster_host_prefix
  }

  notification {
    type_name     = "GROUP"
    roles         = ["GROUP_OWNER"]
    email_enabled = true
    sms_enabled   = false
    delay_min     = 0
    interval_min  = var.alert_interval_min
  }
}

resource "mongodbatlas_alert_configuration" "no_primary" {
  count = var.alerts_enabled ? 1 : 0

  project_id = mongodbatlas_advanced_cluster.mongodb_cluster.project_id
  event_type = "NO_PRIMARY"
  enabled    = true

  matcher {
    field_name = "CLUSTER_NAME"
    operator   = "EQUALS"
    value      = mongodbatlas_advanced_cluster.mongodb_cluster.name
  }

  notification {
    type_name     = "GROUP"
    roles         = ["GROUP_OWNER"]
    email_enabled = true
    sms_enabled   = false
    delay_min     = 0
    interval_min  = var.alert_interval_min
  }
}
