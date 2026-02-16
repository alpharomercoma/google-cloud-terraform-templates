# =============================================================================
# Project & Region
# =============================================================================

variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string
}

variable "region" {
  description = "GCP region for resource deployment (e.g., asia-southeast1)"
  type        = string
  default     = "asia-southeast1"
}

variable "zone" {
  description = "GCP zone for the Compute Engine instance (e.g., asia-southeast1-b)"
  type        = string
  default     = "asia-southeast1-b"
}

# =============================================================================
# Instance Configuration
# =============================================================================

variable "instance_name" {
  description = "Name for the Compute Engine instance"
  type        = string
  default     = "autoshutdown-vm"
}

variable "machine_type" {
  description = "Machine type for the instance (e.g., e2-medium, e2-standard-2, n2-standard-2)"
  type        = string
  default     = "e2-medium"
}

variable "boot_disk_size_gb" {
  description = "Size of the boot disk in GB (10-65536)"
  type        = number
  default     = 30

  validation {
    condition     = var.boot_disk_size_gb >= 10 && var.boot_disk_size_gb <= 65536
    error_message = "Boot disk size must be between 10 and 65536 GB."
  }
}

variable "boot_disk_type" {
  description = "Boot disk type (pd-standard, pd-balanced, pd-ssd)"
  type        = string
  default     = "pd-balanced"

  validation {
    condition     = contains(["pd-standard", "pd-balanced", "pd-ssd"], var.boot_disk_type)
    error_message = "Boot disk type must be one of: pd-standard, pd-balanced, pd-ssd."
  }
}

variable "image_family" {
  description = "OS image family for the boot disk"
  type        = string
  default     = "ubuntu-2404-lts-amd64"
}

variable "image_project" {
  description = "Project hosting the OS image"
  type        = string
  default     = "ubuntu-os-cloud"
}

# =============================================================================
# Network Configuration
# =============================================================================

variable "create_vpc" {
  description = "Whether to create a new VPC network or use an existing one"
  type        = bool
  default     = true
}

variable "network_name" {
  description = "Name of the VPC network (created or existing)"
  type        = string
  default     = "autoshutdown-vpc"
}

variable "subnet_name" {
  description = "Name for the subnet"
  type        = string
  default     = "autoshutdown-subnet"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allow_ssh_cidrs" {
  description = "CIDR ranges allowed to SSH into the instance (restrict in production)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# =============================================================================
# Autoshutdown Configuration
# =============================================================================

variable "cpu_threshold" {
  description = "CPU utilization threshold (fraction 0.0-1.0) below which instance is considered idle"
  type        = number
  default     = 0.05

  validation {
    condition     = var.cpu_threshold > 0 && var.cpu_threshold < 1
    error_message = "CPU threshold must be between 0.0 and 1.0 (exclusive)."
  }
}

variable "cpu_idle_duration_seconds" {
  description = "Duration in seconds that CPU must remain below threshold before triggering stop (must be multiple of 60)"
  type        = number
  default     = 900

  validation {
    condition     = var.cpu_idle_duration_seconds >= 60 && var.cpu_idle_duration_seconds % 60 == 0
    error_message = "CPU idle duration must be at least 60 seconds and a multiple of 60."
  }
}

variable "cpu_alignment_period_seconds" {
  description = "Alignment period for CPU metric aggregation in seconds (must be multiple of 60)"
  type        = number
  default     = 300

  validation {
    condition     = var.cpu_alignment_period_seconds >= 60 && var.cpu_alignment_period_seconds % 60 == 0
    error_message = "Alignment period must be at least 60 seconds and a multiple of 60."
  }
}

variable "ssh_idle_check_interval_minutes" {
  description = "How often to check for SSH inactivity (minutes)"
  type        = number
  default     = 5
}

variable "ssh_idle_threshold_checks" {
  description = "Number of consecutive idle checks before shutdown"
  type        = number
  default     = 2
}

variable "ssh_boot_grace_period_minutes" {
  description = "Grace period after boot before starting idle checks (minutes)"
  type        = number
  default     = 10
}

# =============================================================================
# Labels
# =============================================================================

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    environment = "dev"
    managed_by  = "terraform"
    purpose     = "autoshutdown-vm"
  }
}
