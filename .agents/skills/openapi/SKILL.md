---
name: openapi
description: Regenerate backend OpenAPI and frontend TypeScript schema for this repo. Use when controllers/DTOs change, when openapi.spec.json is stale, or when frontend API typing must be synced by curling localhost Swagger and running `npm run generate-api-types`.
---

# OpenAPI

## Overview
Refresh `openapi.spec.json` from the running local API, then regenerate frontend types in `www/src/schema.d.ts`.

## Quick Command
```bash
cd /home/c10r/workspace/golinks
.agents/skills/openapi/scripts/refresh-openapi.sh compose
# or:
.agents/skills/openapi/scripts/refresh-openapi.sh fresh-db
```

## Standard Workflow
1. Build API image.
```bash
cd /home/c10r/workspace/golinks
docker-compose build fsharp-starter-api
```

2. Start API only (avoid dashboard dependency).
```bash
cd /home/c10r/workspace/golinks
docker-compose up -d --no-deps fsharp-starter-api
```

3. Fetch Swagger JSON with the dev auth header.
```bash
cd /home/c10r/workspace/golinks
curl -fsS \
  -H 'X-Goog-Authenticated-User-Email: accounts.google.com:developer@example.com' \
  http://localhost:5001/swagger/v1/swagger.json \
  > openapi.spec.json
```

4. Regenerate frontend types.
```bash
cd /home/c10r/workspace/golinks/www
npm run generate-api-types
```

5. Verify expected paths exist.
```bash
cd /home/c10r/workspace/golinks
rg -n '"/link"|"/audit"|"/api/examples"' openapi.spec.json
cd /home/c10r/workspace/golinks/www
rg -n '"/link"|"/audit"|GoLinkResponseDto|AuditEventPagedResponseDto' src/schema.d.ts
```

6. Stop the compose service if needed.
```bash
cd /home/c10r/workspace/golinks
docker-compose stop fsharp-starter-api
```

## Fallback Workflow (Fresh DB Container)
Use this if the compose container has schema drift or stale volume state.

1. Build image.
```bash
cd /home/c10r/workspace/golinks
docker-compose build fsharp-starter-api
```

2. Run temporary container with fresh sqlite path.
```bash
docker rm -f golinks-openapi 2>/dev/null || true
docker run -d --rm \
  --name golinks-openapi \
  -p 5001:8080 \
  -e ASPNETCORE_ENVIRONMENT=Development \
  -e ConnectionStrings__DefaultConnection='Data Source=/tmp/openapi.db' \
  golinks-fsharp-starter-api
```

3. Fetch spec and regenerate types.
```bash
cd /home/c10r/workspace/golinks
curl -fsS \
  -H 'X-Goog-Authenticated-User-Email: accounts.google.com:developer@example.com' \
  http://localhost:5001/swagger/v1/swagger.json \
  > openapi.spec.json
cd /home/c10r/workspace/golinks/www
npm run generate-api-types
```

4. Clean up.
```bash
docker rm -f golinks-openapi
```

## Troubleshooting
### Error: `container name "/aspire-dashboard" is already in use`
Cause: `docker-compose up` tries to create dashboard container with fixed name.

Solution A:
```bash
cd /home/c10r/workspace/golinks
docker-compose up -d --no-deps fsharp-starter-api
```

Solution B:
```bash
docker rm -f aspire-dashboard
cd /home/c10r/workspace/golinks
docker-compose up -d
```

### Error: `permission denied while trying to connect to the docker API`
Cause: current session lacks docker socket privileges.

Solution:
```bash
# Run with elevated privileges in your agent/session.
# If on host shell, ensure your user has docker access.
groups | rg docker || echo 'user not in docker group'
```

### Error: `curl: (7) failed to open socket: Operation not permitted`
Cause: network-restricted sandbox session.

Solution:
```bash
# Re-run curl in a session with network permission / elevated mode.
curl -fsS http://localhost:5001/swagger/v1/swagger.json
```

### Error: `curl: (22) ... 401`
Cause: auth middleware requires authenticated user header.

Solution:
```bash
curl -fsS \
  -H 'X-Goog-Authenticated-User-Email: accounts.google.com:developer@example.com' \
  http://localhost:5001/swagger/v1/swagger.json \
  > /tmp/swagger.json
```

### Error: `IdentityProvisioningFailed ... SQLite Error 1: 'no such table: users'`
Cause: container points at stale sqlite DB without current schema.

Solution:
```bash
docker rm -f golinks-openapi 2>/dev/null || true
docker run -d --rm \
  --name golinks-openapi \
  -p 5001:8080 \
  -e ASPNETCORE_ENVIRONMENT=Development \
  -e ConnectionStrings__DefaultConnection='Data Source=/tmp/openapi.db' \
  golinks-fsharp-starter-api
```

### Error: `bind: address already in use` on `5001`
Cause: another process/container already owns `5001`.

Solution:
```bash
docker ps --format '{{.ID}}\t{{.Names}}\t{{.Ports}}' | rg '0\.0\.0\.0:5001|:::5001'
# stop conflicting container, then retry
```

## Expected Outputs
- `openapi.spec.json` updated at repo root.
- `www/src/schema.d.ts` regenerated from `../openapi.spec.json`.
