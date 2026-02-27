# =============================================================================
# Input Variables
# =============================================================================

# -----------------------------------------------------------------------------
# Project Configuration
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "The default region for resources"
  type        = string
  default     = "us-central2"
}

# -----------------------------------------------------------------------------
# TPU Configuration
# -----------------------------------------------------------------------------

variable "tpu_name" {
  description = "The name of the TPU queued resource and node"
  type        = string
  default     = "tpuv4-alpha"
}

variable "tpu_zone" {
  description = "The zone where the TPU will be created"
  type        = string
  default     = "us-central2-b"
}

variable "tpu_accelerator_type" {
  description = "TPU accelerator type"
  type        = string
  default     = "v4-8"
}

variable "tpu_runtime_version" {
  description = "TPU software/runtime version"
  type        = string
  default     = "tpu-ubuntu2204-base"
}

variable "tpu_spot" {
  description = "Whether to use spot/preemptible TPU VM"
  type        = bool
  default     = false
}

variable "tpu_preemptible" {
  description = "Whether the TPU is preemptible"
  type        = bool
  default     = false
}

variable "tpu_labels" {
  description = "Labels to apply to the TPU VM"
  type        = map(string)
  default = {
    environment = "development"
    managed_by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Disk Configuration
# -----------------------------------------------------------------------------

variable "disk_name" {
  description = "The name of the persistent disk"
  type        = string
  default     = "tpuv4-alpha-disk"
}

variable "disk_zone" {
  description = "The zone where the disk will be created (must match TPU zone for attachment)"
  type        = string
  default     = "us-central2-b"
}

variable "disk_type" {
  description = "The type of persistent disk (pd-standard, pd-balanced, pd-ssd)"
  type        = string
  default     = "pd-balanced"
}

variable "disk_size_gb" {
  description = "The size of the disk in GB"
  type        = number
  default     = 50

  validation {
    condition     = var.disk_size_gb >= 10 && var.disk_size_gb <= 65536
    error_message = "Disk size must be between 10 GB and 65536 GB."
  }
}

variable "disk_labels" {
  description = "Labels to apply to the disk"
  type        = map(string)
  default = {
    environment = "development"
    managed_by  = "terraform"
  }
}

# -----------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------

variable "enable_external_ips" {
  description = "Whether to enable external (public) IPs for TPU workers"
  type        = bool
  default     = true
}

variable "network" {
  description = "The VPC network for the TPU (uses default if not specified)"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "The subnetwork for the TPU (uses default if not specified)"
  type        = string
  default     = "default"
}

# -----------------------------------------------------------------------------
# Disk Attachment Configuration
# -----------------------------------------------------------------------------

variable "attach_disk_to_tpu" {
  description = "Whether to attach the persistent disk to the TPU node"
  type        = bool
  default     = true
}

variable "disk_attachment_mode" {
  description = "The mode in which to attach the disk (READ_WRITE or READ_ONLY)"
  type        = string
  default     = "READ_WRITE"

  validation {
    condition     = contains(["READ_WRITE", "READ_ONLY"], var.disk_attachment_mode)
    error_message = "Disk attachment mode must be either READ_WRITE or READ_ONLY."
  }
}
