# =============================================================================
# Compute Engine Auto-Shutdown Stack
# =============================================================================
#
# Creates a Compute Engine instance with dual auto-shutdown mechanisms:
#
# 1. Cloud Monitoring Alert (Primary):
#    - Monitors CPU utilization via compute.googleapis.com/instance/cpu/utilization
#    - Triggers Pub/Sub → Cloud Function to stop instance when CPU < 5% for 15 min
#
# 2. SSH Session Detection (Secondary):
#    - Startup script installs systemd timer checking for active SSH sessions
#    - Shuts down after 2 consecutive 5-minute checks with no activity (10 min)
#
# =============================================================================

locals {
  common_labels = merge(var.labels, {
    project_id   = var.project_id
    autoshutdown = "enabled"
  })

  # SSH idle detection total timeout in minutes
  ssh_idle_timeout_minutes = var.ssh_idle_check_interval_minutes * var.ssh_idle_threshold_checks
}

# =============================================================================
# Random suffix for globally unique resource names
# =============================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

# =============================================================================
# VPC Network
# =============================================================================

resource "google_compute_network" "vpc" {
  count = var.create_vpc ? 1 : 0

  name                    = "${var.network_name}-${random_id.suffix.hex}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "subnet" {
  count = var.create_vpc ? 1 : 0

  name          = "${var.subnet_name}-${random_id.suffix.hex}"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc[0].id

  private_ip_google_access = true
}

# =============================================================================
# Firewall Rules
# =============================================================================

resource "google_compute_firewall" "allow_ssh" {
  count = var.create_vpc ? 1 : 0

  name    = "allow-ssh-${random_id.suffix.hex}"
  network = google_compute_network.vpc[0].id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allow_ssh_cidrs
  target_tags   = ["autoshutdown-vm"]
}

resource "google_compute_firewall" "allow_iap_ssh" {
  count = var.create_vpc ? 1 : 0

  name    = "allow-iap-ssh-${random_id.suffix.hex}"
  network = google_compute_network.vpc[0].id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP's IP range for TCP forwarding
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["autoshutdown-vm"]
}

resource "google_compute_firewall" "allow_egress" {
  count = var.create_vpc ? 1 : 0

  name      = "allow-egress-${random_id.suffix.hex}"
  network   = google_compute_network.vpc[0].id
  direction = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
}

# =============================================================================
# Service Account
# =============================================================================

resource "google_service_account" "instance_sa" {
  account_id   = "autoshutdown-vm-${random_id.suffix.hex}"
  display_name = "Autoshutdown VM Service Account"
  description  = "Service account for the auto-shutdown Compute Engine instance"
}

# Allow the instance to write logs and metrics
resource "google_project_iam_member" "instance_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.instance_sa.email}"
}

resource "google_project_iam_member" "instance_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.instance_sa.email}"
}

# =============================================================================
# Compute Engine Instance
# =============================================================================

resource "google_compute_instance" "vm" {
  name         = "${var.instance_name}-${random_id.suffix.hex}"
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["autoshutdown-vm"]
  labels = local.common_labels

  boot_disk {
    initialize_params {
      image = "${var.image_project}/${var.image_family}"
      size  = var.boot_disk_size_gb
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = var.create_vpc ? google_compute_subnetwork.subnet[0].id : var.subnet_name

    access_config {
      # Ephemeral public IP
    }
  }

  service_account {
    email  = google_service_account.instance_sa.email
    scopes = ["cloud-platform"]
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  shielded_instance_config {
    enable_secure_boot = true
  }

  # =========================================================================
  # Startup Script - SSH Inactivity Auto-Shutdown (Secondary Mechanism)
  # =========================================================================
  metadata_startup_script = templatefile("${path.module}/startup-script.sh", {
    idle_threshold       = var.ssh_idle_threshold_checks
    check_interval_min   = var.ssh_idle_check_interval_minutes
    boot_grace_period    = var.ssh_boot_grace_period_minutes
    idle_timeout_minutes = local.ssh_idle_timeout_minutes
  })

  metadata = {
    enable-oslogin = "TRUE"
  }

  depends_on = [
    google_project_service.compute,
    google_compute_firewall.allow_ssh,
    google_compute_firewall.allow_iap_ssh,
  ]

  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }
}
