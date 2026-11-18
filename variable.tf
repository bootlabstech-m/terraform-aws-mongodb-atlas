variable "mongodb_atlas_client_id" {
  description = "MongoDB Atlas Service Account Client ID (mdb_sa_id_...). Leave null when using an API key."
  type        = string
  sensitive   = true
  default     = null
}

variable "mongodb_atlas_client_secret" {
  description = "MongoDB Atlas Service Account Client Secret (mdb_sa_sk_...). Leave null when using an API key."
  type        = string
  sensitive   = true
  default     = null
}

variable "mongodb_atlas_public_key" {
  description = "MongoDB Atlas API public key. Leave null when using a Service Account."
  type        = string
  sensitive   = true
  default     = null
}

variable "mongodb_atlas_private_key" {
  description = "MongoDB Atlas API private key. Leave null when using a Service Account."
  type        = string
  sensitive   = true
  default     = null
}

variable "atlas_org_id" {
  description = "MongoDB Atlas Organization ID (optional, not used for project lookup)"
  type        = string
  default     = null
}

variable "atlas_project_name" {
  description = "MongoDB Atlas project name"
  type        = string
  
}

variable "cluster_name" {
  description = "MongoDB Atlas cluster name"
  type        = string
  
}

variable "gcp_region" {
  description = "GCP region in Atlas format"
  type        = string
  default     = "ASIA_SOUTH1"
}

variable "cluster_instance_size" {
  description = "Starting MongoDB Atlas instance tier (e.g. M10)"
  type        = string

  validation {
    condition     = contains(["M10", "M20", "M30", "M40", "M50", "M60", "M80", "M140", "M200", "M250", "M300", "M400"], var.cluster_instance_size)
    error_message = "cluster_instance_size must be a dedicated Atlas tier such as M10, M20, M30, M40..."
  }
}

variable "compute_auto_scaling_enabled" {
  description = "Enable compute (instance tier) autoscaling"
  type        = bool
  default     = true
}

variable "compute_scale_down_enabled" {
  description = "Allow compute autoscaling to scale down to compute_min_instance_size"
  type        = bool
  default     = true
}

variable "compute_min_instance_size" {
  description = "Minimum tier for compute autoscaling"
  type        = string
    validation {
    condition     = contains(["M10", "M20", "M30", "M40", "M50", "M60", "M80", "M140", "M200", "M250", "M300", "M400"], var.compute_min_instance_size)
    error_message = "compute_min_instance_size must be a dedicated Atlas tier such as M10, M20, M30..."
  }
}

variable "compute_max_instance_size" {
  description = "Maximum tier for compute autoscaling"
  type        = string
 
  validation {
    condition     = contains(["M10", "M20", "M30", "M40", "M50", "M60", "M80", "M140", "M200", "M250", "M300", "M400"], var.compute_max_instance_size)
    error_message = "compute_max_instance_size must be a dedicated Atlas tier such as M20, M30, M40..."
  }
}

variable "disk_auto_scaling_enabled" {
  description = "Enable storage autoscaling. Atlas grows disk automatically up to the maximum allowed for the current tier."
  type        = bool
  default     = true
}

variable "disk_size_gb" {
  description = "Starting disk size in GB (Atlas UI 'Storage' slider, e.g. 10-128 GB for M10). Leave null to use the Atlas default for the tier."
  type        = number
  default     = null

  validation {
    condition     = var.disk_size_gb == null || try(var.disk_size_gb >= 10, false)
    error_message = "disk_size_gb must be at least 10 GB."
  }
}

# ---------- Backup ----------

variable "pit_enabled" {
  description = "Enable Continuous Cloud Backup (Point-in-Time Restore)"
  type        = bool
  default     = true
}

variable "pit_restore_window_days" {
  description = "How many days back you can do a Point-in-Time Restore"
  type        = number
  default     = 7
}

variable "backup_daily_retention_days" {
  description = "How many days daily snapshots are kept"
  type        = number
  default     = 7
}

variable "backup_hourly_interval_hours" {
  description = "Hours between snapshots for the hourly policy (required by Point-in-Time Restore)"
  type        = number
  default     = 6

  validation {
    condition     = contains([1, 2, 4, 6, 8, 12], var.backup_hourly_interval_hours)
    error_message = "backup_hourly_interval_hours must be one of 1, 2, 4, 6, 8, 12."
  }
}

variable "backup_hourly_retention_days" {
  description = "How many days hourly snapshots are kept (only used when pit_enabled = true). Must be >= pit_restore_window_days."
  type        = number
  default     = 7
}

variable "backup_reference_hour_utc" {
  description = "Hour of day (UTC, 0-23) when the daily snapshot is taken"
  type        = number
  default     = 20 # 20:00 UTC = 01:30 IST next day

  validation {
    condition     = var.backup_reference_hour_utc >= 0 && var.backup_reference_hour_utc <= 23
    error_message = "backup_reference_hour_utc must be between 0 and 23."
  }
}

# ---------- Monitoring / Alerts ----------

variable "alerts_enabled" {
  description = "Create alert configurations for this cluster (notifies Project Owners by email)"
  type        = bool
  default     = true
}

variable "alert_cpu_percent" {
  description = "Alert when normalized CPU usage is above this percent"
  type        = number
  default     = 80
}

variable "alert_disk_percent" {
  description = "Alert when data disk usage is above this percent"
  type        = number
  default     = 80
}

variable "alert_connections_percent" {
  description = "Alert when connections are above this percent of the tier maximum"
  type        = number
  default     = 80
}

variable "alert_replication_lag_seconds" {
  description = "Alert when replication lag is above this many seconds"
  type        = number
  default     = 60
}

variable "alert_replication_lag_delay_min" {
  description = "Minutes to wait before sending a replication lag alert (Atlas requires > 0)"
  type        = number
  default     = 5

  validation {
    condition     = var.alert_replication_lag_delay_min > 0
    error_message = "alert_replication_lag_delay_min must be greater than 0."
  }
}

variable "alert_cpu_critical_percent" {
  description = "Critical alert when normalized CPU usage is above this percent (meant for when the cluster is at the max tier)"
  type        = number
  default     = 90
}

variable "alert_cpu_critical_interval_min" {
  description = "Minutes between repeat notifications for critical alerts (CPU critical, max tier reached; minimum 5)"
  type        = number
  default     = 15
}

variable "alert_interval_min" {
  description = "Minutes between repeat notifications for an open alert (minimum 5)"
  type        = number
  default     = 60
}

variable "db_username" {
  type    = string
  default = "appuser"
}

variable "db_password" {
  type      = string
  sensitive = true
}
# ---------- Tags ----------
# Atlas tag keys/values: 1-255 chars; letters, numbers, spaces and _ . + - = : / @ only.

variable "tag_project_owner" {
  description = "Tag: owner of the project (name or email)"
  type        = string
}

variable "tag_business_unit" {
  description = "Tag: business unit"
  type        = string
}

variable "tag_cost_center" {
  description = "Tag: cost center code"
  type        = string
}

variable "tag_application" {
  description = "Tag: application name"
  type        = string
}

variable "tag_cloud" {
  description = "Tag: cloud provider"
  type        = string
  default     = "GCP"
}

variable "tag_project_name" {
  description = "Tag: project name. Leave null to use atlas_project_name."
  type        = string
  default     = null
}

variable "additional_tags" {
  description = "Any extra tags to add to the cluster, e.g. { Environment = \"dev\" }"
  type        = map(string)
  default     = {}
}
