# Compute Engine Auto-Shutdown

Terraform configuration that creates a Google Cloud Compute Engine instance with **dual automatic shutdown mechanisms** to prevent idle instances from accruing unnecessary costs.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│              Compute Engine Auto-Shutdown Architecture              │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────────────┐
│  VPC Network             │
│  ┌──────────────────────┐│
│  │ Subnet (10.0.1.0/24) ││
│  │ + Firewall Rules     ││
│  │   - Allow SSH        ││
│  │   - Allow IAP SSH    ││
│  └──────────────────────┘│
└──────────────────────────┘
           │
           ▼
┌──────────────────────────────────────┐
│  Compute Engine Instance (e2-small)  │
│  ┌──────────────────────────────────┐│
│  │ OS: Ubuntu 24.04 LTS             ││
│  │ Disk: 30 GB pd-balanced          ││
│  │ Shielded VM: Secure boot on      ││
│  │ OS Login: Enabled                ││
│  └──────────────────────────────────┘│
│  ┌──────────────────────────────────┐│
│  │ DUAL AUTO-SHUTDOWN MECHANISMS:   ││
│  │                                  ││
│  │ ┌─ Primary ──────────────────┐   ││
│  │ │ Cloud Monitoring Alert     │   ││
│  │ │ → Pub/Sub → Cloud Function │   ││
│  │ │ (stops instance via API)   │   ││
│  │ └────────────────────────────┘   ││
│  │ ┌─ Secondary ────────────────┐   ││
│  │ │ Systemd Timer (Internal)   │   ││
│  │ │ → Monitors SSH sessions    │   ││
│  │ │ → Executes shutdown cmd    │   ││
│  │ └────────────────────────────┘   ││
│  └──────────────────────────────────┘│
└──────────────────────────────────────┘
           │                    │
     ┌─────▼──────┐      ┌─────▼────────────┐
     │  Cloud     │      │  Systemd Timer   │
     │ Monitoring │      │  (every 5 min)   │
     │ CPU < 5%   │      │                  │
     │ for 15 min │      │  check-ssh-      │
     └─────┬──────┘      │  idle.sh         │
           │             └──────┬───────────┘
           ▼                    │
     ┌───────────┐              │
     │  Pub/Sub  │              │
     │  Topic    │              ▼
     └─────┬─────┘        ┌────────────┐
           │              │  shutdown  │
           ▼              │  -h now    │
     ┌───────────────┐    └────────────┘
     │ Cloud Function│
     │ (stops via    │
     │  Compute API) │
     └───────────────┘
```

## Service Mapping (AWS → GCP)

| AWS Service | GCP Equivalent | Purpose |
|---|---|---|
| EC2 Instance | Compute Engine Instance | Virtual machine |
| VPC + Security Groups | VPC Network + Firewall Rules | Networking |
| CloudWatch Alarm + EC2 Stop Action | Cloud Monitoring Alert + Pub/Sub + Cloud Function | CPU-based idle detection |
| IAM Role | Service Account | Instance identity |
| Systems Manager (SSH keys) | OS Login | SSH access management |
| User Data Script | Startup Script | Instance initialization |
| EBS (gp3) | Persistent Disk (pd-balanced) | Block storage |
| CDK (TypeScript) | Terraform (HCL) | Infrastructure as Code |

## Auto-Shutdown Mechanisms

### Primary: Cloud Monitoring Alert → Cloud Function (CPU-Based)

| Parameter | Value |
|---|---|
| Metric | `compute.googleapis.com/instance/cpu/utilization` |
| Threshold | < 5% average CPU |
| Alignment Period | 5 minutes |
| Duration | 15 minutes (900s) |
| Action | Cloud Function stops instance via Compute API |

**How it works:**
1. Cloud Monitoring continuously evaluates CPU utilization
2. When average CPU stays below 5% for 15 minutes, the alert fires
3. Alert publishes a message to a Pub/Sub topic
4. Cloud Function (2nd gen) is triggered by the Pub/Sub message
5. Cloud Function verifies the incident is "open", then calls `instances.stop()` using the instance name from its environment variables

> **Design note:** The Cloud Monitoring alert payload provides a numeric `instance_id`
> in `resource.labels`, but the Compute Engine API `instances.stop()` requires the
> instance **name**. To avoid unreliable name resolution at runtime, the target instance
> name is passed to the Cloud Function via environment variables at deploy time.

### Secondary: SSH Session Detection (Startup Script)

| Parameter | Value |
|---|---|
| Check Interval | Every 5 minutes |
| Idle Threshold | 2 consecutive checks |
| Total Idle Timeout | 10 minutes |
| Boot Grace Period | 10 minutes |
| Log File | `/var/log/autoshutdown.log` |

**Activity checks performed:**
1. Active SSH sessions (`who | grep pts/`)
2. SSHD child processes (IAP tunnel / gcloud SSH)
3. Screen/tmux sessions
4. CPU utilization (> 10% = active)
5. Memory usage (> 80% = active)

## Prerequisites

### Required APIs

The following APIs are automatically enabled by Terraform:

- Compute Engine API (`compute.googleapis.com`)
- Cloud Functions API (`cloudfunctions.googleapis.com`)
- Cloud Build API (`cloudbuild.googleapis.com`)
- Cloud Run API (`run.googleapis.com`)
- Eventarc API (`eventarc.googleapis.com`)
- Cloud Monitoring API (`monitoring.googleapis.com`)
- Pub/Sub API (`pubsub.googleapis.com`)

### Required IAM Permissions

The user running Terraform needs:

- `roles/compute.admin` - Create/manage instances, networks, firewalls
- `roles/iam.serviceAccountAdmin` - Create service accounts
- `roles/iam.serviceAccountUser` - Attach service accounts to instances
- `roles/pubsub.admin` - Create Pub/Sub topics
- `roles/monitoring.admin` - Create alert policies and notification channels
- `roles/cloudfunctions.admin` - Deploy Cloud Functions
- `roles/storage.admin` - Create GCS bucket for function source
- `roles/resourcemanager.projectIamAdmin` - Grant IAM bindings
- `roles/serviceusage.serviceUsageAdmin` - Enable APIs

### Tools

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [Google Cloud SDK](https://cloud.google.com/sdk/install) (for `gcloud auth`)
- A GCP project with billing enabled

## Usage

### 1. Authenticate

```bash
gcloud auth application-default login
```

### 2. Configure

```bash
cd compute-autoshutdown
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id and preferences
```

### 3. Deploy

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

### 4. Connect

```bash
# SSH via gcloud (recommended)
gcloud compute ssh <instance-name> --zone=<zone> --project=<project-id>

