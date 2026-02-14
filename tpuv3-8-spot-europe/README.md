# TPU v3-8 Spot VM with Persistent Disk - Terraform Configuration

This Terraform module provisions a Google Cloud TPU v3-8 Spot VM with an attached balanced persistent disk.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform                      │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │                  Zone: europe-west4-a                    │ │
│  │                                                          │ │
│  │  ┌──────────────────────┐    ┌───────────────────────┐  │ │
│  │  │    TPU v3-8 VM       │    │  Balanced Persistent  │  │ │
│  │  │   (tpuv3-alpha)      │◄───┤       Disk            │  │ │
│  │  │                      │    │  (tpuv3-alpha-disk)   │  │ │
│  │  │  • Spot/Preemptible  │    │                       │  │ │
│  │  │  • Ubuntu 22.04 Base │    │  • 50 GB              │  │ │
│  │  │  • Secure Boot       │    │  • pd-balanced        │  │ │
│  │  └──────────────────────┘    └───────────────────────┘  │ │
│  │                                                          │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Resources Created

| Resource | Name | Description |
|----------|------|-------------|
| `google_tpu_v2_vm` | tpuv3-alpha | TPU v3-8 Spot VM instance |
| `google_compute_disk` | tpuv3-alpha-disk | 50 GB balanced persistent disk |

## Configuration Summary

### TPU Configuration
- **Name**: tpuv3-alpha
- **Zone**: europe-west4-a
- **Accelerator Type**: v3-8
- **Runtime Version**: tpu-ubuntu2204-base
- **Spot VM**: Yes (cost-effective, can be preempted)
- **Secure Boot**: Enabled

### Disk Configuration
- **Name**: tpuv3-alpha-disk
- **Zone**: europe-west4-a (same zone as TPU for attachment)
- **Type**: pd-balanced (balanced persistent disk)
- **Size**: 50 GB
- **Snapshot**: None

## Important Notes

### Zone Compatibility
⚠️ **Important**: The persistent disk must be in the **same zone** as the TPU VM for attachment. GCP does not support cross-zone disk attachments.

The original requirements specified:
- TPU zone: `europe-west4-a`
- Disk zone: `europe-west1-b`

Since these are different regions/zones, the disk has been configured to be in `europe-west4-a` to enable attachment to the TPU.

If you need the disk in `europe-west1-b`, set `attach_disk_to_tpu = false` in your variables.

### Spot VM Considerations
- Spot VMs offer significant cost savings (60-91% discount)
- Spot VMs can be preempted at any time with 30 seconds notice
- Ideal for fault-tolerant workloads, batch jobs, and training that can checkpoint

### TPU v3-8 Availability
TPU v3-8 is available in limited zones. `europe-west4-a` is one of the zones where v3-8 is available.

## Prerequisites

1. **Google Cloud Project**: A GCP project with billing enabled
2. **APIs Enabled**:
   - Compute Engine API
   - Cloud TPU API
3. **Permissions**: The user or service account needs:
   - `roles/tpu.admin` or equivalent
   - `roles/compute.instanceAdmin` or equivalent
4. **Quota**: Sufficient TPU v3 quota in the target zone

## Usage

### 1. Initialize Terraform

```bash
cd tpuv3-alpha
terraform init
```

### 2. Configure Variables

```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your project ID
nano terraform.tfvars
```

### 3. Validate Configuration

```bash
terraform validate
```

### 4. Review Execution Plan

```bash
terraform plan
```

### 5. Apply Configuration (When Ready)

```bash
terraform apply
```

## Input Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `project_id` | GCP Project ID | - | Yes |
| `region` | Default region | `europe-west4` | No |
| `tpu_name` | TPU VM name | `tpuv3-alpha` | No |
| `tpu_zone` | TPU zone | `europe-west4-a` | No |
| `tpu_accelerator_type` | TPU accelerator type | `v3-8` | No |
| `tpu_runtime_version` | TPU software version | `tpu-ubuntu2204-base` | No |
| `tpu_spot` | Use spot VM | `true` | No |
| `disk_name` | Disk name | `tpuv3-alpha-disk` | No |
| `disk_zone` | Disk zone | `europe-west4-a` | No |
| `disk_type` | Disk type | `pd-balanced` | No |
| `disk_size_gb` | Disk size in GB | `50` | No |
| `attach_disk_to_tpu` | Attach disk to TPU | `true` | No |

## Outputs

| Output | Description |
|--------|-------------|
| `tpu_id` | TPU VM unique identifier |
| `tpu_name` | TPU VM name |
| `tpu_zone` | TPU zone |
| `tpu_state` | TPU current state |
| `tpu_network_endpoints` | TPU network endpoints |
| `disk_id` | Disk unique identifier |
| `disk_self_link` | Disk self link |
| `connection_info` | Summary of TPU-disk connection |
| `available_runtime_versions` | Available TPU runtimes |
| `available_accelerator_types` | Available TPU types |

## Cost Estimation

Pricing based on the default zone **europe-west4-a (Netherlands)**.

| Resource | Pricing Model | Estimated Cost* |
|----------|---------------|--------------------|
| TPU v3-8 (On-demand) | 4 chips × $2.20/chip-hr | $8.80/hour |
| TPU v3-8 (Spot) | 60-91% off on-demand | ~$0.88-3.52/hour |
| Balanced PD (50GB) | $0.12/GB/mo | ~$6.00/month |

*Spot prices are dynamic and change based on supply/demand. Use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) for current estimates.

## Security Best Practices Implemented

- ✅ Shielded VM with Secure Boot enabled
- ✅ Resource labeling for organization and cost tracking
- ✅ Lifecycle protection configurations
- ✅ Version constraints for providers
- ✅ Input validation for critical variables

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

## Troubleshooting

### TPU Quota Issues
```
Error: Error creating Vm: googleapi: Error 403: Insufficient quota
```
Request additional TPU quota in the GCP Console under IAM & Admin → Quotas.

### TPU Runtime Version Not Found
Use the output `available_runtime_versions` to see valid versions:
```bash
terraform output available_runtime_versions
```

### Disk Attachment Fails
Ensure the disk is in the same zone as the TPU. Check that `disk_zone` matches `tpu_zone`.

## License

This configuration is provided as-is for educational and development purposes.
