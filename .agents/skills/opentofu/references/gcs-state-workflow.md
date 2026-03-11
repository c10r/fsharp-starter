# GCS State Workflow

Use this reference when the task requires exact commands for pulling, rehearsing, restoring, or promoting OpenTofu state.

## Object Paths

- App:
  `BUCKET=iac-state-fsharp-starter`
  `OBJECT=fsharp-starter/dev/default.tfstate`
  `STACK_DIR=infra/opentofu`
  `TFVARS_TEMPLATE=infra/opentofu/environments/dev/terraform.tfvars.example`
- Foundation:
  `BUCKET=iac-state-fsharp-starter`
  `OBJECT=fsharp-starter/foundation/default.tfstate`
  `STACK_DIR=infra/foundation/opentofu`
  `TFVARS_TEMPLATE=infra/foundation/opentofu/terraform.tfvars.example`

For derived projects, keep the same pattern and substitute the project slug in both `BUCKET` and `OBJECT`.

## Pull the Current Remote State

Describe the live object and capture its generation:

```bash
gcloud storage objects describe "gs://$BUCKET/$OBJECT" \
  --format='json(name,generation,metageneration,storage_url,update_time,size)'
```

List all historical versions when you need rollback context:

```bash
gcloud storage ls --all-versions "gs://$BUCKET/$OBJECT"
```

Download the live state and keep an immutable backup named with the remote generation:

```bash
WORKDIR="/tmp/opentofu-$(basename "$OBJECT" .tfstate)-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WORKDIR"

REMOTE_GENERATION="$(gcloud storage objects describe "gs://$BUCKET/$OBJECT" --format='value(generation)')"

gcloud storage cp \
  "gs://$BUCKET/$OBJECT#$REMOTE_GENERATION" \
  "$WORKDIR/remote-original.$REMOTE_GENERATION.tfstate"

cp "$WORKDIR/remote-original.$REMOTE_GENERATION.tfstate" "$WORKDIR/terraform.tfstate"
```

## Build a Scratch Local Loop

Copy the stack into a scratch directory and seed it with the downloaded state:

```bash
cp -R "$STACK_DIR"/. "$WORKDIR/"
cp "$TFVARS_TEMPLATE" "$WORKDIR/terraform.tfvars"
```

Reconstruct `terraform.tfvars` from the example plus the downloaded state payload:

```bash
jq '.outputs | with_entries(.value = .value.value)' "$WORKDIR/terraform.tfstate"
```

Useful app values visible in current state outputs include:
- `project_id`
- `artifact_registry_location`
- `artifact_registry_repo_id`
- `artifact_registry_repo`
- `data_mount_path`
- `iap_jwt_audience`
- `validate_iap_jwt`
- `google_directory_*`

Useful foundation values visible in current state outputs include:
- `project_id`
- `terraform_state_bucket_name`
- `github_deploy_service_account_email`
- `github_workload_identity_provider_name`
- `github_repository_name`

Then run the local-only loop:

```bash
cd "$WORKDIR"
tofu init -backend=false
tofu plan
tofu apply
```

Use the local `terraform.tfstate` produced by that loop as the candidate state to restore or promote.

## Restore the Original Remote State

Before uploading, refetch the current live generation. Do not reuse an old generation value.

```bash
CURRENT_GENERATION="$(gcloud storage objects describe "gs://$BUCKET/$OBJECT" --format='value(generation)')"

gcloud storage cp \
  "$WORKDIR/remote-original.$REMOTE_GENERATION.tfstate" \
  "gs://$BUCKET/$OBJECT" \
  --if-generation-match="$CURRENT_GENERATION"
```

If the command fails because the generation does not match, someone else changed the state first. Stop and inspect the new object history before retrying.

## Promote the New Local State

Promotion uses the same generation guard, but uploads the current working state:

```bash
CURRENT_GENERATION="$(gcloud storage objects describe "gs://$BUCKET/$OBJECT" --format='value(generation)')"

gcloud storage cp \
  "$WORKDIR/terraform.tfstate" \
  "gs://$BUCKET/$OBJECT" \
  --if-generation-match="$CURRENT_GENERATION"
```

After upload, verify a new generation exists:

```bash
gcloud storage objects describe "gs://$BUCKET/$OBJECT" \
  --format='json(generation,storage_url,update_time,size)'
```

## OpenTofu-Native Pull and Push

Use these only when intentionally attached to the real backend.

Pull the current backend state into a local file:

```bash
tofu state pull > before-change.tfstate
```

Push a known-good local file back into the configured backend:

```bash
tofu state push before-change.tfstate
```

`tofu state push` overwrites the configured backend state. Keep it for deliberate recovery, not casual experimentation.

## Reattach the Real Backend

When the remote state is final, use a clean stack directory and a local `backend.hcl` derived from the relevant example:

```bash
tofu init -reconfigure -backend-config=backend.hcl
```

Do not commit `backend.hcl`, `terraform.tfvars`, or any state snapshot.
