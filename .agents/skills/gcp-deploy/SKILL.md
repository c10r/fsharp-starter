---
name: gcp-deploy
description: Use when deploying the starter to Google Compute Engine with Docker Compose and OpenTofu.
---

# Skill: gcp-deploy

Use this when deploying the starter to Google Compute Engine.

## Source Summary
This skill summarizes:
- `docker-compose.gce.yml`
- `infra/opentofu/*`

## Runtime Topology (docker-compose.gce)
- `fsharp-starter-api`: ASP.NET API container, mounts persistent sqlite data at `/app/data`.

## Data/Secrets Expectations
- App data root default: `${FSHARP_STARTER_DATA_ROOT:-/mnt/fsharp-starter-data}`.
- SQLite DB file under mounted `/app/data`.

## OpenTofu Summary
Main files:
- `infra/opentofu/main.tf`: VM, firewall, startup template wiring.
- `infra/opentofu/variables.tf`: project/region/zone/network/image/instance parameters.
- `infra/opentofu/providers.tf` and `versions.tf`: provider and version pins.
- `infra/opentofu/templates/startup.sh.tmpl`: bootstrap script installing Docker/Compose and running deployment.
- `infra/opentofu/outputs.tf`: exported deployment values.

## Deployment Flow
1. Configure `terraform.tfvars` from `environments/dev/terraform.tfvars.example`.
2. `tofu init`.
3. `tofu plan`.
4. `tofu apply`.
5. Verify VM startup script deployed Compose stack and health checks.

## Hardening Rules
- Treat deploy scripts and infra templates as production code (strict shell mode, robust auth paths, explicit compatibility checks).
- Avoid brittle inline token expansion in templated shell/systemd snippets; isolate auth logic in dedicated scripts.
- Handle environment variance explicitly (Compose v1/v2 behavior, IAP tunnel flags, image tag policy like `latest`).
- When changing startup/deploy auth flows, validate in a realistic VM path, not only local shell execution.

## Verification Commands
After infra edits:
1. `cd infra/opentofu && tofu fmt -recursive`
2. `cd infra/opentofu && tofu validate`
3. `docker compose -f docker-compose.gce.yml config`
