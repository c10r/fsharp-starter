#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
MODE="${1:-compose}"

cd "$REPO_ROOT"

fetch_spec() {
  curl -fsS \
    -H 'X-Goog-Authenticated-User-Email: accounts.google.com:developer@example.com' \
    http://localhost:5001/swagger/v1/swagger.json \
    > "$REPO_ROOT/openapi.spec.json"
}

generate_types() {
  (cd "$REPO_ROOT/www" && npm run generate-api-types)
}

cleanup_temp() {
  docker rm -f golinks-openapi >/dev/null 2>&1 || true
}

if [[ "$MODE" == "compose" ]]; then
  docker-compose build fsharp-starter-api
  docker-compose up -d --no-deps fsharp-starter-api
  fetch_spec
  generate_types
  echo "OpenAPI refreshed via compose service."
elif [[ "$MODE" == "fresh-db" ]]; then
  docker-compose build fsharp-starter-api
  cleanup_temp
  docker run -d --rm \
    --name golinks-openapi \
    -p 5001:8080 \
    -e ASPNETCORE_ENVIRONMENT=Development \
    -e ConnectionStrings__DefaultConnection='Data Source=/tmp/openapi.db' \
    golinks-fsharp-starter-api >/dev/null

  # Wait for API startup
  for _ in $(seq 1 30); do
    if fetch_spec; then
      break
    fi
    sleep 1
  done

  generate_types
  cleanup_temp
  echo "OpenAPI refreshed via fresh-db temp container."
else
  echo "Usage: $0 [compose|fresh-db]"
  exit 1
fi
