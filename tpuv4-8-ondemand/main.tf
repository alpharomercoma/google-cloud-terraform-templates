# =============================================================================
# Google Cloud TPU v4-8 On-Demand - Main Configuration
# =============================================================================
#
# This Terraform configuration creates:
# - A TPU v4-8 VM node (google_tpu_v2_vm)
# - A balanced persistent disk
# - Connects the disk to the TPU node
#
# NOTE: google_tpu_v2_queued_resource is severely incomplete in the Terraform
# provider (missing scheduling_config, data_disks, shielded_instance_config,
# labels, tags, metadata, and the guaranteed/spot blocks). Using
# google_tpu_v2_vm instead, which has full schema support.
#
# IMPORTANT: The disk must be in the same zone as the TPU for attachment.
# =============================================================================

# -----------------------------------------------------------------------------
# Local Values
# -----------------------------------------------------------------------------

locals {
  common_labels = merge(var.tpu_labels, {
    project = var.project_id
  })

  # Ensure disk zone matches TPU zone for attachment
  effective_disk_zone = var.attach_disk_to_tpu ? var.tpu_zone : var.disk_zone
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "google_tpu_v2_runtime_versions" "available" {
  provider = google-beta
  zone     = var.tpu_zone
}

data "google_tpu_v2_accelerator_types" "available" {
  provider = google-beta
  zone     = var.tpu_zone
}

# -----------------------------------------------------------------------------
# Persistent Disk Resource
# -----------------------------------------------------------------------------

resource "google_compute_disk" "tpu_disk" {
  name = var.disk_name
  type = var.disk_type
  zone = local.effective_disk_zone
  size = var.disk_size_gb

  labels = merge(local.common_labels, var.disk_labels)

  physical_block_size_bytes = 4096

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# TPU v4-8 VM
# -----------------------------------------------------------------------------
#
# google_tpu_v2_vm provisions a TPU VM directly with full schema support.
# It supports scheduling_config (spot/preemptible), data_disks, labels, tags,
# metadata, and shielded_instance_config — unlike google_tpu_v2_queued_resource
# which is missing all of those fields in the current Terraform provider.
# -----------------------------------------------------------------------------

resource "google_tpu_v2_vm" "tpu" {
  provider = google-beta

  name = var.tpu_name
  zone = var.tpu_zone

  accelerator_type = var.tpu_accelerator_type
  runtime_version  = var.tpu_runtime_version
  description      = "TPU v4-8 on-demand node - managed by Terraform"

  # Network Configuration
  network_config {
    network             = var.network
    subnetwork          = var.subnetwork
    enable_external_ips = var.enable_external_ips
    can_ip_forward      = false
  }

  # Scheduling Configuration - on-demand (not spot, not preemptible)
  scheduling_config {
    preemptible = var.tpu_preemptible
    spot        = var.tpu_spot
  }

  # Data Disk Attachment
  dynamic "data_disks" {
    for_each = var.attach_disk_to_tpu ? [1] : []
    content {
      source_disk = google_compute_disk.tpu_disk.id
      mode        = var.disk_attachment_mode
    }
  }

  # Shielded Instance Configuration
  shielded_instance_config {
    enable_secure_boot = true
  }

  labels = local.common_labels
  tags   = ["tpu-vm", "ml-workload"]

  metadata = {
    managed_by = "terraform"
  }

  depends_on = [google_compute_disk.tpu_disk]

  lifecycle {
    ignore_changes = [
      labels["goog-dataproc-cluster-name"],
      labels["goog-dataproc-cluster-uuid"],
    ]
  }
}
