# Compute Engine Auto-Shutdown

Compute Engine instance with automatic shutdown on inactivity detection.

## Specifications

| Property | Value |
|----------|-------|
| Machine Type | e2-medium |
| OS | Ubuntu 24.04 LTS |
| Region | asia-southeast1 (Singapore) |
| Storage | 30 GB pd-balanced |
| Shielded VM | Secure boot enabled |

## Auto-Shutdown

### Cloud Monitoring Alert (Primary)

Monitors CPU utilization. When average CPU stays below 5% for 15 minutes, the alert fires → Pub/Sub → Cloud Function stops the instance via Compute API.

### SSH Session Detection (Secondary)

Systemd timer runs every 5 minutes checking for activity: SSH sessions, SSHD processes, screen/tmux, CPU > 10%, memory > 80%. Shuts down after 2 consecutive idle checks (10 minutes). 10-minute boot grace period.

## Architecture

```
Compute Engine Instance (e2-medium)
├── Cloud Monitoring Alert (CPU < 5%, 15 min)
│   └── Pub/Sub → Cloud Function → instances.stop()
└── Systemd Timer (SSH/activity idle, 10 min) → shutdown -h now
```

## Deploy

```bash
cd compute-autoshutdown
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id

terraform init
terraform validate
terraform plan
terraform apply
```

## Connect

```bash
# SSH via gcloud
gcloud compute ssh <instance-name> --zone=<zone> --project=<project-id>

# SSH via IAP tunnel (no public IP needed)
gcloud compute ssh <instance-name> --zone=<zone> --project=<project-id> --tunnel-through-iap
```

## Restart After Shutdown

```bash
gcloud compute instances start <instance-name> --zone=<zone> --project=<project-id>
```

## Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP project ID | (required) |
| `region` | GCP region | `asia-southeast1` |
| `zone` | GCP zone | `asia-southeast1-b` |
| `instance_name` | Instance name | `autoshutdown-vm` |
| `machine_type` | Machine type | `e2-medium` |
| `boot_disk_size_gb` | Boot disk size (GB) | `30` |

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| e2-medium (730 hrs) | ~$30.59 |
| 30 GB pd-balanced | ~$3.30 |
| Cloud Function / Pub/Sub | ~$0.00 (free tier) |
| **Total (24/7)** | **~$34** |

With auto-shutdown, actual costs depend on usage.

## Cleanup

```bash
terraform destroy
```
