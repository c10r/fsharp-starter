---
name: openfga
description: Use when adding or modifying relationship-based authorization with OpenFGA.
---

# Skill: openfga

Use this when an app needs relationship-based authorization.

## Goal
Keep authorization model definitions and tuple writes in outer layers while keeping domain pure.
Baseline `FsharpStarter` uses `AllowAllAuthorizationService`; OpenFGA is opt-in.

## Architecture Placement
- Domain (`src/FsharpStarter.Domain`)
  - No OpenFGA client code.
  - Only business concepts that are authorization-agnostic (space/app/resource identities).
- Application (`src/FsharpStarter.Application`)
  - Define authorization contracts/interfaces.
  - Orchestrate checks in handlers through interfaces.
- Infrastructure (`src/FsharpStarter.Infrastructure`)
  - Implement OpenFGA client adapter (`IAuthorizationService` implementation).
  - Handle retries, tuple writes, and API mapping.
- API (`src/FsharpStarter.Api`)
  - Middleware/filters that call application contracts.
  - Optional bootstrap/init endpoints.

## Integration Anchors (Create/Enable)
- Add OpenFGA adapter implementation in infrastructure (for example `src/FsharpStarter.Infrastructure/src/Services/OpenFgaService.fs`).
- Add optional API bootstrap/init endpoint if you want runtime model write support.
- Register OpenFGA implementation in `src/FsharpStarter.Api/src/Program.fs` in place of `AllowAllAuthorizationService`.
- Register all dependent services/configuration bindings in the same PR so startup does not fail at runtime.
- Add startup/integration checks that fail if authorization dependencies are not wired.

## Recommended Refactor for Template Use
1. Keep application interfaces by default.
2. Add OpenFGA infrastructure implementation behind explicit DI registration.
3. Preserve non-OpenFGA fallback (`AllowAllAuthorizationService`) for starter baseline.
4. Keep detailed OpenFGA runbook content in this skill, not top-level README.

## Verification Commands
Run after each change:
1. `dotnet tool run fantomas .`
2. `dotnet build FsharpStarter.sln -c Release`
3. `dotnet test src/FsharpStarter.Infrastructure/test/FsharpStarter.Infrastructure.Tests.fsproj --filter "FullyQualifiedName~Authorization"`
4. `dotnet test FsharpStarter.sln`
