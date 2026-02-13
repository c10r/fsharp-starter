---
name: iac
description: Design and update cost-conscious GCP OpenTofu infrastructure for VM/MIG deployments with HTTPS load balancing and optional blue-green rollout. Use when editing `infra/opentofu` files (for example `main.tf`, `variables.tf`, startup templates, or tfvars) and enforce persistent-disk safety so blue-green deploys and teardown actions never delete application data.
---

# IaC

## Overview

Apply a standardized OpenTofu pattern for GCP compute, load balancing, and rollout safety. Keep infrastructure generic (no product-specific names) and preserve persistent disk data across upgrades, blue-green transitions, and destroy attempts.

## Baseline Defaults

Use these cost-focused defaults unless the user requests otherwise:
- `machine_type = "e2-micro"`
- `boot_disk_size_gb = 10`
- `data_disk_size_gb = 1`
- `data_disk_type = "pd-balanced"`
- `preserve_data_disk_on_destroy = true`

## Workflow

1. Inspect `infra/opentofu/main.tf`, `infra/opentofu/variables.tf`, `infra/opentofu/outputs.tf`, and `infra/opentofu/templates/*.tmpl`.
2. Implement a generic topology:
- VPC/subnet
- VM service account + IAM for registry/logging/secrets
- one persistent data disk attached with `auto_delete = false`
- primary MIG behind HTTPS load balancer
- optional blue-green single VM + unmanaged instance group as alternate backend
3. Enforce persistent-disk guardrails:
- Keep `google_compute_disk` in a protected resource with `lifecycle { prevent_destroy = true }`.
- Model a protected/unprotected disk pair, then select active disk self-link via a local expression.
- Validate blue-green settings so unsafe combinations fail at plan time.
4. Apply variable validation to block unsafe rollouts:
- Require `primary_mig_target_size == 0` when blue-green is enabled.
- Require `primary_backend_capacity == 0` when blue-green is enabled.
- Require `preserve_data_disk_on_destroy == true` when blue-green is enabled.
5. Run infra checks:
- `tofu fmt -recursive`
- `tofu validate`
- `tofu plan -out=tfplan`
- `tofu show -json tfplan > /tmp/tfplan.json`
- `python3 agents/skills/iac/scripts/check_no_disk_delete.py /tmp/tfplan.json`

## Blue-Green Safety Pattern

Use this validation shape in `variables.tf`:

```hcl
variable "bluegreen_enabled" {
  type    = bool
  default = false

  validation {
    condition = !var.bluegreen_enabled || (
      var.primary_mig_target_size == 0
      && var.primary_backend_capacity == 0
      && var.preserve_data_disk_on_destroy
    )
    error_message = "When bluegreen_enabled=true, primary_mig_target_size and primary_backend_capacity must be 0, and preserve_data_disk_on_destroy must be true."
  }
}
```

Use a protected disk by default:

```hcl
resource "google_compute_disk" "data_protected" {
  count = var.preserve_data_disk_on_destroy ? 1 : 0

  name = local.data_disk_name
  type = var.data_disk_type
  zone = var.zone
  size = var.data_disk_size_gb

  lifecycle {
    prevent_destroy = true
  }
}
```

## Naming Guidance

Generalize all names:
- Prefer `app`, `service`, or `${var.name_prefix}` instead of copied product names.
- Keep stable resource keys (`primary`, `bluegreen`, `data_protected`) so plans remain predictable.

## Resources

- Use `references/gcp-opentofu-bluegreen.md` for a complete generic resource map and backend switching pattern.
- Use `scripts/check_no_disk_delete.py` to fail plans that attempt to delete/replace persistent disks.
