# Customer Dash Deploy Workflow

Source file:
- `/home/c10r/workspace/customer-dash/.github/workflows/deploy-gce.yml`

Observed structure:
- Trigger: `push` to `master`
- Permissions: `contents: read`, `id-token: write`
- Concurrency: `deploy-main`, `cancel-in-progress: false`
- Job env:
  - `INFRA_DIR=infra/opentofu`
  - `TOFU_BACKEND_BUCKET`
  - `TOFU_BACKEND_PREFIX`
  - `GCP_PROJECT_ID`
  - `GCP_WORKLOAD_IDENTITY_PROVIDER`
  - `GCP_DEPLOY_SERVICE_ACCOUNT`
- Steps:
  1. checkout
  2. validate required GitHub Actions variables
  3. authenticate to Google Cloud with Workload Identity Federation
  4. set up `gcloud`
  5. set up OpenTofu
  6. `tofu init -input=false` with backend bucket/prefix
  7. run `./scripts/deploy-gce-from-tofu.sh`

Porting guidance for this repo:
- Keep the same auth and backend-init structure.
- Rename the workflow file to `.github/workflows/deploy.yml`.
- Do not assume the default branch is `master`; inspect the current repo first.
- Keep the deploy script path repo-local.
