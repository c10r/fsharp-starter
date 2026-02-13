# GCP OpenTofu Blue-Green Reference

## Intent

Reuse the proven deployment approach from `freetool/infra/opentofu` while keeping names product-neutral and preserving data safety.

## Topology

- Primary runtime: `google_compute_instance_template` + `google_compute_instance_group_manager`.
- Optional green runtime: single `google_compute_instance` + unmanaged `google_compute_instance_group`.
- Traffic control: one `google_compute_backend_service` with:
  - primary MIG backend (`capacity_scaler = var.primary_backend_capacity`)
  - dynamic green backend only when `bluegreen_enabled` (`capacity_scaler = var.bluegreen_backend_capacity`)
- Front door: managed SSL certificate, HTTPS proxy, HTTP redirect, global forwarding rules.

## Persistent Disk Guardrail Model

1. Define two data disk resources:
- `google_compute_disk.data_protected` with `prevent_destroy = true`
- `google_compute_disk.data_unprotected` for explicit temporary override scenarios
2. Choose active disk via local:
- `local.data_disk_self_link = var.preserve_data_disk_on_destroy ? google_compute_disk.data_protected[0].self_link : google_compute_disk.data_unprotected[0].self_link`
3. Attach disk to all compute paths:
- primary template disk block
- blue-green instance attached disk block
4. Always set `auto_delete = false` for attached data disks.

## Validation Contract

Ensure these are enforced in `variables.tf`:

- `bluegreen_enabled=true` requires `primary_mig_target_size == 0`
- `bluegreen_enabled=true` requires `primary_backend_capacity == 0`
- `bluegreen_enabled=true` requires `preserve_data_disk_on_destroy == true`
- `primary_backend_capacity` and `bluegreen_backend_capacity` each stay in `[0, 1]`
- `primary_mig_target_size >= 0`

This blocks plans that could route traffic to both old and new writers on the same disk or allow accidental disk destroy during cutover.

## Cost Defaults

Set these starter defaults in `variables.tf` or `environments/*/terraform.tfvars.example`:

- `machine_type = "e2-micro"`
- `boot_disk_size_gb = 10`
- `data_disk_size_gb = 1`

## Template and Startup Script Notes

- Keep startup script idempotent.
- Wait for persistent disk device, format only when unformatted, add UUID-based `/etc/fstab` entry, mount before starting containers.
- Put registry login in a dedicated script invoked by systemd `ExecStartPre`.
- Support Docker Compose v2 with v1 fallback in bootstrap logic.

## Plan Validation Commands

```bash
cd infra/opentofu
tofu fmt -recursive
tofu validate
tofu plan -out=tfplan
tofu show -json tfplan > /tmp/tfplan.json
python3 ../../agents/skills/iac/scripts/check_no_disk_delete.py /tmp/tfplan.json
```
