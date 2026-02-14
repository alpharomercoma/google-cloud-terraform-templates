# Google Cloud Terraform Templates

Collection of Google Cloud infrastructure templates using Terraform (HCL).

---

## Available Templates

### [compute-autoshutdown](./compute-autoshutdown)
Compute Engine instance with **dual automatic shutdown mechanisms** — Cloud Monitoring alert (CPU-based) and systemd timer (SSH session detection) — to prevent idle instances from accruing costs.

- **Instance:** e2-small · Ubuntu 24.04 LTS · 30 GB pd-balanced
- **Region:** asia-southeast1 (Singapore)
- **Shutdown:** CPU < 5% for 15 min (Cloud Function) + no SSH for 10 min (systemd)
- **Cost:** ~$18.41/mo (running 24/7) — significantly less with auto-shutdown

### [tpuv3-8-spot-europe](./tpuv3-8-spot-europe)
TPU v3-8 Spot VM with attached persistent disk for cost-effective ML training workloads in Europe.

- **Accelerator:** TPU v3-8 (4 chips, 8 TensorCores) · Spot/Preemptible
- **Zone:** europe-west4-a (Netherlands) — one of the limited zones with v3-8 availability
- **Storage:** 50 GB pd-balanced attached disk
- **Cost:** ~$0.88-3.52/hr (spot) vs $8.80/hr (on-demand) + ~$6.00/mo disk

---

## Quick Start

```bash
# Navigate to template
cd <template-name>

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id and preferences

# Deploy
terraform init
terraform validate
terraform plan
terraform apply

# Destroy when done
terraform destroy
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) >= 1.5.0
- [Google Cloud SDK](https://cloud.google.com/sdk/install) (`gcloud` CLI)
- A GCP project with billing enabled
- Appropriate IAM permissions (see each template's README)

## Authentication

```bash
# Option 1: Application Default Credentials (recommended)
gcloud auth application-default login

# Option 2: Service Account Key
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"

# Option 3: gcloud CLI auth
gcloud auth login
```

## Documentation

Each Terraform template has its own README with architecture diagrams, input variables, outputs, cost estimates, and troubleshooting guides.

---

## Related: AWS CDK Templates

The [aws-cdk-templates](./aws-cdk-templates) directory contains the predecessor project — a collection of AWS CDK (TypeScript) infrastructure templates with equivalent management utilities. See its [README](./aws-cdk-templates/README.md) for details.

| | AWS CDK Templates | Google Cloud Terraform Templates |
|---|---|---|
| **IaC Tool** | AWS CDK (TypeScript) | Terraform (HCL) |
| **Cloud Provider** | AWS | Google Cloud |
| **Package Manager** | npm / pnpm | N/A (Terraform providers) |
| **Deploy Command** | `npx cdk deploy` | `terraform apply` |
| **Destroy Command** | `npx cdk destroy` | `terraform destroy` |

## License

MIT
