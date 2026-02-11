---
name: new-controller
description: Use when adding a new endpoint flow end-to-end across the hexagonal layers.
---

# Skill: new-controller

Use this to add a new endpoint flow end-to-end in hexagonal architecture.

## End-to-End Sequence
1. Domain
- Add/update value objects and entity behavior.
- Add domain events if state changes should be audited.

2. Application
- Add DTOs.
- Add command/result DU cases.
- Add handler branch and orchestration.
- Add repository/service interface changes.

3. Infrastructure
- Implement repository updates.
- Add EF conversions and DBUp migration scripts if schema changes.
- Add event persistence mappings if introducing events.

4. API
- Add controller endpoint.
- Treat API contracts as first-class: annotate explicit response status codes and typed DTOs for full OpenAPI output.
- Map request DTO -> command.
- Handle result DU mapping to HTTP responses.
- Add DI registrations.

5. Frontend (if API contract changed)
- Regenerate and commit `openapi.spec.json` plus frontend schema/types.
- Do not merge with temporary `any`/casts as an API bridge.
- Regenerate API types from OpenAPI.
- Update client call sites.

## Cross-Layer Consistency Rules
- Pagination must use one shared contract (`skip`, `take`, `totalCount`, paged DTO) with consistent defaults/bounds across API, validation, handlers, and frontend.
- Validate boundary inputs (especially pagination edges) and add regression tests where bugs escaped.
- Register all new services/handlers/repositories in `src/FsharpStarter.Api/src/Program.fs` in the same PR.
- Add startup/integration coverage that fails on missing DI registrations.

## Mandatory Validation After Each Layer
- After Domain edits:
  - `dotnet tool run fantomas .`
  - `dotnet test src/FsharpStarter.Domain/test/FsharpStarter.Domain.Tests.fsproj`
- After Application edits:
  - `dotnet tool run fantomas .`
  - `dotnet test src/FsharpStarter.Application/test/FsharpStarter.Application.Tests.fsproj`
- After Infrastructure edits:
  - `dotnet tool run fantomas .`
  - `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj`
- After API edits:
  - `dotnet tool run fantomas .`
  - `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~Controller"`
- Final:
  - `dotnet build FsharpStarter.sln -c Release`
  - `dotnet test FsharpStarter.sln`
  - `cd www && npm run check && npm run lint && npm test`
  - Regenerate and validate OpenAPI + frontend schema/types when controller/DTO signatures change.
