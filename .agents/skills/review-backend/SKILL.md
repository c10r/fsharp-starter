---
name: review-backend
description: Review backend changes after generating or modifying F#/.NET code in this hexagonal starter. Use when reviewing edits in Domain/Application/Infrastructure/API layers, EF/SQLite persistence, migrations, DI wiring, audit/event behavior, API contracts/OpenAPI, or backend tests before merge.
---

# Review Backend

Review backend code for regressions and missing cross-layer follow-through before merge.

## Review Workflow
1. Scan changed backend files in `src/FsharpStarter.Domain`, `src/FsharpStarter.Application`, `src/FsharpStarter.Infrastructure`, and `src/FsharpStarter.Api`.
2. List findings first, ordered by severity, with file references.
3. Flag behavioral regressions, runtime failure risks, schema drift, and missing tests.
4. Add a brief summary only after findings.

## Backend Review Checklist
- Verify API contracts are explicit.
- Require controller responses to declare status codes and typed DTOs.
- Require `openapi.spec.json` updates when DTO/controller signatures change.
- Reject temporary frontend bridge patterns (`any`/unsafe casts) caused by backend contract drift.

- Verify pagination consistency across layers.
- Enforce one contract (`skip`, `take`, `totalCount`, paged DTO).
- Enforce shared defaults and bounds in controller, validation, handler, and client-facing behavior.
- Require edge-case tests for invalid/large pagination inputs.

- Verify EF + F# nullability and option safety.
- Guard against null collection assumptions on hydrated entities.
- Normalize nullable list fields before mapping/iteration.
- Prefer explicit option equality in query predicates (`field = None` / `field = Some(...)`).

- Verify EF update behavior respects tracking.
- Prefer updating tracked entities when already loaded.
- Flag attach-and-update patterns that can create tracking conflicts.

- Verify migrations and model registration stay in lockstep.
- Require migration SQL plus project registration (`EmbeddedResource` or equivalent).
- Verify new required columns include safe defaults for existing rows.
- Require startup/integration checks that fail fast when expected columns are absent.

- Verify audit/event schema compatibility.
- Ensure display-critical fields (for example entity names) are present for create/delete events.
- Ensure update events support lookup-based enrichment when payload fields are missing.
- Preserve backward compatibility with tolerant handling of legacy event payload shapes.

- Verify DI wiring completeness.
- Ensure new handlers/services/repositories are registered in `src/FsharpStarter.Api/src/Program.fs`.
- Require startup/integration tests that fail when registrations are missing.

- Verify regression tests accompany bug fixes.
- Require a test at the layer where the bug escaped.
- Prefer realistic regression fixtures (legacy payloads, null collections, boundary inputs).

## F# Architecture Guardrails
- Keep domain strongly typed and framework-free.
- Parse/validate boundary `string` data into domain value objects early.
- Prefer explicit pattern matching and domain error unions.
- Avoid introducing nullable state into domain models.

## Quality Gates
Run before merge:
1. `dotnet tool run fantomas .`
2. `dotnet build FsharpStarter.sln -c Release`
3. `dotnet test FsharpStarter.sln`
4. `cd www && npm run check && npm run lint && npm test`
