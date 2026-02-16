# Google Cloud Terraform Templates

Google Cloud infrastructure templates using Terraform (HCL).

## Templates

### [compute-autoshutdown](./compute-autoshutdown)

Compute Engine instance with automatic shutdown on inactivity (Cloud Monitoring alert + SSH session detection).

| Property | Value |
|----------|-------|
| Instance | e2-medium |
| OS | Ubuntu 24.04 LTS |
| Region | asia-southeast1 (Singapore) |
| Storage | 30 GB pd-balanced |
| Cost | ~$34/mo (running 24/7) |

### [tpuv3-8-spot](./tpuv3-8-spot)

TPU v3-8 Spot VM with persistent disk for cost-effective ML training.

| Property | Value |
|----------|-------|
| Accelerator | TPU v3-8 (Spot) |
| Zone | europe-west4-a (Netherlands) |
| Storage | 50 GB pd-balanced |
| Cost | ~$0.88–3.52/hr (spot) vs $8.80/hr (on-demand) |

> **Note:** TPU v3-8 availability is limited to specific zones. `europe-west4-a` is one of the supported zones.

## Quick Start

```bash
cd <template-name>
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id

terraform init
terraform validate
terraform plan
terraform apply
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [Google Cloud SDK](https://cloud.google.com/sdk/install) (`gcloud auth application-default login`)
- GCP project with billing enabled

## Helper Scripts

| Script | Description |
|--------|-------------|
| `create-start-script.sh` | Generate a one-command launcher for Compute Engine instances |
| `destroy-project.sh` | Safely destroy Terraform projects with confirmation |

## License

MIT
