#!/usr/bin/env bash
set -euo pipefail

required_vars=(
  GCP_PROJECT_ID
  GCP_REGION
  GCP_ARTIFACT_REPO
  GCP_VM_ZONE
  FSHARP_STARTER_IAP_JWT_AUDIENCE
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required env var: $var" >&2
    exit 1
  fi
done

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is required" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

resolve_target_vm_name() {
  if [[ -n "${GCP_VM_NAME:-}" ]]; then
    echo "${GCP_VM_NAME}"
    return 0
  fi

  if [[ -n "${GCP_MIG_NAME:-}" ]]; then
    local instance_name
    instance_name="$(gcloud compute instance-groups managed list-instances "${GCP_MIG_NAME}" --project "${GCP_PROJECT_ID}" --zone "${GCP_VM_ZONE}" --format='value(instance.basename())' 2>/dev/null | head -n1)"

    if [[ -n "${instance_name}" ]]; then
      echo "${instance_name}"
      return 0
    fi

    echo "Managed instance group ${GCP_MIG_NAME} has no instances in zone ${GCP_VM_ZONE}; trying fallbacks." >&2
  fi

  if [[ -n "${GCP_BLUEGREEN_VM_NAME:-}" ]]; then
    if gcloud compute instances describe "${GCP_BLUEGREEN_VM_NAME}" --zone "${GCP_VM_ZONE}" --project "${GCP_PROJECT_ID}" --format='value(name)' >/dev/null 2>&1; then
      echo "${GCP_BLUEGREEN_VM_NAME}"
      return 0
    fi
  fi

  if [[ -n "${GCP_BACKEND_SERVICE:-}" ]]; then
    local backend_vm_name
    backend_vm_name="$(
      gcloud compute backend-services get-health "${GCP_BACKEND_SERVICE}" \
        --project "${GCP_PROJECT_ID}" \
        --global \
        --format='value(status.healthStatus.instance)' 2>/dev/null \
      | sed -n 's|.*/instances/\([^/]*\)$|\1|p' \
      | head -n1
    )"

    if [[ -n "${backend_vm_name}" ]]; then
      echo "${backend_vm_name}"
      return 0
    fi
  fi

  local labeled_vm_name
  labeled_vm_name="$(
    gcloud compute instances list \
      --project "${GCP_PROJECT_ID}" \
      --filter="zone:(${GCP_VM_ZONE}) AND labels.app=fsharp-starter AND status=RUNNING" \
      --format='value(name)' 2>/dev/null \
      | head -n1
  )"
  if [[ -n "${labeled_vm_name}" ]]; then
    echo "${labeled_vm_name}"
    return 0
  fi

  echo "Could not resolve target VM. Set GCP_VM_NAME explicitly or ensure a running fsharp-starter VM exists in zone ${GCP_VM_ZONE}." >&2
  return 1
}

IMAGE_NAME="${IMAGE_NAME:-fsharp-starter-api}"
REMOTE_DIR="${REMOTE_DIR:-/opt/fsharp-starter}"
TAG="${TAG:-$(git rev-parse --short HEAD)}"
REGISTRY_HOST="${GCP_REGION}-docker.pkg.dev"
IMAGE_URI="${REGISTRY_HOST}/${GCP_PROJECT_ID}/${GCP_ARTIFACT_REPO}/${IMAGE_NAME}:${TAG}"
LATEST_IMAGE_URI="${REGISTRY_HOST}/${GCP_PROJECT_ID}/${GCP_ARTIFACT_REPO}/${IMAGE_NAME}:latest"
USE_IAP_TUNNEL="${USE_IAP_TUNNEL:-true}"
PUBLISH_LATEST="${PUBLISH_LATEST:-true}"
TARGET_VM_NAME="$(resolve_target_vm_name)"

if [[ -z "${TARGET_VM_NAME}" ]]; then
  echo "Resolved target VM name is empty." >&2
  exit 1
fi

if [[ "${TARGET_VM_NAME}" == "${GCP_VM_ZONE}" ]]; then
  echo "Resolved target VM name '${TARGET_VM_NAME}' matches zone '${GCP_VM_ZONE}', which is invalid." >&2
  exit 1
fi

