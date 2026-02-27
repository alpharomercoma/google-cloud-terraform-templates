# TPU v4-8 On-Demand VM

TPU v4-8 on-demand VM with persistent disk for ML training.

## Specifications

| Property | Value |
|----------|-------|
| Accelerator | TPU v4-8 (4 chips, 8 TensorCores) |
| Pricing | On-Demand (non-spot, non-preemptible) |
| Runtime | tpu-ubuntu2204-base |
| Zone | us-central2-b (Iowa) |
| Storage | 50 GB pd-balanced |
| Shielded VM | Secure boot enabled |

> **Note:** TPU v4 is available in `us-central2-b` and limited other zones. Check [supported configurations](https://cloud.google.com/tpu/docs/supported-tpu-configurations) for availability.

## Architecture

```
Zone: us-central2-b
├── TPU v4-8 VM (On-Demand)
│   ├── Ubuntu 22.04 base
│   └── Secure Boot enabled
└── Persistent Disk (50 GB pd-balanced)
```

## Deploy

```bash
cd tpuv4-8-ondemand
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project_id

terraform init
terraform validate
terraform plan
terraform apply
```

## Inputs

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | GCP project ID | (required) |
| `tpu_zone` | TPU zone | `us-central2-b` |
| `tpu_accelerator_type` | Accelerator type | `v4-8` |
| `tpu_spot` | Use spot pricing | `false` |
| `tpu_preemptible` | Use preemptible pricing | `false` |
| `disk_size_gb` | Disk size (GB) | `50` |
| `attach_disk_to_tpu` | Attach disk to TPU | `true` |
| `enable_external_ips` | Assign public IPs to TPU workers | `true` |

> **Important:** The persistent disk must be in the same zone as the TPU VM.

## Cost Estimate

| Resource | Price |
|----------|-------|
| TPU v4-8 (4 chips, on-demand) | ~$13/hr |
| 50 GB pd-balanced | $6.00/mo |

On-demand pricing guarantees availability but is billed continuously while the VM is running. Check the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for current estimates.

## Provider Note

This module uses `google_tpu_v2_vm` (via `google-beta`). The alternative `google_tpu_v2_queued_resource` resource is incomplete in the current Terraform provider — it is missing `scheduling_config`, `data_disks`, `shielded_instance_config`, `labels`, `tags`, `metadata`, and the `guaranteed`/`spot` queuing blocks. `google_tpu_v2_vm` has full schema support for all of these.

## Cleanup

```bash
terraform destroy
```
