# =============================================================================
# Instance Outputs
# =============================================================================

output "instance_id" {
  value       = google_compute_instance.vm.instance_id
  description = "Compute Engine instance ID"
}

output "instance_name" {
  value       = google_compute_instance.vm.name
  description = "Compute Engine instance name"
}

output "instance_zone" {
  value       = google_compute_instance.vm.zone
  description = "Compute Engine instance zone"
}

output "instance_external_ip" {
  value       = google_compute_instance.vm.network_interface[0].access_config[0].nat_ip
  description = "External IP address of the instance"
}

output "instance_internal_ip" {
  value       = google_compute_instance.vm.network_interface[0].network_ip
  description = "Internal IP address of the instance"
}

output "instance_self_link" {
  value       = google_compute_instance.vm.self_link
  description = "Self-link URI of the instance"
}

# =============================================================================
# Network Outputs
# =============================================================================

output "vpc_network" {
  value       = var.create_vpc ? google_compute_network.vpc[0].name : var.network_name
  description = "VPC network name"
}

output "subnet_name" {
  value       = var.create_vpc ? google_compute_subnetwork.subnet[0].name : var.subnet_name
  description = "Subnet name"
}

# =============================================================================
# Service Account Outputs
# =============================================================================

output "instance_service_account" {
  value       = google_service_account.instance_sa.email
  description = "Service account email attached to the instance"
}

output "cloud_function_service_account" {
  value       = google_service_account.cloud_function_sa.email
  description = "Service account email used by the Cloud Function"
}

# =============================================================================
# Monitoring Outputs
# =============================================================================

output "alert_policy_name" {
  value       = google_monitoring_alert_policy.cpu_idle.name
  description = "Cloud Monitoring alert policy resource name"
}

output "pubsub_topic" {
  value       = google_pubsub_topic.idle_alerts.name
  description = "Pub/Sub topic for idle instance alerts"
}

output "cloud_function_name" {
  value       = google_cloudfunctions2_function.stop_idle_instance.name
  description = "Cloud Function name for stopping idle instances"
}

output "cloud_function_uri" {
  value       = google_cloudfunctions2_function.stop_idle_instance.service_config[0].uri
  description = "Cloud Function URI"
}

# =============================================================================
# Autoshutdown Configuration Summary
# =============================================================================

output "autoshutdown_config" {
  value = {
    primary_method   = "Cloud Monitoring: CPU < ${var.cpu_threshold * 100}% for ${var.cpu_idle_duration_seconds / 60} min → Pub/Sub → Cloud Function stops instance"
    secondary_method = "Startup script: SSH idle check every ${var.ssh_idle_check_interval_minutes} min, shutdown after ${var.ssh_idle_threshold_checks} consecutive idle checks (${local.ssh_idle_timeout_minutes} min)"
    boot_grace       = "${var.ssh_boot_grace_period_minutes} minutes"
  }
  description = "Summary of auto-shutdown configuration"
}

# =============================================================================
# Connection Commands
# =============================================================================

output "ssh_command" {
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${var.zone} --project=${var.project_id}"
  description = "gcloud command to SSH into the instance"
}

output "iap_ssh_command" {
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${var.zone} --project=${var.project_id} --tunnel-through-iap"
  description = "gcloud command to SSH via IAP tunnel"
}

output "start_instance_command" {
  value       = "gcloud compute instances start ${google_compute_instance.vm.name} --zone=${var.zone} --project=${var.project_id}"
  description = "gcloud command to restart the instance after auto-shutdown"
}

output "check_autoshutdown_log_command" {
  value       = "gcloud compute ssh ${google_compute_instance.vm.name} --zone=${var.zone} --project=${var.project_id} --command='cat /var/log/autoshutdown.log'"
  description = "gcloud command to check the auto-shutdown log"
}