if ! gcloud compute instances describe "${TARGET_VM_NAME}" --zone "${GCP_VM_ZONE}" --project "${GCP_PROJECT_ID}" --format='value(name)' >/dev/null; then
  echo "Target VM '${TARGET_VM_NAME}' not found in zone '${GCP_VM_ZONE}' (project '${GCP_PROJECT_ID}')." >&2
  exit 1
fi

ssh_iap_flag=()
if [[ "${USE_IAP_TUNNEL}" == "true" ]]; then
  ssh_iap_flag=(--tunnel-through-iap)
fi

echo "Building image: ${IMAGE_URI}"
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet
docker build --platform linux/amd64 -f src/FsharpStarter.Api/Dockerfile -t "${IMAGE_URI}" .
docker push "${IMAGE_URI}"

if [[ "${PUBLISH_LATEST}" == "true" && "${TAG}" != "latest" ]]; then
  echo "Tagging and pushing: ${LATEST_IMAGE_URI}"
  docker tag "${IMAGE_URI}" "${LATEST_IMAGE_URI}"
  docker push "${LATEST_IMAGE_URI}"
fi

tmp_env_file="$(mktemp)"

FSHARP_STARTER_VALIDATE_IAP_JWT="${FSHARP_STARTER_VALIDATE_IAP_JWT:-true}"
FSHARP_STARTER_GOOGLE_DIRECTORY_ENABLED="${FSHARP_STARTER_GOOGLE_DIRECTORY_ENABLED:-false}"
FSHARP_STARTER_GOOGLE_DIRECTORY_ADMIN_USER_EMAIL="${FSHARP_STARTER_GOOGLE_DIRECTORY_ADMIN_USER_EMAIL:-}"
FSHARP_STARTER_GOOGLE_DIRECTORY_SCOPE="${FSHARP_STARTER_GOOGLE_DIRECTORY_SCOPE:-https://www.googleapis.com/auth/admin.directory.user.readonly}"
FSHARP_STARTER_GOOGLE_DIRECTORY_OU_KEY_PREFIX="${FSHARP_STARTER_GOOGLE_DIRECTORY_OU_KEY_PREFIX:-ou}"
FSHARP_STARTER_GOOGLE_DIRECTORY_INCLUDE_OU_HIERARCHY="${FSHARP_STARTER_GOOGLE_DIRECTORY_INCLUDE_OU_HIERARCHY:-true}"
FSHARP_STARTER_GOOGLE_DIRECTORY_CUSTOM_KEY_PREFIX="${FSHARP_STARTER_GOOGLE_DIRECTORY_CUSTOM_KEY_PREFIX:-custom}"
FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME="${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME:-}"
FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_FILE="${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_FILE:-}"

if [[ -z "${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_FILE}" && -n "${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME}" ]]; then
  FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_FILE="/var/secrets/google/directory-dwd-key.json"
fi

cat > "${tmp_env_file}" <<EOF
FSHARP_STARTER_IMAGE=${IMAGE_URI}
FSHARP_STARTER_IAP_JWT_AUDIENCE=${FSHARP_STARTER_IAP_JWT_AUDIENCE}
FSHARP_STARTER_ORG_ADMIN_EMAIL=${FSHARP_STARTER_ORG_ADMIN_EMAIL:-}
FSHARP_STARTER_VALIDATE_IAP_JWT=${FSHARP_STARTER_VALIDATE_IAP_JWT}
FSHARP_STARTER_GOOGLE_DIRECTORY_ENABLED=${FSHARP_STARTER_GOOGLE_DIRECTORY_ENABLED}
FSHARP_STARTER_GOOGLE_DIRECTORY_ADMIN_USER_EMAIL=${FSHARP_STARTER_GOOGLE_DIRECTORY_ADMIN_USER_EMAIL}
FSHARP_STARTER_GOOGLE_DIRECTORY_SCOPE=${FSHARP_STARTER_GOOGLE_DIRECTORY_SCOPE}
FSHARP_STARTER_GOOGLE_DIRECTORY_OU_KEY_PREFIX=${FSHARP_STARTER_GOOGLE_DIRECTORY_OU_KEY_PREFIX}
FSHARP_STARTER_GOOGLE_DIRECTORY_INCLUDE_OU_HIERARCHY=${FSHARP_STARTER_GOOGLE_DIRECTORY_INCLUDE_OU_HIERARCHY}
FSHARP_STARTER_GOOGLE_DIRECTORY_CUSTOM_KEY_PREFIX=${FSHARP_STARTER_GOOGLE_DIRECTORY_CUSTOM_KEY_PREFIX}
FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME=${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME}
FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_FILE=${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_FILE}
FSHARP_STARTER_DATA_ROOT=${FSHARP_STARTER_DATA_ROOT:-/mnt/fsharp-starter-data}
EOF

