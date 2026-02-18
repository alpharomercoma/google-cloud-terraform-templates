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

Monitors a multi-signal idle profile. Alert fires only when all conditions remain true for 15 minutes:
- CPU utilization below 5%
- Network ingress below 20 KB/s
- Network egress below 20 KB/s
- Disk read throughput below 10 KB/s
- Disk write throughput below 10 KB/s

Alert flow: Monitoring policy → Pub/Sub → Cloud Function → `instances.stop()`.

### In-VM Multi-Signal Detection (Secondary)

Systemd timer runs every 5 minutes checking:
- Session activity (`who`, `sshd`, `screen`/`tmux`)
- CPU busy percentage
- Combined network throughput (RX+TX)
- Combined disk I/O (IOPS + throughput)

Shutdown quorum requires:
- session signals idle **and**
- at least `2 of 3` workload-idle signals (`CPU`, `Network`, `Disk`)
- for 2 consecutive checks (10 minutes), after a 10-minute boot grace period

## Architecture

```
Compute Engine Instance (e2-medium)
├── Cloud Monitoring Alert (CPU + Network + Disk idle, 15 min)
│   └── Pub/Sub → Cloud Function → instances.stop()
└── Systemd Timer (session idle + workload quorum, 10 min) → shutdown -h now
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
| `allow_ssh_cidrs` | Optional direct SSH CIDRs | `[]` (disabled) |

Direct SSH ingress is disabled by default. Use IAP (`--tunnel-through-iap`) or set `allow_ssh_cidrs` explicitly.

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