# SSH via IAP tunnel (no public IP needed)
gcloud compute ssh <instance-name> --zone=<zone> --project=<project-id> --tunnel-through-iap
```

### 5. Monitor

```bash
# Check auto-shutdown log on the instance
gcloud compute ssh <instance-name> --zone=<zone> --command='cat /var/log/autoshutdown.log'

# Check Cloud Monitoring alert status
gcloud alpha monitoring policies list --project=<project-id>

# Check Cloud Function logs
gcloud functions logs read stop-idle-instance-<suffix> --region=<region> --gen2
```

### 6. Restart After Auto-Shutdown

```bash
gcloud compute instances start <instance-name> --zone=<zone> --project=<project-id>
```

## Inputs

| Variable | Description | Default |
|---|---|---|
| `project_id` | GCP project ID | (required) |
| `region` | GCP region | `asia-southeast1` |
| `zone` | GCP zone | `asia-southeast1-b` |
| `instance_name` | Instance name | `autoshutdown-vm` |
| `machine_type` | Machine type | `e2-small` |
| `boot_disk_size_gb` | Boot disk size (GB) | `30` |
| `boot_disk_type` | Boot disk type | `pd-balanced` |
| `image_family` | OS image family | `ubuntu-2404-lts-amd64` |
| `image_project` | Image source project | `ubuntu-os-cloud` |
| `create_vpc` | Create new VPC | `true` |
| `network_name` | VPC name | `autoshutdown-vpc` |
| `subnet_name` | Subnet name | `autoshutdown-subnet` |
| `subnet_cidr` | Subnet CIDR | `10.0.1.0/24` |
| `allow_ssh_cidrs` | SSH allowed CIDRs | `["0.0.0.0/0"]` |
| `cpu_threshold` | CPU idle threshold (fraction) | `0.05` (5%) |
| `cpu_idle_duration_seconds` | CPU idle duration before stop | `900` (15 min) |
| `cpu_alignment_period_seconds` | Metric alignment period | `300` (5 min) |
| `ssh_idle_check_interval_minutes` | SSH check interval | `5` |
| `ssh_idle_threshold_checks` | Consecutive idle checks before shutdown | `2` |
| `ssh_boot_grace_period_minutes` | Grace period after boot | `10` |
| `labels` | Resource labels | `{environment="dev", ...}` |

## Outputs

| Output | Description |
|---|---|
| `instance_id` | Compute Engine instance ID |
| `instance_name` | Instance name |
| `instance_external_ip` | External IP address |
| `ssh_command` | gcloud SSH command |
| `iap_ssh_command` | gcloud SSH via IAP command |
| `start_instance_command` | Command to restart after shutdown |
| `check_autoshutdown_log_command` | Command to view shutdown logs |
| `alert_policy_name` | Cloud Monitoring alert policy |
| `cloud_function_name` | Cloud Function name |
| `autoshutdown_config` | Summary of shutdown configuration |

## Cost Estimate

Pricing based on the default region **asia-southeast1 (Singapore)**.

| Resource | Approximate Monthly Cost |
|---|---|
| e2-small instance (730 hrs × $0.0207/hr) | ~$15.11 |
| 30 GB pd-balanced disk ($0.11/GB/mo) | ~$3.30 |
| Cloud Function (idle alert only) | ~$0.00 (free tier) |
| Cloud Monitoring | ~$0.00 (included) |
| Pub/Sub | ~$0.00 (free tier) |
| VPC + Firewall | ~$0.00 (no charge) |
| **Total (running 24/7)** | **~$18.41/mo** |

With auto-shutdown, actual costs will be significantly lower based on usage. Prices vary by region — use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for other regions.

## Cleanup

```bash
terraform destroy
```

## Troubleshooting

### Instance shuts down too quickly
- Increase `ssh_idle_threshold_checks` or `ssh_idle_check_interval_minutes`
- Increase `cpu_idle_duration_seconds`
- Check `/var/log/autoshutdown.log` for what triggered the shutdown

### Instance doesn't shut down
- Verify Cloud Monitoring alert is firing: check the alert policy in Cloud Console
- Check Cloud Function logs for errors
- SSH into the instance and check `systemctl status autoshutdown.timer`
- Verify the startup script ran: `cat /var/log/autoshutdown.log`

### Cloud Function fails to stop instance
- Check the Cloud Function service account has `roles/compute.instanceAdmin.v1`
- Check Cloud Function logs: `gcloud functions logs read <fn-name> --region=<region> --gen2`
- Verify the Pub/Sub topic is receiving messages

### Can't SSH into the instance
- Ensure OS Login is enabled (it is by default)
- Grant yourself `roles/compute.osLogin` on the project
- For IAP: ensure `roles/iap.tunnelResourceAccessor` is granted
- Check firewall rules allow SSH from your IP
