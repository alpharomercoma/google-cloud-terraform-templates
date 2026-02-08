# =============================================================================
# Cloud Monitoring Auto-Shutdown (Primary Mechanism)
# =============================================================================
#
# Architecture:
#   Cloud Monitoring Alert Policy (CPU < 5% for 15 min)
#     → Pub/Sub Topic (notification channel)
#       → Cloud Function (2nd gen, stops the instance)
#
# GCP equivalent of AWS CloudWatch Alarm → EC2 Stop Action
# =============================================================================

# =============================================================================
# Enable Required APIs
# =============================================================================

resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  project = var.project_id
  service = "pubsub.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloudfunctions" {
  project = var.project_id
  service = "cloudfunctions.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "run" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  project = var.project_id
  service = "eventarc.googleapis.com"

  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  project = var.project_id
  service = "monitoring.googleapis.com"

  disable_on_destroy = false
}

# =============================================================================
# Pub/Sub Topic for Alert Notifications
# =============================================================================

resource "google_pubsub_topic" "idle_alerts" {
  name   = "compute-idle-alerts-${random_id.suffix.hex}"
  labels = local.common_labels

  depends_on = [google_project_service.pubsub]
}

# =============================================================================
# Cloud Monitoring Notification Channel (Pub/Sub)
# =============================================================================

resource "google_monitoring_notification_channel" "pubsub" {
  display_name = "Compute Idle Alert - Pub/Sub"
  type         = "pubsub"

  labels = {
    topic = google_pubsub_topic.idle_alerts.id
  }

  depends_on = [google_project_service.monitoring]
}

# Grant Cloud Monitoring permission to publish to the Pub/Sub topic
resource "google_pubsub_topic_iam_member" "monitoring_publisher" {
  topic  = google_pubsub_topic.idle_alerts.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
}

# =============================================================================
# Cloud Monitoring Alert Policy (CPU Idle Detection)
# =============================================================================

resource "google_monitoring_alert_policy" "cpu_idle" {
  display_name = "Compute Auto-Shutdown - CPU Idle (${google_compute_instance.vm.name})"
  combiner     = "OR"

  documentation {
    content = <<-EOT
      ## Auto-Shutdown Alert

      Instance **${google_compute_instance.vm.name}** in zone **${var.zone}** has CPU
      utilization below ${var.cpu_threshold * 100}% for over ${var.cpu_idle_duration_seconds / 60} minutes,
      indicating it is idle.

      The Cloud Function will automatically stop this instance.

      To restart: `gcloud compute instances start ${google_compute_instance.vm.name} --zone=${var.zone}`
    EOT
  }

  conditions {
    display_name = "CPU utilization below ${var.cpu_threshold * 100}%"

    condition_threshold {
      filter = "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\" AND resource.labels.instance_id = \"${google_compute_instance.vm.instance_id}\""

      duration        = "${var.cpu_idle_duration_seconds}s"
      comparison      = "COMPARISON_LT"
      threshold_value = var.cpu_threshold

      aggregations {
        alignment_period   = "${var.cpu_alignment_period_seconds}s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.pubsub.name
  ]

  alert_strategy {
    auto_close = "604800s" # 7 days
  }

  depends_on = [google_project_service.monitoring]
}

# =============================================================================
# Cloud Function Service Account
# =============================================================================

resource "google_service_account" "cloud_function_sa" {
  account_id   = "autoshutdown-fn-${random_id.suffix.hex}"
  display_name = "Autoshutdown Cloud Function SA"
  description  = "Service account for the auto-shutdown Cloud Function"
}

# Grant the Cloud Function permission to stop Compute Engine instances
resource "google_project_iam_member" "function_compute_admin" {
  project = var.project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.cloud_function_sa.email}"
}

# =============================================================================
# Cloud Function Source Archive
# =============================================================================

data "archive_file" "cloud_function" {
  type        = "zip"
  source_dir  = "${path.module}/cloud-function"
  output_path = "${path.module}/cloud-function.zip"
}

resource "google_storage_bucket" "function_source" {
  name     = "autoshutdown-fn-source-${random_id.suffix.hex}"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  labels = local.common_labels
}

resource "google_storage_bucket_object" "function_source" {
  name   = "cloud-function-${data.archive_file.cloud_function.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.cloud_function.output_path
}

# =============================================================================
# Cloud Function (2nd Gen) - Stops Idle Instances
# =============================================================================

resource "google_cloudfunctions2_function" "stop_idle_instance" {
  name     = "stop-idle-instance-${random_id.suffix.hex}"
  location = var.region

  description = "Stops idle Compute Engine instances when triggered by Cloud Monitoring alerts"
  labels      = local.common_labels

  build_config {
    runtime     = "python312"
    entry_point = "stop_idle_instance"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 300
    service_account_email = google_service_account.cloud_function_sa.email

    environment_variables = {
      TARGET_PROJECT_ID    = var.project_id
      TARGET_ZONE          = var.zone
      TARGET_INSTANCE_NAME = google_compute_instance.vm.name
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.idle_alerts.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_project_service.cloudfunctions,
    google_project_service.cloudbuild,
    google_project_service.run,
    google_project_service.eventarc,
  ]
}

# =============================================================================
# Data Sources
# =============================================================================

data "google_project" "current" {
  project_id = var.project_id
}
