# =============================================================================
# Output Values
# =============================================================================

# -----------------------------------------------------------------------------
# TPU VM Outputs
# -----------------------------------------------------------------------------

output "tpu_id" {
  description = "The unique identifier of the TPU VM"
  value       = google_tpu_v2_vm.tpu.id
}

output "tpu_vm_name" {
  description = "The name of the TPU VM"
  value       = google_tpu_v2_vm.tpu.name
}

output "tpu_vm_zone" {
  description = "The zone where the TPU VM is located"
  value       = google_tpu_v2_vm.tpu.zone
}

output "tpu_vm_state" {
  description = "The current state of the TPU VM (e.g., READY, CREATING)"
  value       = google_tpu_v2_vm.tpu.state
}

output "tpu_network_endpoints" {
  description = "Network endpoints for connecting to TPU workers"
  value       = google_tpu_v2_vm.tpu.network_endpoints
}

# -----------------------------------------------------------------------------
# TPU Node Configuration Outputs
# -----------------------------------------------------------------------------

output "tpu_accelerator_type" {
  description = "The TPU accelerator type"
  value       = var.tpu_accelerator_type
}

output "tpu_runtime_version" {
  description = "The TPU runtime version"
  value       = var.tpu_runtime_version
}

output "tpu_node_id" {
  description = "The TPU node name"
  value       = var.tpu_name
}

output "tpu_public_ip_enabled" {
  description = "Whether public (external) IPs are enabled for TPU workers"
  value       = var.enable_external_ips
}

output "tpu_on_demand" {
  description = "Whether the TPU is on-demand (non-spot, non-preemptible)"
  value       = !var.tpu_spot && !var.tpu_preemptible
}

# -----------------------------------------------------------------------------
# Disk Outputs
# -----------------------------------------------------------------------------

output "disk_id" {
  description = "The unique identifier of the persistent disk"
  value       = google_compute_disk.tpu_disk.id
}

output "disk_name" {
  description = "The name of the persistent disk"
  value       = google_compute_disk.tpu_disk.name
}

output "disk_self_link" {
  description = "The self link of the persistent disk"
  value       = google_compute_disk.tpu_disk.self_link
}

output "disk_zone" {
  description = "The zone where the disk is located"
  value       = google_compute_disk.tpu_disk.zone
}

output "disk_size_gb" {
  description = "The size of the disk in GB"
  value       = google_compute_disk.tpu_disk.size
}

output "disk_type" {
  description = "The type of the persistent disk"
  value       = google_compute_disk.tpu_disk.type
}

# -----------------------------------------------------------------------------
# Connection Summary
# -----------------------------------------------------------------------------

output "connection_info" {
  description = "Summary of the TPU VM and disk configuration"
  value = {
    tpu_name         = google_tpu_v2_vm.tpu.name
    tpu_zone         = google_tpu_v2_vm.tpu.zone
    accelerator_type = var.tpu_accelerator_type
    runtime_version  = var.tpu_runtime_version
    public_ip_enabled = var.enable_external_ips
    on_demand        = !var.tpu_spot && !var.tpu_preemptible
    disk_name        = google_compute_disk.tpu_disk.name
    disk_zone        = google_compute_disk.tpu_disk.zone
    disk_attached    = var.attach_disk_to_tpu
    attachment_mode  = var.attach_disk_to_tpu ? var.disk_attachment_mode : "N/A"
  }
}

# -----------------------------------------------------------------------------
# Available TPU Configurations (for reference)
# -----------------------------------------------------------------------------

output "available_runtime_versions" {
  description = "Available TPU runtime versions in the specified zone"
  value       = data.google_tpu_v2_runtime_versions.available.versions
}

output "available_accelerator_types" {
  description = "Available TPU accelerator types in the specified zone"
  value       = data.google_tpu_v2_accelerator_types.available.types
}