echo "Copying compose bundle to VM: ${TARGET_VM_NAME}"
REMOTE_STAGE_DIR="/tmp/fsharp-starter-deploy-$$"
gcloud compute ssh "${TARGET_VM_NAME}" --zone "${GCP_VM_ZONE}" "${ssh_iap_flag[@]}" --command "set -euo pipefail; sudo mkdir -p '${REMOTE_DIR}'; mkdir -p '${REMOTE_STAGE_DIR}'"
gcloud compute scp docker-compose.gce.yml "${tmp_env_file}" \
  "${TARGET_VM_NAME}:${REMOTE_STAGE_DIR}/" \
  --zone "${GCP_VM_ZONE}" \
  "${ssh_iap_flag[@]}"
gcloud compute ssh "${TARGET_VM_NAME}" --zone "${GCP_VM_ZONE}" "${ssh_iap_flag[@]}" --command "
  set -euo pipefail
  sudo install -m 0644 '${REMOTE_STAGE_DIR}/docker-compose.gce.yml' '${REMOTE_DIR}/docker-compose.gce.yml'
  sudo install -m 0600 '${REMOTE_STAGE_DIR}/$(basename "${tmp_env_file}")' '${REMOTE_DIR}/.env'
  rm -rf '${REMOTE_STAGE_DIR}'
"

echo "Deploying containers on VM"
gcloud compute ssh "${TARGET_VM_NAME}" --zone "${GCP_VM_ZONE}" "${ssh_iap_flag[@]}" --command "
  set -euo pipefail
  cd ${REMOTE_DIR}
  if ! command -v docker >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo apt-get install -y docker-compose-plugin || sudo apt-get install -y docker-compose-v2 || sudo apt-get install -y docker-compose
    sudo systemctl enable docker
    sudo systemctl start docker
  fi
  TOKEN=\$(curl -fsS -H \"Metadata-Flavor: Google\" \"http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token\" | sed -n 's/.*\"access_token\":\"\\([^\"]*\\)\".*/\\1/p')
  if [[ -z \"\${TOKEN}\" ]]; then
    echo \"Failed to obtain VM service account access token for Artifact Registry\" >&2
    exit 1
  fi
  echo \"\${TOKEN}\" | sudo docker login -u oauth2accesstoken --password-stdin \"https://${REGISTRY_HOST}\"
  if [[ -n \"\${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME:-}\" ]]; then
    sudo mkdir -p /opt/fsharp-starter/creds
    gcloud secrets versions access latest \
      --secret \"\${FSHARP_STARTER_GOOGLE_DIRECTORY_CREDENTIALS_SECRET_NAME}\" \
      --project \"${GCP_PROJECT_ID}\" \
      | sudo tee /opt/fsharp-starter/creds/directory-dwd-key.json >/dev/null
    sudo chmod 600 /opt/fsharp-starter/creds/directory-dwd-key.json
  fi
  sudo mkdir -p \"${FSHARP_STARTER_DATA_ROOT}/fsharp-starter-db\" \"${FSHARP_STARTER_DATA_ROOT}/openfga\"
  sudo chmod 0777 \"${FSHARP_STARTER_DATA_ROOT}/fsharp-starter-db\" \"${FSHARP_STARTER_DATA_ROOT}/openfga\"
  if sudo docker compose version >/dev/null 2>&1; then
    sudo docker compose -f docker-compose.gce.yml --env-file .env pull
    sudo docker compose -f docker-compose.gce.yml --env-file .env up -d --remove-orphans
  elif command -v docker-compose >/dev/null 2>&1; then
    sudo docker-compose -f docker-compose.gce.yml --env-file .env pull
    sudo docker-compose -f docker-compose.gce.yml --env-file .env up -d --remove-orphans
  else
    echo \"Neither 'docker compose' nor 'docker-compose' is available on VM\" >&2
    exit 1
  fi
  sudo docker image prune -f
"

rm -f "${tmp_env_file}"

echo "Deployment finished: ${IMAGE_URI}"
